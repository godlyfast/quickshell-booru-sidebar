pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../common"
import "../common/utils"
import "../common/functions/file_utils.js" as FileUtils
import "../common/functions/shell_utils.js" as ShellUtils
import "../../services"

/**
 * Singleton service handling image downloads.
 * Supports Grabber downloads with artist-aware filenames and curl fallback.
 */
Singleton {
    id: root

    // Download paths
    readonly property string downloadPath: FileUtils.trimFileProtocol(Directories.homeDir) + "/Pictures/booru"
    readonly property string nsfwPath: FileUtils.trimFileProtocol(Directories.homeDir) + "/Pictures/booru/nsfw"
    readonly property string wallpaperPath: FileUtils.trimFileProtocol(Directories.homeDir) + "/Pictures/wallpapers"

    // Current download context (for fallback handling)
    property var currentImageData: null
    property string currentProvider: ""

    /**
     * Download image using Grabber or curl fallback.
     * @param imageData - Image object with file_url, is_nsfw, id
     * @param provider - Provider key for Grabber source lookup
     * @param isWallpaper - If true, save to wallpaper folder
     */
    function downloadImage(imageData, provider, isWallpaper) {
        if (!imageData || !imageData.file_url) return

        root.currentImageData = imageData
        root.currentProvider = provider

        const targetPath = isWallpaper ? root.wallpaperPath : (imageData.is_nsfw ? root.nsfwPath : root.downloadPath)
        const notifyTitle = isWallpaper ? "Wallpaper saved" : "Download complete"
        const grabberSource = Booru.getGrabberSource(provider)

        Logger.info("DownloadManager", `Download started: id=${imageData.id} provider=${provider} isWallpaper=${isWallpaper}`)
        Logger.debug("DownloadManager", `Target: ${targetPath}`)

        if (grabberSource && grabberSource.length > 0) {
            // Use Grabber for supported providers
            Logger.debug("DownloadManager", `Using Grabber source: ${grabberSource}`)
            const downloader = isWallpaper ? wallpaperDownloader : previewDownloader
            downloader.source = grabberSource
            downloader.imageId = String(imageData.id)
            downloader.outputPath = targetPath
            downloader.notifyTitle = notifyTitle
            downloader.startDownload()
        } else {
            // Fallback to curl
            Logger.debug("DownloadManager", "Using curl fallback (no Grabber source)")
            curlDownload(imageData, targetPath, notifyTitle)
        }
    }

    /**
     * Curl fallback for providers without Grabber support.
     */
    function curlDownload(imageData, targetPath, notifyTitle) {
        let fileName = imageData.file_url.substring(imageData.file_url.lastIndexOf('/') + 1)
        const queryIdx = fileName.indexOf('?')
        if (queryIdx > 0) fileName = fileName.substring(0, queryIdx)
        fileName = decodeURIComponent(fileName)

        Quickshell.execDetached(["bash", "-c",
            "mkdir -p '" + ShellUtils.shellEscape(targetPath) + "' && " +
            "curl -sL -A 'Mozilla/5.0 BooruSidebar/1.0' '" + ShellUtils.shellEscape(imageData.file_url) + "' " +
            "-o '" + ShellUtils.shellEscape(targetPath) + "/" + ShellUtils.shellEscape(fileName) + "' && " +
            "notify-send '" + notifyTitle + "' '" + ShellUtils.shellEscape(targetPath + "/" + fileName) + "' -a 'Booru'"
        ])
    }

    /**
     * Copy URL to clipboard using wl-copy.
     * @param url - URL to copy
     */
    function copyToClipboard(url) {
        if (!url) return
        Logger.info("DownloadManager", `Copying URL to clipboard: ${url.substring(0, 60)}...`)
        clipboardProcess.command = ["wl-copy", url]
        clipboardProcess.running = true
    }

    // Grabber downloader for regular downloads
    GrabberDownloader {
        id: previewDownloader
        filenameTemplate: Booru.filenameTemplate
        property string notifyTitle: "Download complete"

        onDone: function(success, message) {
            if (success) {
                Logger.info("DownloadManager", `Grabber download complete: ${message}`)
                Quickshell.execDetached(["notify-send", notifyTitle, message, "-a", "Booru"])
            } else if (root.currentImageData && root.currentImageData.file_url) {
                Logger.warn("DownloadManager", "Grabber failed, falling back to curl")
                const targetPath = root.currentImageData.is_nsfw ? root.nsfwPath : root.downloadPath
                root.curlDownload(root.currentImageData, targetPath, notifyTitle)
            }
        }
    }

    // Grabber downloader for wallpaper saves
    GrabberDownloader {
        id: wallpaperDownloader
        filenameTemplate: Booru.filenameTemplate
        property string notifyTitle: "Wallpaper saved"

        onDone: function(success, message) {
            if (success) {
                Logger.info("DownloadManager", `Wallpaper saved: ${message}`)
                Quickshell.execDetached(["notify-send", notifyTitle, message, "-a", "Booru"])
            } else if (root.currentImageData && root.currentImageData.file_url) {
                Logger.warn("DownloadManager", "Grabber wallpaper failed, falling back to curl")
                root.curlDownload(root.currentImageData, root.wallpaperPath, notifyTitle)
            }
        }
    }

    // Clipboard process for yank command
    Process {
        id: clipboardProcess
        onExited: function(code, status) {
            if (code === 0) {
                Quickshell.execDetached(["notify-send", "URL copied", "Image URL copied to clipboard", "-a", "Booru"])
            }
        }
    }
}
