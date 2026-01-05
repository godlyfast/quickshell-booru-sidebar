import QtQuick
import QtQuick.Controls
import QtMultimedia
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

    // Handle sidebar open/close
    onSidebarOpenChanged: {
        if (sidebarOpen) {
            // Ensure keyboard focus when sidebar opens (delayed to ensure component is ready)
            focusTimer.start()
        } else {
            Booru.stopAllVideos()
        }
    }

    // Delayed focus to ensure sidebar is ready
    Timer {
        id: focusTimer
        interval: 50
        onTriggered: {
            // Access focusTarget through Loader's item (PanelWindow inside sourceComponent)
            if (sidebarLoader.item && sidebarLoader.item.focusTarget) {
                sidebarLoader.item.focusTarget.forceActiveFocus()
            }
        }
    }

    // Preview panel state
    property var previewImageData: null
    property bool previewActive: false
    property string previewCachedSource: ""
    property bool previewManualDownload: false
    property string previewProvider: ""
    property var tagInputFieldRef: null  // Reference to search input for clickable tags

    // Called by BooruImage when clicked to show preview
    function showPreview(imageData, cachedSource, manualDownload, provider) {
        // Deep copy to avoid reference issues when model changes
        var imageCopy = imageData ? JSON.parse(JSON.stringify(imageData)) : null
        root.previewImageData = imageCopy
        root.previewCachedSource = cachedSource || ""
        root.previewManualDownload = manualDownload || false
        root.previewProvider = provider || ""
        root.previewActive = true
        // Explicitly update PreviewPanel to avoid binding issues
        previewPanel.setImageData(imageCopy, cachedSource || "")
    }

    // Called to hide preview (close button or clicking outside)
    function hidePreview() {
        // Stop any playing video in preview before closing
        previewPanel.stopVideo()
        // Set flag BEFORE closing preview to prevent focus grab from closing sidebar
        root.closingPreviewIntentionally = true
        root.previewActive = false
    }

    // Vim keybinding state
    property string pendingKey: ""  // For multi-key sequences like 'gg'
    property bool showKeybindingsHelp: false
    property bool showPickerDialog: false
    property bool closingPreviewIntentionally: false  // Flag to prevent focus grab clear from closing sidebar

    // Reactive computed properties for position indicator
    // These re-evaluate when Booru.responses or previewImageData changes
    property int imageCount: {
        var count = 0
        var responses = Booru.responses  // Creates reactive dependency
        for (var i = 0; i < responses.length; i++) {
            var resp = responses[i]
            if (resp && resp.images) {
                count += resp.images.length
            }
        }
        return count
    }

    property int currentImageIndex: {
        if (!previewImageData) return -1
        var responses = Booru.responses  // Creates reactive dependency
        var index = 0
        for (var i = 0; i < responses.length; i++) {
            var resp = responses[i]
            if (resp && resp.images) {
                for (var j = 0; j < resp.images.length; j++) {
                    if (String(resp.images[j].id) === String(previewImageData.id)) return index
                    index++
                }
            }
        }
        return -1
    }

    // Get flat list of all images from all responses
    function getAllImages() {
        var images = []
        var responses = Booru.responses
        for (var i = 0; i < responses.length; i++) {
            var resp = responses[i]
            if (resp && resp.images) {
                for (var j = 0; j < resp.images.length; j++) {
                    images.push({
                        data: resp.images[j],
                        provider: resp.provider
                    })
                }
            }
        }
        return images
    }

    // Get current image index in flat list
    function getCurrentImageIndex() {
        if (!previewImageData) return -1
        var images = getAllImages()
        for (var i = 0; i < images.length; i++) {
            if (String(images[i].data.id) === String(previewImageData.id)) return i
        }
        return -1
    }

    // Compute expected cache path for an image
    property string cacheDir: Directories.cacheDir + "/booru/previews"

    function getCachedPath(imageData, provider) {
        if (!imageData || !imageData.file_url) return ""

        // Extract filename from file_url
        var url = imageData.file_url
        var path = url.substring(url.lastIndexOf('/') + 1)
        var queryIdx = path.indexOf('?')
        if (queryIdx > 0) path = path.substring(0, queryIdx)
        var fileName = decodeURIComponent(path)

        // Get file extension
        var ext = imageData.file_ext ? imageData.file_ext.toLowerCase() : ""
        if (!ext) {
            ext = fileName.split('.').pop().toLowerCase()
        }

        // Determine cache path based on media type
        var cachePath
        if (ext === "gif") {
            // GIFs use gif_ prefix
            cachePath = cacheDir + "/gif_" + fileName
        } else if (ext === "mp4" || ext === "webm") {
            // Videos use video_ prefix with md5/id
            cachePath = cacheDir + "/video_" + (imageData.md5 ? imageData.md5 : imageData.id) + "." + ext
        } else {
            // Images use hires_ prefix
            cachePath = cacheDir + "/hires_" + fileName
            // For danbooru, use md5/id based naming
            if (provider === "danbooru") {
                cachePath = cacheDir + "/hires_" + (imageData.md5 ? imageData.md5 : imageData.id) + "." + ext
            }
        }

        return "file://" + cachePath
    }

    // Navigate to prev/next image in preview (circular)
    function navigatePreview(delta) {
        var images = getAllImages()
        if (images.length === 0) return
        var idx = getCurrentImageIndex()
        if (idx < 0) idx = 0
        // Circular wrap-around
        var newIdx = (idx + delta + images.length) % images.length
        var img = images[newIdx]
        var cachedPath = getCachedPath(img.data, img.provider)
        showPreview(img.data, cachedPath, false, img.provider)
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

    // Clipboard process for yank (y) command
    Process {
        id: clipboardProcess
        onExited: function(code, status) {
            if (code === 0) {
                Quickshell.execDetached(["notify-send", "URL copied", "Image URL copied to clipboard", "-a", "Booru"])
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
            property alias focusTarget: sidebarBackground  // Expose for focus management

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
                    // Check if we're intentionally closing the preview (not actually losing focus)
                    if (root.closingPreviewIntentionally) {
                        root.closingPreviewIntentionally = false
                        // Re-grab focus for sidebar since preview is now closed
                        sidebarBackground.forceActiveFocus()
                        return
                    }
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
                focus: true  // Enable keyboard focus for vim keybindings
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.m3colors.m3borderSecondary
                radius: Appearance.rounding.large

                Keys.onPressed: (event) => {
                    // Skip if input field is focused (let it handle keys normally)
                    if (animeContent.inputField && animeContent.inputField.activeFocus) {
                        // Escape blurs input
                        if (event.key === Qt.Key_Escape) {
                            animeContent.inputField.focus = false
                            sidebarBackground.forceActiveFocus()
                            event.accepted = true
                        }
                        return
                    }

                    // Handle multi-key sequences (gg)
                    if (root.pendingKey === "g") {
                        root.pendingKey = ""
                        if (event.key === Qt.Key_G) {
                            animeContent.scrollToTop()
                            event.accepted = true
                            return
                        }
                    }

                    // === HELP ===
                    if (event.key === Qt.Key_Question || (event.key === Qt.Key_Slash && event.modifiers & Qt.ShiftModifier)) {
                        root.showKeybindingsHelp = !root.showKeybindingsHelp
                        event.accepted = true
                        return
                    }

                    // === CLOSE/QUIT ===
                    if (event.key === Qt.Key_Q || event.key === Qt.Key_Escape) {
                        if (root.showKeybindingsHelp) {
                            root.showKeybindingsHelp = false
                        } else if (root.previewActive) {
                            root.hidePreview()
                        } else {
                            sidebarRoot.hide()
                        }
                        event.accepted = true
                        return
                    }

                    // === TAB: Toggle preview for hovered image ===
                    if (event.key === Qt.Key_Tab && Booru.hoveredBooruImage) {
                        Booru.hoveredBooruImage.togglePreview()
                        event.accepted = true
                        return
                    }

                    // === W: Save hovered image as wallpaper (when not in preview mode) ===
                    if (event.key === Qt.Key_W && !root.previewActive && Booru.hoveredBooruImage) {
                        Booru.hoveredBooruImage.saveAsWallpaper()
                        event.accepted = true
                        return
                    }

                    // === HOVERED VIDEO CONTROLS (takes priority over preview when hovering grid video) ===
                    // Only handle if player has a valid source (pool slot is active)
                    var hoverPlayer = Booru.hoveredVideoPlayer
                    var hasValidSource = hoverPlayer && hoverPlayer.source && hoverPlayer.source.toString().length > 0
                    if (hasValidSource) {
                        // M: toggle mute
                        if (event.key === Qt.Key_M) {
                            if (Booru.hoveredAudioOutput) {
                                Booru.hoveredAudioOutput.muted = !Booru.hoveredAudioOutput.muted
                            }
                            event.accepted = true
                            return
                        }
                        // Right arrow: seek forward 5s
                        if (event.key === Qt.Key_Right) {
                            var newPos = Math.min(hoverPlayer.duration, hoverPlayer.position + 5000)
                            hoverPlayer.position = newPos
                            event.accepted = true
                            return
                        }
                        // Left arrow: seek backward 5s
                        if (event.key === Qt.Key_Left) {
                            var newPos = Math.max(0, hoverPlayer.position - 5000)
                            hoverPlayer.position = newPos
                            event.accepted = true
                            return
                        }
                        // Space: play/pause
                        if (event.key === Qt.Key_Space) {
                            if (hoverPlayer.playbackState === MediaPlayer.PlayingState) {
                                hoverPlayer.pause()
                            } else {
                                hoverPlayer.play()
                            }
                            event.accepted = true
                            return
                        }
                    }

                    // === BLOCK SPACE ON HOVERED NON-VIDEO IMAGES ===
                    // Prevent Space from triggering Button click (which opens preview)
                    if (event.key === Qt.Key_Space && Booru.hoveredBooruImage && !root.previewActive) {
                        event.accepted = true
                        return
                    }

                    // === PREVIEW NAVIGATION & VIDEO CONTROLS ===
                    if (root.previewActive) {
                        var isVideo = previewPanel.isVideo

                        // Video controls (only when viewing video)
                        if (isVideo) {
                            // Space: play/pause
                            if (event.key === Qt.Key_Space) {
                                previewPanel.togglePlayPause()
                                event.accepted = true
                                return
                            }
                            // m: mute toggle
                            if (event.key === Qt.Key_M) {
                                previewPanel.toggleMute()
                                event.accepted = true
                                return
                            }
                            // Up/Down: volume control
                            if (event.key === Qt.Key_Up) {
                                previewPanel.changeVolume(0.1)
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_Down) {
                                previewPanel.changeVolume(-0.1)
                                event.accepted = true
                                return
                            }
                            // comma (<): decrease speed
                            if (event.key === Qt.Key_Comma || event.key === Qt.Key_Less) {
                                previewPanel.changeSpeed(-1)
                                event.accepted = true
                                return
                            }
                            // period (>): increase speed
                            if (event.key === Qt.Key_Period || event.key === Qt.Key_Greater) {
                                previewPanel.changeSpeed(1)
                                event.accepted = true
                                return
                            }
                            // Left/Right: seek (for videos only, images use these for prev/next)
                            if (event.key === Qt.Key_Left) {
                                previewPanel.seekRelative(-5000)  // 5s back
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_Right) {
                                previewPanel.seekRelative(5000)   // 5s forward
                                event.accepted = true
                                return
                            }
                        }

                        // Image panning (non-video only)
                        if (!isVideo) {
                            var panStep = 50
                            if (event.key === Qt.Key_Up) {
                                previewPanel.panY += panStep
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_Down) {
                                previewPanel.panY -= panStep
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_Left) {
                                previewPanel.panX += panStep
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_Right) {
                                previewPanel.panX -= panStep
                                event.accepted = true
                                return
                            }
                        }

                        // h/l: prev/next image in preview
                        if (event.key === Qt.Key_H) {
                            root.navigatePreview(-1)
                            event.accepted = true
                            return
                        }
                        if (event.key === Qt.Key_L) {
                            root.navigatePreview(1)
                            event.accepted = true
                            return
                        }
                        // Preview zoom controls
                        if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
                            previewPanel.zoomLevel = Math.min(previewPanel.maxZoom, previewPanel.zoomLevel * 1.15)
                            event.accepted = true
                            return
                        }
                        if (event.key === Qt.Key_Minus) {
                            previewPanel.zoomLevel = Math.max(previewPanel.minZoom, previewPanel.zoomLevel * 0.87)
                            event.accepted = true
                            return
                        }
                        if (event.key === Qt.Key_0 || event.key === Qt.Key_R) {
                            previewPanel.zoomLevel = 1.0
                            previewPanel.panX = 0
                            previewPanel.panY = 0
                            event.accepted = true
                            return
                        }
                        // Preview actions
                        if (event.key === Qt.Key_D) {
                            root.downloadImage(root.previewImageData, false)
                            event.accepted = true
                            return
                        }
                        if (event.key === Qt.Key_W) {
                            root.downloadImage(root.previewImageData, true)
                            event.accepted = true
                            return
                        }
                        if (event.key === Qt.Key_G) {
                            var postUrl = Booru.getPostUrl(root.previewProvider, root.previewImageData ? root.previewImageData.id : "")
                            if (postUrl) Qt.openUrlExternally(postUrl)
                            event.accepted = true
                            return
                        }
                        if (event.key === Qt.Key_S) {
                            if (root.previewImageData && root.previewImageData.source) {
                                Qt.openUrlExternally(root.previewImageData.source)
                            }
                            event.accepted = true
                            return
                        }
                        if (event.key === Qt.Key_Y) {
                            if (root.previewImageData && root.previewImageData.file_url) {
                                // Copy URL to clipboard using Process
                                clipboardProcess.command = ["wl-copy", root.previewImageData.file_url]
                                clipboardProcess.running = true
                            }
                            event.accepted = true
                            return
                        }
                        // I: Toggle info panel
                        if (event.key === Qt.Key_I) {
                            previewPanel.showInfoPanel = !previewPanel.showInfoPanel
                            event.accepted = true
                            return
                        }
                    }

                    // === h/l: Navigate images (works with preview open or closed) ===
                    if (!root.previewActive) {
                        if (event.key === Qt.Key_H) {
                            root.navigatePreview(-1)
                            event.accepted = true
                            return
                        }
                        if (event.key === Qt.Key_L) {
                            root.navigatePreview(1)
                            event.accepted = true
                            return
                        }
                    }

                    // === VIEWPORT SCROLLING (j/k) ===
                    if (event.key === Qt.Key_J) {
                        animeContent.scrollDown(100)
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_K) {
                        animeContent.scrollUp(100)
                        event.accepted = true
                        return
                    }

                    // === VIEWPORT SCROLLING (Ctrl+u/d, gg, G) ===
                    if (event.key === Qt.Key_G && !(event.modifiers & Qt.ShiftModifier)) {
                        root.pendingKey = "g"
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
                        animeContent.scrollToBottom()
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
                        animeContent.scrollPageDown()
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                        animeContent.scrollPageUp()
                        event.accepted = true
                        return
                    }

                    // === PAGINATION ===
                    if (event.key === Qt.Key_N && !(event.modifiers & Qt.ShiftModifier)) {
                        animeContent.loadNextPage()
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_N && (event.modifiers & Qt.ShiftModifier)) {
                        animeContent.loadPrevPage()
                        event.accepted = true
                        return
                    }

                    // === TOGGLES ===
                    // p: Provider picker (Shift+P: pin sidebar)
                    if (event.key == Qt.Key_P) {
                        if (event.modifiers & Qt.ShiftModifier) {
                            sidebarRoot.pinned = !sidebarRoot.pinned
                        } else {
                            root.showPickerDialog = true
                        }
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_X) {
                        Booru.allowNsfw = !Booru.allowNsfw
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_I) {
                        animeContent.focusInput()
                        event.accepted = true
                        return
                    }

                    // === RELOAD ===
                    // r: reload current page, R (Shift+r): clean cache and reload
                    if (event.key === Qt.Key_R && !root.previewActive) {
                        if (event.modifiers & Qt.ShiftModifier) {
                            animeContent.cleanCacheAndReload()
                        } else {
                            animeContent.reloadCurrentPage()
                        }
                        event.accepted = true
                        return
                    }

                    // === QUICK PROVIDER SWITCH (1-9 via favorites) ===
                    var numKey = -1
                    if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                        numKey = event.key - Qt.Key_1
                    }
                    if (numKey >= 0) {
                        var favorites = (ConfigOptions.booru && ConfigOptions.booru.favorites)
                            ? ConfigOptions.booru.favorites
                            : Booru.providerList.slice(0, 9)
                        if (numKey < favorites.length) {
                            Booru.setProvider(favorites[numKey])
                        }
                        event.accepted = true
                        return
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
                        color: sidebarRoot.pinned ? Appearance.m3colors.m3surfaceText : Appearance.m3colors.m3secondaryText
                        text: sidebarRoot.pinned ? "push_pin" : "push_pin"
                    }

                    onClicked: sidebarRoot.pinned = !sidebarRoot.pinned
                }

                // Content
                Anime {
                    id: animeContent
                    anchors.fill: parent
                    previewImageId: root.previewActive && root.previewImageData ? root.previewImageData.id : null
                    onShowPreview: function(imageData, cachedSource, manualDownload, provider) {
                        root.showPreview(imageData, cachedSource, manualDownload, provider)
                        sidebarBackground.forceActiveFocus()  // Restore keyboard focus after click
                    }
                    onHidePreview: root.hidePreview()
                    onUpdatePreviewSource: function(cachedSource) {
                        // Update preview panel's cached source when download completes
                        root.previewCachedSource = cachedSource
                        // Also notify PreviewPanel directly to update its display
                        previewPanel.updateCachedSource(cachedSource)
                    }
                    onFocusReleased: sidebarBackground.forceActiveFocus()  // Restore keyboard focus after search
                    // Use onInputFieldChanged to catch when Anime sets its inputField property
                    onInputFieldChanged: root.tagInputFieldRef = inputField
                }

                // Provider picker overlay (inside sidebarBackground for proper z-order)
                PickerDialog {
                    id: pickerDialog
                    visible: root.showPickerDialog && root.sidebarOpen
                    anchors.fill: parent
                    z: 100

                    onProviderSelected: function(key) {
                        Booru.setProvider(key)
                    }

                    onClosed: {
                        root.showPickerDialog = false
                        sidebarBackground.forceActiveFocus()
                    }
                }
            }
        }
    }

    // Full-size preview panel (slides out to the right)
    // Note: imageData and cachedSource are set via setImageData() to avoid binding issues
    PreviewPanel {
        id: previewPanel
        active: root.previewActive && root.sidebarOpen
        manualDownload: root.previewManualDownload
        provider: root.previewProvider
        sidebarWidth: 420
        sidebarX: 8
        tagInputField: root.tagInputFieldRef  // For clickable tags
        currentIndex: root.currentImageIndex
        totalCount: root.imageCount

        onRequestClose: root.hidePreview()
        onRequestDownload: function(imageData) { root.downloadImage(imageData, false) }
        onRequestSaveWallpaper: function(imageData) { root.downloadImage(imageData, true) }
    }

    // Keybindings help overlay
    Loader {
        active: root.showKeybindingsHelp && root.sidebarOpen
        sourceComponent: PanelWindow {
            id: helpWindow
            visible: true
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "booru-help"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusiveZone: 0

            anchors {
                top: true
                left: true
            }
            margins.top: (screen.height - height) / 2
            margins.left: (screen.width - width) / 2

            width: helpContent.width + 48
            height: helpContent.height + 48
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.85)
                radius: Appearance.rounding.large

                Column {
                    id: helpContent
                    anchors.centerIn: parent
                    spacing: 16

                    StyledText {
                        text: "Keyboard Shortcuts"
                        font.pixelSize: Appearance.font.pixelSize.textLarge
                        font.bold: true
                        color: "#ffffff"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Row {
                        spacing: 32

                        // Navigation column
                        Column {
                            spacing: 4
                            StyledText { text: "Navigation"; font.bold: true; color: Appearance.m3colors.m3primary }
                            StyledText { text: "j / k  Scroll viewport"; color: "#ffffff" }
                            StyledText { text: "gg     Jump to top"; color: "#ffffff" }
                            StyledText { text: "G      Jump to bottom"; color: "#ffffff" }
                            StyledText { text: "Ctrl+d Page down"; color: "#ffffff" }
                            StyledText { text: "Ctrl+u Page up"; color: "#ffffff" }
                            StyledText { text: "n / N  Next/prev page"; color: "#ffffff" }
                            StyledText { text: "h / l  Prev/next image"; color: "#ffffff" }
                            StyledText { text: "Tab    Preview hovered"; color: "#ffffff" }
                            StyledText { text: "w      Wallpaper hovered"; color: "#ffffff" }
                        }

                        // Preview column
                        Column {
                            spacing: 4
                            StyledText { text: "Preview"; font.bold: true; color: Appearance.m3colors.m3primary }
                            StyledText { text: "d      Download"; color: "#ffffff" }
                            StyledText { text: "w      Save as wallpaper"; color: "#ffffff" }
                            StyledText { text: "g      Go to booru post"; color: "#ffffff" }
                            StyledText { text: "s      Open source"; color: "#ffffff" }
                            StyledText { text: "y      Yank URL"; color: "#ffffff" }
                            StyledText { text: "i      Toggle info"; color: "#ffffff" }
                            StyledText { text: "+ / =  Zoom in"; color: "#ffffff" }
                            StyledText { text: "-      Zoom out"; color: "#ffffff" }
                            StyledText { text: "0 / r  Reset zoom"; color: "#ffffff" }
                        }

                        // Video column
                        Column {
                            spacing: 4
                            StyledText { text: "Video"; font.bold: true; color: Appearance.m3colors.m3primary }
                            StyledText { text: "Space  Play/pause"; color: "#ffffff" }
                            StyledText { text: "m      Mute toggle"; color: "#ffffff" }
                            StyledText { text: "←      Seek -5s"; color: "#ffffff" }
                            StyledText { text: "→      Seek +5s"; color: "#ffffff" }
                            StyledText { text: ",      Slower"; color: "#ffffff" }
                            StyledText { text: ".      Faster"; color: "#ffffff" }
                        }

                        // Toggles column
                        Column {
                            spacing: 4
                            StyledText { text: "Toggles"; font.bold: true; color: Appearance.m3colors.m3primary }
                            StyledText { text: "P      Pin sidebar"; color: "#ffffff" }
                            StyledText { text: "x      Toggle NSFW"; color: "#ffffff" }
                            StyledText { text: "i      Focus input"; color: "#ffffff" }
                            StyledText { text: "p      Provider picker"; color: "#ffffff" }
                            StyledText { text: "1-9    Favorite providers"; color: "#ffffff" }
                            StyledText { text: "r      Reload page"; color: "#ffffff" }
                            StyledText { text: "R      Refresh cache"; color: "#ffffff" }
                            StyledText { text: ""; color: "transparent" }
                            StyledText { text: "General"; font.bold: true; color: Appearance.m3colors.m3primary }
                            StyledText { text: "q/Esc  Close"; color: "#ffffff" }
                            StyledText { text: "?      This help"; color: "#ffffff" }
                        }
                    }

                    StyledText {
                        text: "Press ? or Escape to close"
                        font.pixelSize: Appearance.font.pixelSize.textSmall
                        color: Appearance.m3colors.m3secondaryText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
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
