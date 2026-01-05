import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../common"
import "../../common/widgets"
import "../../common/utils"
import "../../../services" as Services

/**
 * Individual booru image card with context menu.
 */
Button {
    id: root
    property var imageData
    property real rowHeight
    property bool manualDownload: false
    property string provider: ""
    property string previewDownloadPath
    property string downloadPath
    property string nsfwPath

    // Preview signals - emitted on hover for full-size preview
    signal showPreview(var imageData, string cachedSource, bool manualDownload, string provider)
    signal hidePreview()
    signal updatePreviewSource(string cachedSource)  // Emitted when download completes while preview is active

    property string fileName: {
        var url = imageData.file_url ? imageData.file_url : ""
        var path = url.substring(url.lastIndexOf('/') + 1)
        // Strip query parameters (e.g., Sankaku signed URLs)
        var queryIdx = path.indexOf('?')
        if (queryIdx > 0) path = path.substring(0, queryIdx)
        return decodeURIComponent(path)
    }
    // Preview filename - based on preview_url for correct caching when different from file_url
    property string previewFileName: {
        var url = imageData.preview_url ? imageData.preview_url : (imageData.file_url || "")
        var path = url.substring(url.lastIndexOf('/') + 1)
        var queryIdx = path.indexOf('?')
        if (queryIdx > 0) path = path.substring(0, queryIdx)
        return decodeURIComponent(path)
    }
    property string filePath: root.previewDownloadPath + "/" + root.previewFileName
    property real imageRadius: Appearance.rounding.small

    property bool showActions: false

    // Shell escape helper - escapes single quotes for safe shell string embedding
    // 'foo'bar' -> 'foo'\''bar' (end quote, escaped quote, start quote)
    function shellEscape(str) {
        if (!str) return "";
        return str.replace(/'/g, "'\\''");
    }

    // Video detection - fallback to extracting from URL if file_ext not provided
    property string fileExt: {
        var ext = imageData.file_ext ? imageData.file_ext.toLowerCase() : ""
        if (!ext && imageData.file_url) {
            // Extract extension, stripping query parameters (for signed URLs like Sankaku)
            var url = imageData.file_url
            var queryIdx = url.indexOf('?')
            if (queryIdx > 0) url = url.substring(0, queryIdx)
            ext = url.split('.').pop().toLowerCase()
        }
        return ext
    }
    property bool isVideo: (fileExt === "mp4" || fileExt === "webm")
    // Check both API-provided extension AND actual cached file extension
    // (zerochan may have .gif content served from .jpg URL via fallback)
    property bool isGif: fileExt === "gif" || cachedImageSource.toLowerCase().endsWith(".gif")
    property bool isArchive: (fileExt === "zip" || fileExt === "rar" || fileExt === "7z")  // Danbooru image packs

    // File paths for download status checks
    property string savedFilePath: root.downloadPath + "/" + root.fileName
    property string savedNsfwFilePath: root.nsfwPath + "/" + root.fileName
    property string wallpaperFilePath: root.downloadPath.replace(/\/booru$/, '/wallpapers') + "/" + root.fileName

    // File existence state (checked async on load)
    property bool isSavedLocally: false
    property bool isSavedAsWallpaper: false

    // Local file paths for progressive loading (manual download providers)
    property string localHighResSource: ""

    // Universal cache - applies to ALL providers, not just manualDownload
    // CacheIndex provides instant O(1) lookup, no need for per-image Process
    property bool universalCacheChecked: Services.CacheIndex.initialized
    property string cachedImageSource: {
        if (!Services.CacheIndex.initialized) return ""
        // Look up by filename (without hires_ prefix, CacheIndex checks variants)
        return Services.CacheIndex.lookup(root.fileName)
    }

    // Local dimension overrides - don't mutate shared model data
    property int localWidth: 0
    property int localHeight: 0
    property real localAspectRatio: 0

    // Effective dimensions - prefer model data, fall back to locally computed
    property int effectiveWidth: root.imageData.width || root.localWidth || 300
    property int effectiveHeight: root.imageData.height || root.localHeight || 300
    property real effectiveAspectRatio: root.imageData.aspect_ratio || root.localAspectRatio || 1

    // Check if preview and file URLs are the same (e.g., Sankaku uses file_url for both)
    // Skip separate hi-res download when they match - saves bandwidth and time
    property bool previewIsFullRes: {
        var previewUrl = (root.imageData.preview_url || "").split("?")[0]
        var fileUrl = (root.imageData.file_url || "").split("?")[0]
        return previewUrl.length > 0 && previewUrl === fileUrl
    }

    // Manual download for preview images (providers that block direct requests)
    ImageDownloaderProcess {
        id: imageDownloader
        enabled: root.manualDownload && !root.isGif && !root.isVideo
        filePath: root.filePath
        sourceUrl: root.imageData.preview_url ? root.imageData.preview_url : ""
        property string downloadedPath: ""
        onDone: (path, width, height) => {
            downloadedPath = path
            // Store dimensions locally instead of mutating shared model
            if (!root.imageData.width || !root.imageData.height) {
                root.localWidth = width
                root.localHeight = height
                root.localAspectRatio = width / height
            }
            // If preview is already full-res (e.g., Sankaku), use it directly
            if (root.previewIsFullRes && path.length > 0) {
                root.localHighResSource = "file://" + path
            }
        }
    }

    // Manual download for high-res images (triggered after preview loads)
    property string highResFileName: {
        var url = imageData.file_url ? imageData.file_url : ""
        var path = url.substring(url.lastIndexOf('/') + 1)
        // Strip query parameters (e.g., Sankaku signed URLs)
        var queryIdx = path.indexOf('?')
        if (queryIdx > 0) path = path.substring(0, queryIdx)
        return "hires_" + decodeURIComponent(path)
    }
    property string highResFilePath: root.previewDownloadPath + "/" + root.highResFileName

    // Grabber uses md5-based filename for Danbooru
    property string grabberHighResPath: root.previewDownloadPath + "/hires_" + (root.imageData.md5 ? root.imageData.md5 : root.imageData.id) + "." + root.fileExt

    // Unified cache check for all manual download providers
    property bool highResCacheChecked: false
    property string effectiveHighResPath: root.provider === "danbooru" ? root.grabberHighResPath : root.highResFilePath

    Process {
        id: highResCacheCheck
        running: root.manualDownload && !root.isGif && !root.isVideo && !root.isArchive && root.effectiveHighResPath.length > 0 && !root.highResCacheChecked
        command: ["test", "-f", root.effectiveHighResPath]
        onExited: function(code, status) {
            root.highResCacheChecked = true
            if (code === 0) {
                // File exists - use it immediately
                root.localHighResSource = "file://" + root.effectiveHighResPath
            }
            // If not cached, downloaders below will trigger
        }
    }

    // Universal cache check - REPLACED by CacheIndex singleton for O(1) lookups
    // Previously spawned a bash Process per image; now uses in-memory index
    // Process retained for backwards compatibility but never runs
    Process {
        id: universalCacheCheck
        running: false  // Disabled - CacheIndex handles cache lookups
        command: ["true"]
    }

    // Download hi-res to cache for non-manual providers (after cache check)
    ImageDownloaderProcess {
        id: universalHighResDownloader
        enabled: !root.manualDownload && !root.isGif && !root.isVideo && !root.isArchive
                 && root.universalCacheChecked && root.cachedImageSource === ""
                 && root.imageData.file_url && root.imageData.file_url.length > 0
        filePath: root.highResFilePath
        sourceUrl: root.imageData.file_url ? root.imageData.file_url : ""
        // Zerochan provides extension fallbacks (.png, .jpeg, .webp) since API doesn't specify extension
        fallbackUrls: root.imageData.file_url_fallbacks ? root.imageData.file_url_fallbacks : []

        onDone: function(path, width, height) {
            if (path.length > 0) {
                var cachedPath = "file://" + path
                root.cachedImageSource = cachedPath
                // Register in CacheIndex for instant future lookups
                Services.CacheIndex.register(root.highResFileName, path)
                // Update preview if it's showing this image
                if (root.isPreviewActive) {
                    root.updatePreviewSource(cachedPath)
                }
            }
        }
    }

    ImageDownloaderProcess {
        id: highResDownloader
        // Use curl for non-Danbooru providers (only if not cached and preview isn't already full-res)
        enabled: root.manualDownload && root.provider !== "danbooru" && !root.previewIsFullRes && !root.isGif && !root.isVideo && !root.isArchive && imageDownloader.downloadedPath.length > 0 && root.highResCacheChecked && root.localHighResSource === ""
        filePath: root.highResFilePath
        sourceUrl: root.imageData.file_url ? root.imageData.file_url : ""
        fallbackUrls: root.imageData.file_url_fallbacks ? root.imageData.file_url_fallbacks : []
        onDone: (path, width, height) => {
            if (path.length > 0) {
                var cachedPath = "file://" + path
                root.localHighResSource = cachedPath
                // Update preview if it's showing this image
                if (root.isPreviewActive) {
                    root.updatePreviewSource(cachedPath)
                }
            } else {
                // High-res blocked - use preview as fallback
                root.localHighResSource = "file://" + imageDownloader.downloadedPath
            }
        }
    }

    GrabberDownloader {
        id: grabberHighResDownloader
        source: "danbooru.donmai.us"
        imageId: root.imageData.id ? String(root.imageData.id) : ""
        outputPath: root.previewDownloadPath
        filenameTemplate: "hires_%md5%.%ext%"
        user: Services.Booru.danbooruLogin
        password: Services.Booru.danbooruApiKey
        onDone: (success, message) => {
            if (success) {
                var cachedPath = "file://" + root.grabberHighResPath
                root.localHighResSource = cachedPath
                // Update preview if it's showing this image
                if (root.isPreviewActive) {
                    root.updatePreviewSource(cachedPath)
                }
            } else {
                // Fallback to preview
                root.localHighResSource = "file://" + imageDownloader.downloadedPath
            }
        }
    }

    // Trigger Grabber download for Danbooru (only if not cached)
    Timer {
        id: grabberTrigger
        interval: 100
        running: root.manualDownload && root.provider === "danbooru" && !root.isGif && !root.isVideo && !root.isArchive && imageDownloader.downloadedPath.length > 0 && !grabberHighResDownloader.downloading && root.localHighResSource === "" && root.highResCacheChecked
        onTriggered: grabberHighResDownloader.startDownload()
    }

    // Manual download for GIFs (providers that block direct requests)
    property string gifFileName: {
        var url = modelData.file_url ? modelData.file_url : ""
        var path = url.substring(url.lastIndexOf('/') + 1)
        // Strip query parameters (e.g., Sankaku signed URLs)
        var queryIdx = path.indexOf('?')
        if (queryIdx > 0) path = path.substring(0, queryIdx)
        return decodeURIComponent(path)
    }
    property string gifFilePath: root.previewDownloadPath + "/gif_" + root.gifFileName
    property string localGifSource: ""

    // Universal GIF cache - uses CacheIndex for O(1) lookups
    property bool gifCacheChecked: Services.CacheIndex.initialized
    property string cachedGifSource: {
        if (!Services.CacheIndex.initialized || !root.isGif) return ""
        // Look up GIF with gif_ prefix variant
        var cached = Services.CacheIndex.lookup("gif_" + root.gifFileName)
        if (cached.length > 0) return cached
        // Also check without prefix (user downloads)
        return Services.CacheIndex.lookup(root.gifFileName)
    }

    ImageDownloaderProcess {
        id: gifDownloader
        enabled: root.manualDownload && root.isGif
        filePath: root.gifFilePath
        sourceUrl: modelData.file_url ? modelData.file_url : ""
        onDone: function(path, width, height) {
            if (path.length > 0) {
                root.localGifSource = "file://" + path
            } else {
                // GIF blocked (Danbooru Cloudflare) - use preview as static fallback
                root.localGifSource = modelData.preview_url ? modelData.preview_url : ""
            }
        }
    }

    // Universal GIF cache check - REPLACED by CacheIndex singleton
    Process {
        id: gifCacheCheck
        running: false  // Disabled - CacheIndex handles cache lookups
        command: ["true"]
    }

    // Download GIF to cache for non-manual providers
    ImageDownloaderProcess {
        id: universalGifDownloader
        enabled: root.isGif && !root.manualDownload && root.gifCacheChecked
                 && root.cachedGifSource === "" && root.imageData.file_url
        filePath: root.gifFilePath
        sourceUrl: root.imageData.file_url ? root.imageData.file_url : ""
        onDone: function(path, width, height) {
            if (path.length > 0) {
                var cachedPath = "file://" + path
                root.cachedGifSource = cachedPath
                // Register in CacheIndex for instant future lookups
                Services.CacheIndex.register("gif_" + root.gifFileName, path)
                // Update preview if it's showing this GIF
                if (root.isPreviewActive) {
                    root.updatePreviewSource(cachedPath)
                }
            }
        }
    }

    // Ugoira (animated ZIP) support
    // Danbooru provides pre-converted WebM at sample_url (large_file_url)
    // We download this directly instead of downloading ZIP + converting
    property string ugoiraVideoPath: root.previewDownloadPath + "/ugoira_" + (root.imageData.md5 ? root.imageData.md5 : root.imageData.id) + ".webm"
    property string ugoiraSampleUrl: root.imageData.sample_url ? root.imageData.sample_url : ""
    property string localUgoiraSource: ""
    property bool ugoiraCacheChecked: false
    property bool ugoiraDownloading: false

    // Check if WebM already exists in cache
    Process {
        id: ugoiraCacheCheck
        running: root.isArchive && root.ugoiraVideoPath.length > 0 && !root.ugoiraCacheChecked
        command: ["test", "-f", root.ugoiraVideoPath]
        onExited: (code, status) => {
            root.ugoiraCacheChecked = true
            if (code === 0) {
                root.localUgoiraSource = "file://" + root.ugoiraVideoPath
            }
        }
    }

    // Download pre-converted WebM from sample_url (works for Danbooru, AIBooru, etc.)
    // Uses bash to create cache directory, then curl with browser headers
    Process {
        id: ugoiraDownloader
        property bool downloading: false
        running: false
        command: ["bash", "-c",
            "mkdir -p \"$(dirname '" + root.ugoiraVideoPath + "')\" && " +
            "curl -sL '" + root.ugoiraSampleUrl + "' " +
            "-H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36' " +
            "-o '" + root.ugoiraVideoPath + "'"
        ]

        onRunningChanged: {
            if (running) downloading = true
        }

        onExited: (code, status) => {
            downloading = false
            root.ugoiraDownloading = false
            if (code === 0) {
                var cachedPath = "file://" + root.ugoiraVideoPath
                root.localUgoiraSource = cachedPath
                // Update preview if it's showing this ugoira
                if (root.isPreviewActive) {
                    root.updatePreviewSource(cachedPath)
                }
            }
        }
    }

    // Timer to trigger download after cache check
    // Uses repeat: false and internal guard to prevent race conditions
    Timer {
        id: ugoiraDownloadTrigger
        interval: 100
        repeat: false
        running: root.isArchive && root.ugoiraCacheChecked && root.localUgoiraSource === "" && root.ugoiraSampleUrl.length > 0
        onTriggered: {
            // Guard against race condition - check flags inside handler
            if (root.ugoiraDownloading || ugoiraDownloader.downloading) return
            root.ugoiraDownloading = true
            ugoiraDownloader.running = true
        }
    }

    // Universal video cache - uses CacheIndex for O(1) lookups
    property bool videoCacheChecked: Services.CacheIndex.initialized
    property string cachedVideoSource: {
        if (!Services.CacheIndex.initialized || !root.isVideo) return ""
        // Look up video with video_ prefix
        var videoName = "video_" + (root.imageData.md5 ? root.imageData.md5 : root.imageData.id) + "." + root.fileExt
        var cached = Services.CacheIndex.lookup(videoName)
        if (cached.length > 0) return cached
        // Also check by filename (user downloads)
        return Services.CacheIndex.lookup(root.fileName)
    }
    property bool videoDownloadFailed: false
    property string videoFilePath: root.previewDownloadPath + "/video_" + (root.imageData.md5 ? root.imageData.md5 : root.imageData.id) + "." + root.fileExt

    // Video preview for manualDownload providers (Sankaku CDN blocks direct image requests)
    property string videoPreviewPath: root.previewDownloadPath + "/vidpreview_" + (root.imageData.md5 ? root.imageData.md5 : root.imageData.id) + ".jpg"
    property string localVideoPreview: ""
    property bool videoPreviewCacheChecked: false

    // Check if video preview is already cached
    Process {
        id: videoPreviewCacheCheck
        running: root.isVideo && root.manualDownload && !root.videoPreviewCacheChecked && root.videoPreviewPath.length > 0
        command: ["test", "-s", root.videoPreviewPath]
        onExited: function(code, status) {
            root.videoPreviewCacheChecked = true
            if (code === 0) {
                root.localVideoPreview = "file://" + root.videoPreviewPath
            }
        }
    }

    Process {
        id: videoPreviewDownloader
        property bool downloading: false
        running: false

        function buildCommand() {
            var previewUrl = root.imageData.preview_url || ""
            var url = shellEscape(previewUrl)
            var jpgPath = shellEscape(root.videoPreviewPath)
            var avifPath = shellEscape(root.videoPreviewPath.replace(".jpg", ".avif"))

            // Check if preview URL is AVIF (Sankaku videos use AVIF previews)
            // If so, download AVIF and convert to JPEG using avifdec
            if (previewUrl.indexOf(".avif") >= 0) {
                return ["bash", "-c",
                    "mkdir -p \"$(dirname '" + jpgPath + "')\" && " +
                    "curl -fsSL --connect-timeout 5 --max-time 30 " +
                    "-A 'Mozilla/5.0 BooruSidebar/1.0' '" + url + "' -o '" + avifPath + "' && " +
                    "[ -s '" + avifPath + "' ] && " +
                    "avifdec '" + avifPath + "' '" + jpgPath + "' >/dev/null 2>&1 && " +
                    "rm -f '" + avifPath + "' && " +
                    "[ -s '" + jpgPath + "' ]"
                ]
            } else {
                // Non-AVIF preview, download directly
                return ["bash", "-c",
                    "mkdir -p \"$(dirname '" + jpgPath + "')\" && " +
                    "curl -fsSL --connect-timeout 5 --max-time 30 " +
                    "-A 'Mozilla/5.0 BooruSidebar/1.0' '" + url + "' -o '" + jpgPath + "' && " +
                    "[ -s '" + jpgPath + "' ]"
                ]
            }
        }

        command: buildCommand()

        onRunningChanged: {
            if (running) downloading = true
        }

        onExited: function(code, status) {
            downloading = false
            if (code === 0) {
                root.localVideoPreview = "file://" + root.videoPreviewPath
            } else {
                console.log("[BooruImage] Video preview download/conversion failed: " + root.imageData.preview_url)
            }
        }
    }

    Timer {
        id: videoPreviewTrigger
        interval: 50
        repeat: false
        // Download preview for manualDownload providers showing videos (after cache check)
        running: root.isVideo && root.manualDownload && root.videoPreviewCacheChecked
                 && root.localVideoPreview === ""
                 && (root.imageData.preview_url || root.imageData.sample_url)
                 && !videoPreviewDownloader.downloading
        onTriggered: {
            if (!videoPreviewDownloader.downloading) {
                videoPreviewDownloader.command = videoPreviewDownloader.buildCommand()
                videoPreviewDownloader.running = true
            }
        }
    }

    // Universal video cache check - REPLACED by CacheIndex singleton
    // Note: Video validation (checking file is not HTML error) now relies on MediaPlayer error handling
    Process {
        id: videoCacheCheck
        running: false  // Disabled - CacheIndex handles cache lookups
        command: ["true"]
    }

    // Video download progress tracking
    property int videoDownloadProgress: 0  // 0-100 percentage
    property int videoFileSize: root.imageData.file_size || 0  // Expected size in bytes

    function formatFileSize(bytes) {
        if (bytes <= 0) return ""
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1024 * 1024) return Math.round(bytes / 1024) + " KB"
        return (bytes / (1024 * 1024)).toFixed(1) + " MB"
    }

    // Download video to cache (after cache check)
    Process {
        id: universalVideoDownloader
        property bool downloading: false
        property int retryCount: 0
        property int maxRetries: 2
        running: false

        // Build command dynamically when starting to ensure fresh URL
        function buildCommand() {
            var url = shellEscape(root.imageData.file_url || "")
            var path = shellEscape(root.videoFilePath)
            // Validate downloaded file is actually a video, not an HTML error page
            // Sankaku CDN returns 403 HTML with HTTP 200 status on expired tokens
            return ["bash", "-c",
                "mkdir -p \"$(dirname '" + path + "')\" && " +
                "curl -fSL --connect-timeout 10 --max-time 300 " +
                "-A 'Mozilla/5.0 BooruSidebar/1.0' '" + url + "' -o '" + path + "' && " +
                "[ -s '" + path + "' ] && " +  // File exists and non-empty
                "file -b '" + path + "' | grep -qiE 'video|MP4|WebM|ISO Media' || " +  // Must be video
                "{ rm -f '" + path + "'; exit 1; }"  // Delete HTML error page, fail
            ]
        }

        command: buildCommand()

        onRunningChanged: {
            if (running) {
                downloading = true
                root.videoDownloadProgress = 0
                videoProgressTimer.start()
            }
        }

        onExited: function(code, status) {
            videoProgressTimer.stop()
            if (code === 0) {
                downloading = false
                retryCount = 0
                root.videoDownloadFailed = false
                root.videoDownloadProgress = 100
                var cachedPath = "file://" + root.videoFilePath
                root.cachedVideoSource = cachedPath
                // Register in CacheIndex for instant future lookups
                var videoName = "video_" + (root.imageData.md5 ? root.imageData.md5 : root.imageData.id) + "." + root.fileExt
                Services.CacheIndex.register(videoName, root.videoFilePath)
                // Update preview if it's showing this video
                if (root.isPreviewActive) {
                    root.updatePreviewSource(cachedPath)
                }
            } else {
                // Retry on failure
                if (retryCount < maxRetries) {
                    retryCount++
                    console.log("[BooruImage] Video download failed, retry " + retryCount + "/" + maxRetries + ": " + root.imageData.file_url)
                    videoRetryTimer.start()
                } else {
                    downloading = false
                    retryCount = 0
                    root.videoDownloadFailed = true
                    console.log("[BooruImage] Video download failed after " + maxRetries + " retries: " + root.imageData.file_url)
                }
            }
        }
    }

    // Check download progress periodically
    Timer {
        id: videoProgressTimer
        interval: 500
        repeat: true
        running: false
        onTriggered: videoProgressChecker.running = true
    }

    Process {
        id: videoProgressChecker
        running: false
        command: ["stat", "-c", "%s", root.videoFilePath]
        stdout: StdioCollector {
            onStreamFinished: {
                var currentSize = parseInt(text.trim()) || 0
                if (root.videoFileSize > 0 && currentSize > 0) {
                    root.videoDownloadProgress = Math.min(99, Math.round((currentSize / root.videoFileSize) * 100))
                }
            }
        }
    }

    Timer {
        id: videoRetryTimer
        interval: 1000  // Wait 1 second before retry
        repeat: false
        onTriggered: {
            universalVideoDownloader.command = universalVideoDownloader.buildCommand()
            universalVideoDownloader.running = true
        }
    }

    Timer {
        id: videoDownloadTrigger
        interval: 100
        repeat: false
        running: root.isVideo && root.videoCacheChecked && root.cachedVideoSource === ""
                 && root.imageData.file_url && root.imageData.file_url.length > 0
                 && !universalVideoDownloader.downloading
        onTriggered: {
            if (!universalVideoDownloader.downloading) {
                universalVideoDownloader.command = universalVideoDownloader.buildCommand()
                universalVideoDownloader.running = true
            }
        }
    }

    // Grabber-based downloader for high-quality downloads with metadata-aware filenames
    // Falls back to curl if provider not supported by Grabber
    property string grabberSource: Services.Booru.getGrabberSource(root.provider)
    property bool useGrabber: grabberSource && grabberSource.length > 0

    GrabberDownloader {
        id: grabberDownloader
        source: root.grabberSource
        imageId: root.imageData.id ? String(root.imageData.id) : ""
        filenameTemplate: Services.Booru.filenameTemplate

        onDone: (success, message) => {
            if (success) {
                Quickshell.execDetached(["notify-send", "Download complete", message, "-a", "Booru"])
            } else {
                // Fallback to curl on Grabber failure (User-Agent for Sankaku etc.)
                console.log("[BooruImage] Grabber failed, falling back to curl: " + message)
                var targetPath = root.imageData.is_nsfw ? root.nsfwPath : root.downloadPath
                var escapedPath = shellEscape(targetPath)
                var escapedUrl = shellEscape(root.imageData.file_url)
                var escapedFile = shellEscape(root.fileName)
                Quickshell.execDetached(["bash", "-c",
                    "mkdir -p '" + escapedPath + "' && curl -sL -A 'Mozilla/5.0 BooruSidebar/1.0' '" + escapedUrl + "' -o '" + escapedPath + "/" + escapedFile + "' && notify-send 'Download complete' '" + escapedPath + "/" + escapedFile + "' -a 'Booru'"
                ])
            }
        }
    }

    GrabberDownloader {
        id: wallpaperDownloader
        source: root.grabberSource
        imageId: root.imageData.id ? String(root.imageData.id) : ""
        filenameTemplate: Services.Booru.filenameTemplate

        onDone: (success, message) => {
            if (success) {
                Quickshell.execDetached(["notify-send", "Wallpaper saved", message, "-a", "Booru"])
            } else {
                // Fallback to curl on Grabber failure (User-Agent for Sankaku etc.)
                console.log("[BooruImage] Grabber wallpaper failed, falling back to curl: " + message)
                var wallpaperPath = root.downloadPath.replace(/\/booru$/, '/wallpapers')
                var escapedWpPath = shellEscape(wallpaperPath)
                var escapedUrl = shellEscape(root.imageData.file_url)
                var escapedFile = shellEscape(root.fileName)
                Quickshell.execDetached(["bash", "-c",
                    "mkdir -p '" + escapedWpPath + "' && curl -sL -A 'Mozilla/5.0 BooruSidebar/1.0' '" + escapedUrl + "' -o '" + escapedWpPath + "/" + escapedFile + "' && notify-send 'Wallpaper saved' '" + escapedWpPath + "/" + escapedFile + "' -a 'Booru'"
                ])
            }
        }
    }

    // Check if file exists locally (downloaded or as wallpaper)
    // Use Timer to ensure all properties are bound before checking
    Timer {
        id: fileCheckTimer
        interval: 100
        running: root.fileName.length > 0 && root.downloadPath.length > 0
        onTriggered: {
            // Build command dynamically when timer fires to ensure paths are set
            fileChecker.command = ["bash", "-c",
                "SAVED=0; WP=0; " +
                "[ -f '" + root.savedFilePath + "' ] && SAVED=1; " +
                "[ -f '" + root.savedNsfwFilePath + "' ] && SAVED=1; " +
                "[ -f '" + root.wallpaperFilePath + "' ] && WP=1; " +
                "echo $SAVED $WP"
            ]
            fileChecker.running = true
        }
    }

    Process {
        id: fileChecker
        property bool handled: false

        onRunningChanged: {
            if (running) handled = false
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (fileChecker.handled) return
                fileChecker.handled = true
                var parts = text.trim().split(" ")
                if (parts.length >= 2) {
                    root.isSavedLocally = (parts[0] === "1")
                    root.isSavedAsWallpaper = (parts[1] === "1")
                }
            }
        }

        onExited: (code, status) => {
            // Fallback if stdout didn't fire
            if (!fileChecker.handled) {
                fileChecker.handled = true
            }
        }
    }

    StyledToolTip {
        // Show first 5 tags, truncated to max 200 chars
        property var tagList: (root.imageData.tags ? root.imageData.tags : "").split(" ").filter(t => t.length > 0)
        property string rawContent: tagList.slice(0, 5).join(", ") + (tagList.length > 5 ? " ..." : "")
        content: rawContent.length > 200 ? rawContent.substring(0, 200) + "..." : rawContent
    }

    padding: 0
    implicitWidth: root.rowHeight * (root.effectiveAspectRatio)
    implicitHeight: root.rowHeight
    z: showActions ? 100 : 0

    background: Rectangle {
        implicitWidth: root.rowHeight * (root.effectiveAspectRatio)
        implicitHeight: root.rowHeight
        radius: imageRadius
        color: Appearance.colors.colLayer2
    }

    contentItem: Item {
        anchors.fill: parent

        // Static image display with progressive loading (non-GIF, non-video)
        // Structure: Container with OpacityMask > [HighRes + BlurredPreview overlay]
        Item {
            id: staticImageContainer
            anchors.fill: parent
            // Hide when video, GIF, or converted ugoira is playing
            visible: !root.isVideo && !root.isGif && !(root.isArchive && root.localUgoiraSource.length > 0)

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: root.rowHeight * (root.effectiveAspectRatio)
                    height: root.rowHeight
                    radius: imageRadius
                }
            }

            // High-res image (loads in background)
            Image {
                id: highResImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: {
                    if (root.isVideo || root.isGif) return ""
                    // Universal cache takes priority (any provider)
                    if (root.cachedImageSource.length > 0) return root.cachedImageSource
                    // Manual download providers use their own path
                    if (root.manualDownload) return root.localHighResSource
                    // Wait for cache check before loading from network
                    if (!root.universalCacheChecked) return ""
                    return modelData.file_url ? modelData.file_url : ""
                }
                sourceSize.width: parent.width * 2
                sourceSize.height: parent.height * 2
                asynchronous: true
                cache: true

                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            // Blurred preview overlay (fades out when high-res ready)
            Item {
                id: blurOverlay
                anchors.fill: parent
                visible: opacity > 0
                opacity: highResImage.status === Image.Ready ? 0 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutCubic
                    }
                }

                Image {
                    id: previewImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    source: {
                        if (!blurOverlay.visible) return ""
                        if (root.isVideo || root.isGif) return ""
                        // For manual download providers, use local preview file
                        if (root.manualDownload) {
                            return imageDownloader.downloadedPath ? "file://" + imageDownloader.downloadedPath : ""
                        }
                        // Fallback chain: preview -> sample -> file_url
                        if (modelData.preview_url) return modelData.preview_url
                        if (modelData.sample_url) return modelData.sample_url
                        return modelData.file_url ? modelData.file_url : ""
                    }
                    sourceSize.width: root.rowHeight * (root.effectiveAspectRatio)
                    sourceSize.height: root.rowHeight
                    asynchronous: true
                    cache: true
                    visible: false  // Only used as blur source
                }

                FastBlur {
                    anchors.fill: parent
                    source: previewImage
                    radius: 32
                    transparentBorder: false
                }
            }

            // Archive/Ugoira badge - shows status, hidden when video is playing
            Rectangle {
                visible: root.isArchive && root.localUgoiraSource === ""
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.margins: 6
                width: archiveBadgeRow.width + 10
                height: 18
                radius: 4
                color: root.ugoiraDownloading ? Qt.rgba(0.2, 0.5, 0.8, 0.9) : Qt.rgba(0.6, 0.3, 0, 0.8)

                Row {
                    id: archiveBadgeRow
                    anchors.centerIn: parent
                    spacing: 3

                    MaterialSymbol {
                        visible: !root.ugoiraDownloading
                        anchors.verticalCenter: parent.verticalCenter
                        iconSize: 12
                        color: "#ffffff"
                        text: "play_circle"
                    }

                    StyledText {
                        id: archiveLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.ugoiraDownloading ? "..." : "UGOIRA"  // Show dots while downloading
                        font.pixelSize: 10
                        font.bold: true
                        color: "#ffffff"
                    }
                }
            }
        }

        // GIF preview (shown while loading)
        Image {
            id: gifPreview
            anchors.fill: parent
            // Hide preview for manual download providers (they block direct image requests)
            visible: root.isGif && !root.manualDownload && gifObject.status !== AnimatedImage.Ready
            fillMode: Image.PreserveAspectCrop
            source: (root.isGif && !root.manualDownload) ? (modelData.preview_url ? modelData.preview_url : "") : ""
            asynchronous: true

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: gifPreview.width
                    height: gifPreview.height
                    radius: imageRadius
                }
            }

            // GIF badge
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.margins: 6
                width: gifLabel.width + 8
                height: 18
                radius: 4
                color: Qt.rgba(0, 0, 0, 0.6)

                StyledText {
                    id: gifLabel
                    anchors.centerIn: parent
                    text: "GIF"
                    font.pixelSize: 10
                    font.bold: true
                    color: "#ffffff"
                }
            }
        }

        // GIF display - cache: true required for looping from network sources
        AnimatedImage {
            id: gifObject
            anchors.fill: parent
            visible: root.isGif
            fillMode: Image.PreserveAspectCrop
            // Universal cache first, then manual download path, then network
            source: {
                if (!root.isGif) return ""
                // Universal cache first
                if (root.cachedGifSource.length > 0) return root.cachedGifSource
                // Also check image cache (zerochan GIFs found via extension variant lookup with hires_ prefix)
                if (root.cachedImageSource.length > 0 && root.cachedImageSource.toLowerCase().endsWith(".gif")) {
                    return root.cachedImageSource
                }
                // Manual download providers
                if (root.manualDownload) return root.localGifSource
                // Wait for cache check
                if (!root.gifCacheChecked) return ""
                return modelData.file_url ? modelData.file_url : ""
            }
            asynchronous: true
            cache: true  // Required for looping from network sources per Qt docs
            playing: true

            opacity: status === AnimatedImage.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: gifObject.width
                    height: gifObject.height
                    radius: imageRadius
                }
            }
        }

        // Video display (MediaPlayer + VideoOutput) - handles both regular videos and ugoira WebM
        Item {
            id: videoContainer
            anchors.fill: parent
            // Show for regular videos OR ugoira with downloaded WebM
            visible: root.isVideo || (root.isArchive && root.localUgoiraSource.length > 0)

            // Compute video source: ugoira → cached → network (if allowed)
            property string videoSource: {
                if (root.isArchive && root.localUgoiraSource.length > 0) {
                    return root.localUgoiraSource
                } else if (root.isVideo) {
                    // Universal cache first
                    if (root.cachedVideoSource.length > 0) return root.cachedVideoSource
                    // Wait for cache check
                    if (!root.videoCacheChecked) return ""
                    // Manual download providers (Sankaku, e621, etc.) can't stream directly
                    // Qt MediaPlayer doesn't send User-Agent headers, so CDN blocks the request
                    // Wait for curl download to complete instead
                    if (root.manualDownload) return ""
                    return root.imageData.file_url ? root.imageData.file_url : ""
                }
                return ""
            }

            // Preview thumbnail while video is loading/downloading
            Image {
                id: videoPreviewImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                // Show preview while video not playing (downloading or buffering)
                visible: mediaPlayer.playbackState !== MediaPlayer.PlayingState
                // For manualDownload providers, use downloaded preview (CDN blocks direct requests)
                // For others, try preview_url directly
                source: {
                    if (root.manualDownload) {
                        return root.localVideoPreview
                    }
                    return modelData.preview_url ? modelData.preview_url : ""
                }
                asynchronous: true

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: videoPreviewImage.width
                        height: videoPreviewImage.height
                        radius: imageRadius
                    }
                }
            }

            // Solid background shown if preview doesn't load (CDN blocked, etc.)
            Rectangle {
                anchors.fill: parent
                radius: imageRadius
                color: Appearance.colors.colLayer2
                visible: videoPreviewImage.status !== Image.Ready
                         && mediaPlayer.playbackState !== MediaPlayer.PlayingState
                z: -1
            }

            MediaPlayer {
                id: mediaPlayer
                source: videoContainer.videoSource
                loops: MediaPlayer.Infinite
                audioOutput: AudioOutput {
                    id: videoAudio
                    // Unmute on hover - allows hearing videos with sound
                    muted: !root.hovered
                }
                videoOutput: videoOutput

                onSourceChanged: {
                    // source is a QUrl, not string - must convert to check length
                    if (source.toString().length > 0) play()
                }
            }

            VideoOutput {
                id: videoOutput
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: videoOutput.width
                        height: videoOutput.height
                        radius: imageRadius
                    }
                }
            }

            // Play icon overlay (shown when paused, but not while downloading)
            Rectangle {
                anchors.centerIn: parent
                width: 40
                height: 40
                radius: 20
                color: Qt.rgba(0, 0, 0, 0.6)
                // Hide during download (manualDownload providers) - show download indicator instead
                visible: mediaPlayer.playbackState !== MediaPlayer.PlayingState
                         && !universalVideoDownloader.downloading
                         && videoContainer.videoSource.length > 0

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 24
                    color: "#ffffff"
                    text: "play_arrow"
                }
            }

            // Sound indicator (bottom-right corner, shown on hover when video is playing)
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 6
                width: 28
                height: 28
                radius: 14
                color: Qt.rgba(0, 0, 0, 0.6)
                visible: root.hovered && mediaPlayer.playbackState === MediaPlayer.PlayingState

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 18
                    color: "#ffffff"
                    text: "volume_up"
                }
            }

            // Video download indicator with progress (shown while downloading, not when cached)
            Rectangle {
                id: videoDownloadIndicator
                anchors.centerIn: parent
                width: root.videoFileSize > 0 ? 70 : 40
                height: 40
                radius: 20
                color: Qt.rgba(0, 0, 0, 0.7)
                visible: root.isVideo && universalVideoDownloader.downloading && root.cachedVideoSource === ""

                Row {
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        iconSize: 20
                        color: "#ffffff"
                        text: "downloading"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        visible: root.videoFileSize > 0
                        text: root.videoDownloadProgress + "%"
                        color: "#ffffff"
                        font.pixelSize: 12
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Progress bar at bottom
                Rectangle {
                    visible: root.videoFileSize > 0
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.margins: 3
                    width: (parent.width - 6) * (root.videoDownloadProgress / 100)
                    height: 3
                    radius: 1.5
                    color: "#4CAF50"
                }
            }

            // Video download error indicator
            Rectangle {
                anchors.centerIn: parent
                width: 40
                height: 40
                radius: 20
                color: Qt.rgba(200, 50, 50, 0.8)
                visible: root.isVideo && root.videoDownloadFailed

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 24
                    color: "#ffffff"
                    text: "error"
                }

                // Tap to retry
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.videoDownloadFailed = false
                        universalVideoDownloader.retryCount = 0
                        universalVideoDownloader.command = universalVideoDownloader.buildCommand()
                        universalVideoDownloader.running = true
                    }
                }
            }
        }

        // Ugoira download indicator (shown while downloading pre-converted WebM)
        Rectangle {
            anchors.fill: parent
            radius: imageRadius
            color: Appearance.colors.colLayer2
            visible: root.isArchive && root.localUgoiraSource === "" && root.ugoiraDownloading

            Column {
                anchors.centerIn: parent
                spacing: 8

                // Spinner animation
                MaterialSymbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    iconSize: 24
                    color: Appearance.m3colors.m3onSurface
                    text: "sync"

                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                        running: root.ugoiraDownloading
                    }
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Downloading..."
                    font.pixelSize: Appearance.font.pixelSize.textSmall
                    color: Appearance.m3colors.m3secondaryText
                }
            }
        }

        // Loading indicator (static images - shows while preview loads)
        Rectangle {
            anchors.fill: parent
            radius: imageRadius
            color: Appearance.colors.colLayer2
            // Hide for videos, GIFs, and ugoira (when video source is ready)
            visible: !root.isVideo && !root.isGif && !(root.isArchive && root.localUgoiraSource.length > 0) && previewImage.status !== Image.Ready && highResImage.status !== Image.Ready

            StyledText {
                anchors.centerIn: parent
                text: "..."
                color: Appearance.m3colors.m3secondaryText
            }
        }

        // Loading indicator (GIFs - when both preview and GIF are loading)
        Rectangle {
            anchors.fill: parent
            radius: imageRadius
            color: Appearance.colors.colLayer2
            visible: {
                if (!root.isGif) return false
                if (root.manualDownload) {
                    // Show while downloading (localGifSource empty) or loading
                    return root.localGifSource === "" || gifObject.status !== AnimatedImage.Ready
                }
                return gifPreview.status !== Image.Ready && gifObject.status !== AnimatedImage.Ready
            }

            StyledText {
                anchors.centerIn: parent
                text: "GIF..."
                color: Appearance.m3colors.m3secondaryText
            }
        }

        // Menu button
        RippleButton {
            id: menuButton
            anchors.top: parent.top
            anchors.right: parent.right
            property real buttonSize: 28
            anchors.margins: 6
            implicitHeight: buttonSize
            implicitWidth: buttonSize
            buttonRadius: Appearance.rounding.full
            colBackground: Qt.rgba(0, 0, 0, 0.4)
            colBackgroundHover: Qt.rgba(0, 0, 0, 0.6)

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                iconSize: 18
                color: "#ffffff"
                text: "more_vert"
            }

            onClicked: root.showActions = !root.showActions
        }

        // Download status badges (bottom-right corner)
        Row {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 6
            spacing: 4
            z: 5

            // Downloaded badge
            Rectangle {
                visible: root.isSavedLocally
                width: 22
                height: 22
                radius: 4
                color: Qt.rgba(0, 0, 0, 0.6)

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 14
                    color: "#ffffff"
                    text: "download_done"
                }
            }

            // Wallpaper badge
            Rectangle {
                visible: root.isSavedAsWallpaper
                width: 22
                height: 22
                radius: 4
                color: Qt.rgba(0, 0, 0, 0.6)

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 14
                    color: "#ffffff"
                    text: "wallpaper"
                }
            }
        }

        // Context menu popup - renders in overlay layer above all content
        Popup {
            id: contextMenuPopup
            visible: root.showActions
            y: menuButton.y + menuButton.height + 4
            x: Math.max(4, Math.min(parent.width - 164, menuButton.x + menuButton.width - 160))
            width: 160
            height: menuColumn.implicitHeight + 16
            padding: 0
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            onClosed: root.showActions = false

            background: Rectangle {
                radius: Appearance.rounding.small
                color: Appearance.m3colors.m3layerBackground2
            }

            contentItem: Column {
                id: menuColumn
                width: 152
                spacing: 2
                padding: 4

                RippleButton {
                    width: parent.width - 8
                    implicitHeight: 36
                    buttonRadius: 4

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: "Open file link"
                        font.pixelSize: Appearance.font.pixelSize.textSmall
                    }

                    onClicked: {
                        root.showActions = false
                        Qt.openUrlExternally(root.imageData.file_url)
                    }
                }

                RippleButton {
                    width: parent.width - 8
                    implicitHeight: 36
                    buttonRadius: 4

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: root.isVideo ? "Play in mpv" : "Open in viewer"
                        font.pixelSize: Appearance.font.pixelSize.textSmall
                    }

                    onClicked: {
                        root.showActions = false
                        if (root.isVideo) {
                            // mpv can stream URLs directly (use --user-agent for Sankaku)
                            Quickshell.execDetached(["mpv", "--loop", "--user-agent=Mozilla/5.0 BooruSidebar/1.0", root.imageData.file_url])
                        } else {
                            // Download to temp and open with system default
                            var tmpFile = "/tmp/booru_" + root.fileName
                            var escapedUrl = shellEscape(root.imageData.file_url)
                            var escapedTmp = shellEscape(tmpFile)
                            Quickshell.execDetached(["bash", "-c",
                                "curl -sL -A 'Mozilla/5.0 BooruSidebar/1.0' '" + escapedUrl + "' -o '" + escapedTmp + "' && xdg-open '" + escapedTmp + "'"
                            ])
                        }
                    }
                }

                RippleButton {
                    visible: root.imageData.source && root.imageData.source.length > 0
                    width: parent.width - 8
                    implicitHeight: 36
                    buttonRadius: 4

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: "Go to source"
                        font.pixelSize: Appearance.font.pixelSize.textSmall
                    }

                    onClicked: {
                        root.showActions = false
                        Qt.openUrlExternally(root.imageData.source)
                    }
                }

                RippleButton {
                    width: parent.width - 8
                    implicitHeight: 36
                    buttonRadius: 4

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: "Download"
                        font.pixelSize: Appearance.font.pixelSize.textSmall
                    }

                    onClicked: {
                        root.showActions = false
                        root.isSavedLocally = true
                        var targetPath = root.imageData.is_nsfw ? root.nsfwPath : root.downloadPath
                        if (root.useGrabber) {
                            grabberDownloader.outputPath = targetPath
                            grabberDownloader.startDownload()
                        } else {
                            // Fallback to curl for unsupported providers (User-Agent for Sankaku etc.)
                            var escapedPath = shellEscape(targetPath)
                            var escapedUrl = shellEscape(root.imageData.file_url)
                            var escapedFile = shellEscape(root.fileName)
                            Quickshell.execDetached(["bash", "-c",
                                "mkdir -p '" + escapedPath + "' && curl -sL -A 'Mozilla/5.0 BooruSidebar/1.0' '" + escapedUrl + "' -o '" + escapedPath + "/" + escapedFile + "' && notify-send 'Download complete' '" + escapedPath + "/" + escapedFile + "' -a 'Booru'"
                            ])
                        }
                    }
                }

                RippleButton {
                    width: parent.width - 8
                    implicitHeight: 36
                    buttonRadius: 4

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: "Save as wallpaper"
                        font.pixelSize: Appearance.font.pixelSize.textSmall
                    }

                    onClicked: {
                        root.showActions = false
                        root.isSavedAsWallpaper = true
                        var wallpaperPath = root.downloadPath.replace(/\/booru$/, '/wallpapers')
                        if (root.useGrabber) {
                            wallpaperDownloader.outputPath = wallpaperPath
                            wallpaperDownloader.startDownload()
                        } else {
                            // Fallback to curl for unsupported providers (User-Agent for Sankaku etc.)
                            var escapedWpPath = shellEscape(wallpaperPath)
                            var escapedUrl = shellEscape(root.imageData.file_url)
                            var escapedFile = shellEscape(root.fileName)
                            Quickshell.execDetached(["bash", "-c",
                                "mkdir -p '" + escapedWpPath + "' && curl -sL -A 'Mozilla/5.0 BooruSidebar/1.0' '" + escapedUrl + "' -o '" + escapedWpPath + "/" + escapedFile + "' && notify-send 'Wallpaper saved' '" + escapedWpPath + "/" + escapedFile + "' -a 'Booru'"
                            ])
                        }
                    }
                }
            }
        }

    }

    // Track if this image's preview is currently shown
    property bool isPreviewActive: false

    onClicked: {
        if (!showActions) {
            // Toggle preview - close if this image is already being previewed
            if (root.isPreviewActive) {
                root.hidePreview()
            } else {
                console.log("[BooruImage] Clicked - id:", root.imageData ? root.imageData.id : "null")
                var cachedSrc = ""
                if (root.isVideo || root.isArchive) {
                    // For videos/ugoira, prefer the actual playing source if it's local
                    // This handles cases where video was downloaded after CacheIndex initialized
                    var videoSrc = videoContainer.videoSource
                    if (videoSrc && videoSrc.indexOf("file://") === 0) {
                        cachedSrc = videoSrc
                    } else if (root.cachedVideoSource) {
                        cachedSrc = root.cachedVideoSource
                    }
                } else if (root.isGif) {
                    // For GIFs, prefer the actual source if it's local
                    var gifSrc = gifObject.source.toString()
                    if (gifSrc && gifSrc.indexOf("file://") === 0) {
                        cachedSrc = gifSrc
                    } else if (root.cachedGifSource) {
                        cachedSrc = root.cachedGifSource
                    } else if (root.cachedImageSource && root.cachedImageSource.toLowerCase().endsWith(".gif")) {
                        // Zerochan GIFs found via extension variant lookup with hires_ prefix
                        cachedSrc = root.cachedImageSource
                    }
                } else if (root.cachedImageSource) {
                    cachedSrc = root.cachedImageSource
                } else if (root.localHighResSource) {
                    cachedSrc = root.localHighResSource
                }
                root.showPreview(root.imageData, cachedSrc, root.manualDownload, root.provider)
            }
        }
    }
}
