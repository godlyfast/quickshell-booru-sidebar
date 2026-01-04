import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../common"
import "../common/widgets"
import "../common/utils"
import "../common/functions/file_utils.js" as FileUtils
import "../../services"

/**
 * Left sidebar panel window containing the Booru browser.
 */
Scope {
    id: root
    property bool sidebarOpen: false

    // Preview panel state
    property var previewImageData: null
    property bool previewActive: false
    property string previewCachedSource: ""
    property bool previewManualDownload: false
    property string previewProvider: ""

    // Called by BooruImage when clicked to show preview
    function showPreview(imageData, cachedSource, manualDownload, provider) {
        root.previewImageData = imageData
        root.previewCachedSource = cachedSource || ""
        root.previewManualDownload = manualDownload || false
        root.previewProvider = provider || ""
        root.previewActive = true
    }

    // Called to hide preview (close button or clicking outside)
    function hidePreview() {
        root.previewActive = false
    }

    // Download paths
    property string downloadPath: FileUtils.trimFileProtocol(Directories.homeDir) + "/Pictures/booru"
    property string nsfwPath: FileUtils.trimFileProtocol(Directories.homeDir) + "/Pictures/booru/nsfw"
    property string wallpaperPath: FileUtils.trimFileProtocol(Directories.homeDir) + "/Pictures/wallpapers"

    // Shell escape helper
    function shellEscape(str) {
        if (!str) return ""
        return str.replace(/'/g, "'\\''")
    }

    // Download image using Grabber or curl fallback
    function downloadImage(imageData, isWallpaper) {
        if (!imageData || !imageData.file_url) return

        var targetPath = isWallpaper ? root.wallpaperPath : (imageData.is_nsfw ? root.nsfwPath : root.downloadPath)
        var notifyTitle = isWallpaper ? "Wallpaper saved" : "Download complete"
        var grabberSource = Booru.getGrabberSource(root.previewProvider)

        if (grabberSource && grabberSource.length > 0) {
            // Use Grabber for supported providers
            var downloader = isWallpaper ? wallpaperDownloader : previewDownloader
            downloader.source = grabberSource
            downloader.imageId = String(imageData.id)
            downloader.outputPath = targetPath
            downloader.startDownload()
        } else {
            // Fallback to curl
            var fileName = imageData.file_url.substring(imageData.file_url.lastIndexOf('/') + 1)
            var queryIdx = fileName.indexOf('?')
            if (queryIdx > 0) fileName = fileName.substring(0, queryIdx)
            fileName = decodeURIComponent(fileName)

            Quickshell.execDetached(["bash", "-c",
                "mkdir -p '" + shellEscape(targetPath) + "' && " +
                "curl -sL -A 'Mozilla/5.0 BooruSidebar/1.0' '" + shellEscape(imageData.file_url) + "' " +
                "-o '" + shellEscape(targetPath) + "/" + shellEscape(fileName) + "' && " +
                "notify-send '" + notifyTitle + "' '" + shellEscape(targetPath + "/" + fileName) + "' -a 'Booru'"
            ])
        }
    }

    // Curl fallback helper for Grabber failures
    function curlFallback(imageData, targetPath, notifyTitle) {
        var fileName = imageData.file_url.substring(imageData.file_url.lastIndexOf('/') + 1)
        var queryIdx = fileName.indexOf('?')
        if (queryIdx > 0) fileName = fileName.substring(0, queryIdx)
        fileName = decodeURIComponent(fileName)

        Quickshell.execDetached(["bash", "-c",
            "mkdir -p '" + shellEscape(targetPath) + "' && " +
            "curl -sL -A 'Mozilla/5.0 BooruSidebar/1.0' '" + shellEscape(imageData.file_url) + "' " +
            "-o '" + shellEscape(targetPath) + "/" + shellEscape(fileName) + "' && " +
            "notify-send '" + notifyTitle + "' '" + shellEscape(targetPath + "/" + fileName) + "' -a 'Booru'"
        ])
    }

    // Grabber downloader for preview panel downloads
    GrabberDownloader {
        id: previewDownloader
        filenameTemplate: Booru.filenameTemplate

        onDone: function(success, message) {
            if (success) {
                Quickshell.execDetached(["notify-send", "Download complete", message, "-a", "Booru"])
            } else if (root.previewImageData && root.previewImageData.file_url) {
                var targetPath = root.previewImageData.is_nsfw ? root.nsfwPath : root.downloadPath
                root.curlFallback(root.previewImageData, targetPath, "Download complete")
            }
        }
    }

    // Grabber downloader for wallpaper saves
    GrabberDownloader {
        id: wallpaperDownloader
        filenameTemplate: Booru.filenameTemplate

        onDone: function(success, message) {
            if (success) {
                Quickshell.execDetached(["notify-send", "Wallpaper saved", message, "-a", "Booru"])
            } else if (root.previewImageData && root.previewImageData.file_url) {
                root.curlFallback(root.previewImageData, root.wallpaperPath, "Wallpaper saved")
            }
        }
    }

    Loader {
        id: sidebarLoader
        active: true

        sourceComponent: PanelWindow {
            id: sidebarRoot
            visible: root.sidebarOpen

            property real sidebarWidth: 420

            function hide() {
                root.sidebarOpen = false
            }

            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            implicitWidth: sidebarWidth + 20
            WlrLayershell.namespace: "quickshell:sidebarLeft"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors {
                top: true
                left: true
                bottom: true
            }

            mask: Region {
                item: sidebarBackground
            }

            property bool pinned: false

            HyprlandFocusGrab {
                id: grab
                // Include preview panel in focus grab so clicking it doesn't close sidebar
                windows: previewPanel.panelWindow ? [sidebarRoot, previewPanel.panelWindow] : [sidebarRoot]
                active: sidebarRoot.visible && !sidebarRoot.pinned
                onActiveChanged: {
                    if (active) {
                        sidebarBackground.forceActiveFocus()
                    }
                }
                onCleared: {
                    if (!sidebarRoot.pinned) sidebarRoot.hide()
                }
            }

            // Shadow
            Rectangle {
                anchors.fill: sidebarBackground
                anchors.margins: -4
                radius: sidebarBackground.radius + 4
                color: "transparent"
                border.width: 8
                border.color: Qt.rgba(0, 0, 0, 0.3)
                z: -1
            }

            // Main background
            Rectangle {
                id: sidebarBackground
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: 8
                anchors.leftMargin: 8
                width: sidebarRoot.sidebarWidth
                height: parent.height - 16
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.m3colors.m3borderSecondary
                radius: Appearance.rounding.large

                Keys.onPressed: (event) => {
                    // Close preview with Q or Escape when preview is active
                    if (root.previewActive && (event.key === Qt.Key_Q || event.key === Qt.Key_Escape)) {
                        root.hidePreview()
                        event.accepted = true
                        return
                    }
                    // Close sidebar with Escape
                    if (event.key === Qt.Key_Escape) {
                        sidebarRoot.hide()
                        event.accepted = true
                    }
                }

                // Pin button
                RippleButton {
                    id: pinButton
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: sidebarRoot.pinned ? Appearance.colors.colLayer2Active : Qt.rgba(0, 0, 0, 0.2)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    z: 10

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 16
                        color: sidebarRoot.pinned ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3secondaryText
                        text: sidebarRoot.pinned ? "push_pin" : "push_pin"
                    }

                    onClicked: sidebarRoot.pinned = !sidebarRoot.pinned
                }

                // Content
                Anime {
                    anchors.fill: parent
                    previewImageId: root.previewActive && root.previewImageData ? root.previewImageData.id : null
                    onShowPreview: function(imageData, cachedSource, manualDownload, provider) {
                        root.showPreview(imageData, cachedSource, manualDownload, provider)
                    }
                    onHidePreview: root.hidePreview()
                }
            }
        }
    }

    // Full-size preview panel (slides out to the right)
    PreviewPanel {
        id: previewPanel
        imageData: root.previewImageData
        active: root.previewActive && root.sidebarOpen
        cachedSource: root.previewCachedSource
        manualDownload: root.previewManualDownload
        provider: root.previewProvider
        sidebarWidth: 420
        sidebarX: 8

        onRequestClose: root.hidePreview()
        onRequestDownload: function(imageData) { root.downloadImage(imageData, false) }
        onRequestSaveWallpaper: function(imageData) { root.downloadImage(imageData, true) }
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            root.sidebarOpen = !root.sidebarOpen
        }

        function close(): void {
            root.sidebarOpen = false
        }

        function open(): void {
            root.sidebarOpen = true
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles Booru sidebar"

        onPressed: {
            root.sidebarOpen = !root.sidebarOpen
        }
    }
}
