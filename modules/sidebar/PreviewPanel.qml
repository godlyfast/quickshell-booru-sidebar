import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../common"
import "../common/widgets"
import "./preview"
import "../../services"

/**
 * Full-size preview panel that slides out from the sidebar edge.
 * Shows images, GIFs, and videos with playback controls.
 */
Scope {
    id: root

    // Input properties (from SidebarLeft)
    property var imageData: null  // May be externally bound - DO NOT rely on this
    property bool active: false
    property string cachedSource: ""
    property bool manualDownload: false
    property string provider: ""
    property real sidebarWidth: 420
    property real sidebarX: 8  // Left margin of sidebar

    // Stop video when global stop signal is emitted (sidebar close, page change, etc.)
    Connections {
        target: Booru
        function onStopAllVideos() {
            if (videoContainer.mediaPlayer) {
                videoContainer.mediaPlayer.stop()
            }
        }
    }

    // STABLE image data - only updated via setImageData(), immune to external binding issues
    property var stableImageData: null

    // Helper to detect media type from extension or URL
    function detectMediaType(ext, url) {
        ext = ext ? ext.toLowerCase() : ""
        var urlLower = url ? url.toLowerCase() : ""
        if (ext === "mp4" || ext === "webm" || urlLower.endsWith(".mp4") || urlLower.endsWith(".webm")) {
            return "video"
        } else if (ext === "gif" || urlLower.endsWith(".gif")) {
            return "gif"
        }
        return "image"
    }

    // Explicit update function to avoid binding-related issues
    function setImageData(newImageData, newCachedSource) {
        // Stop any playing video before switching to new content
        if (videoContainer.mediaPlayer) {
            videoContainer.mediaPlayer.stop()
        }
        // Store in STABLE property, not the externally-bound one
        stableImageData = newImageData
        // Force update of stable values
        if (newImageData) {
            currentImageId = newImageData.id
            // Determine URL first so we can check its extension
            var url = ""
            if (newCachedSource && newCachedSource.length > 0) {
                url = newCachedSource
            } else if (newImageData.file_url) {
                url = newImageData.file_url
            } else if (newImageData.sample_url) {
                url = newImageData.sample_url
            }
            stableImageUrl = url
            // Detect media type from API extension OR cached file extension
            var ext = newImageData.file_ext ? newImageData.file_ext.toLowerCase() : ""
            stableMediaType = detectMediaType(ext, url)
            zoomLevel = 1.0
            panX = 0
            panY = 0
            imageCacheTriedAndFailed = false
            gifCacheTriedAndFailed = false
        } else {
            stableImageUrl = ""
            stableMediaType = "image"
        }
    }

    // Update cached source when download completes (e.g., zerochan fallback found correct extension)
    function updateCachedSource(newSource) {
        if (newSource && newSource.length > 0) {
            stableImageUrl = newSource
            // Re-detect media type from new source (may have different extension)
            var ext = stableImageData ? stableImageData.file_ext : ""
            stableMediaType = detectMediaType(ext, newSource)
            imageCacheTriedAndFailed = false
            gifCacheTriedAndFailed = false
        }
    }

    // Computed properties - use stableImageData instead of imageData
    property bool panelVisible: active && stableImageData !== null
    onPanelVisibleChanged: {
        // Stop video playback when preview is closed
        if (!panelVisible && videoContainer.mediaPlayer) {
            videoContainer.mediaPlayer.stop()
        }
    }
    property bool isVideo: stableImageData ? (stableImageData.file_ext === "mp4" || stableImageData.file_ext === "webm") : false
    // Check both API extension AND cached file extension (zerochan GIFs may be served from .jpg URLs)
    property bool isGif: (stableImageData && stableImageData.file_ext === "gif") || stableImageUrl.toLowerCase().endsWith(".gif")

    // Cached image ID to detect actual changes (var comparison is unreliable)
    property var currentImageId: null

    // Stable URL cache - only updates when image actually changes
    property string stableImageUrl: ""
    property string stableMediaType: "image"  // "image", "gif", or "video"

    // Zoom/pan state for image preview
    property real zoomLevel: 1.0
    property real panX: 0
    property real panY: 0
    property real minZoom: 1.0
    property real maxZoom: 5.0

    // Track cache fallback state (reset on image change)
    property bool imageCacheTriedAndFailed: false
    property bool gifCacheTriedAndFailed: false

    // DISABLED: onImageDataChanged causes issues with stale binding updates
    // All updates now go through setImageData() function
    // onImageDataChanged: { ... }

    onCachedSourceChanged: {
        // Update URL if cached source becomes available for current image
        if (cachedSource && cachedSource.length > 0 && stableImageData && stableImageData.id === currentImageId) {
            stableImageUrl = cachedSource
        }
    }

    // Expose the panel window for HyprlandFocusGrab inclusion
    property var panelWindow: panelLoader.item

    // Signal to notify parent that preview wants to close
    signal requestClose()

    // Signal to request download of current image
    signal requestDownload(var imageData)

    // Signal to request saving as wallpaper
    signal requestSaveWallpaper(var imageData)

    // Video control functions (for keyboard shortcuts)
    // These safely no-op if current preview isn't a video
    function stopVideo() {
        if (videoContainer.mediaPlayer) {
            videoContainer.mediaPlayer.stop()
        }
    }

    function togglePlayPause() {
        if (!root.isVideo || !contentLoader.item) return
        var player = contentLoader.item.mediaPlayer
        if (!player) return
        if (player.playbackState === MediaPlayer.PlayingState) {
            player.pause()
        } else {
            player.play()
        }
    }

    function toggleMute() {
        if (!root.isVideo || !contentLoader.item) return
        var audio = contentLoader.item.audioOutput
        if (audio) audio.muted = !audio.muted
    }

    function seekRelative(ms) {
        if (!root.isVideo || !contentLoader.item) return
        var player = contentLoader.item.mediaPlayer
        if (!player) return
        var newPos = Math.max(0, Math.min(player.duration, player.position + ms))
        player.position = newPos
    }

    function changeSpeed(delta) {
        if (!root.isVideo || !contentLoader.item) return
        var player = contentLoader.item.mediaPlayer
        if (!player) return
        var speeds = [0.5, 1.0, 1.5, 2.0]
        var currentIdx = -1
        for (var i = 0; i < speeds.length; i++) {
            if (Math.abs(player.playbackRate - speeds[i]) < 0.01) {
                currentIdx = i
                break
            }
        }
        if (currentIdx < 0) currentIdx = 1  // Default to 1.0x
        var newIdx = Math.max(0, Math.min(speeds.length - 1, currentIdx + delta))
        player.playbackRate = speeds[newIdx]
    }

    Loader {
        id: panelLoader
        active: true

        sourceComponent: PanelWindow {
            id: previewWindow
            visible: root.panelVisible

            // Panel dimensions - take up remaining screen width
            property real panelWidth: Math.min(screen.width - root.sidebarWidth - root.sidebarX - 24, 800)
            property real panelHeight: screen.height - 16

            // Left margin to position right of sidebar (no overlap)
            property real leftMargin: root.sidebarX + root.sidebarWidth + 8

            // Only cover preview area, not sidebar
            implicitWidth: panelWidth + 16
            implicitHeight: panelHeight

            // Layer shell configuration
            WlrLayershell.namespace: "quickshell:previewPanel"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            color: "transparent"

            // Use margins to position right of sidebar
            WlrLayershell.margins.left: leftMargin

            // Anchor to left edge (with margin), top, bottom
            anchors {
                top: true
                left: true
                bottom: true
            }

            // Content wrapper - no longer needs x offset
            Item {
                id: contentWrapper
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: previewWindow.panelWidth + 16

                // Slide animation (relative to panel, not screen)
                x: root.panelVisible ? 0 : -30
                opacity: root.panelVisible ? 1 : 0

                Behavior on x {
                    NumberAnimation {
                        duration: root.panelVisible ? Appearance.animation.elementMoveEnter.duration : Appearance.animation.elementMoveExit.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root.panelVisible ? Appearance.animation.elementMoveEnter.bezierCurve : Appearance.animation.elementMoveExit.bezierCurve
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.panelVisible ? Appearance.animation.elementMoveEnter.duration : Appearance.animation.elementMoveExit.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root.panelVisible ? Appearance.animation.elementMoveEnter.bezierCurve : Appearance.animation.elementMoveExit.bezierCurve
                    }
                }

                // Shadow
                Rectangle {
                    anchors.fill: previewBackground
                    anchors.margins: -4
                    radius: previewBackground.radius + 4
                    color: "transparent"
                    border.width: 8
                    border.color: Qt.rgba(0, 0, 0, 0.3)
                    z: -1
                }

                // Main background
                Rectangle {
                    id: previewBackground
                    anchors.fill: parent
                    anchors.margins: 8
                    anchors.leftMargin: 0  // No left margin - flush transition from sidebar
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.m3colors.m3borderSecondary
                    radius: Appearance.rounding.large
                    clip: true

                    // Top-right button row
                    Row {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 8
                        spacing: 8
                        z: 100

                        // Download button
                        RippleButton {
                            id: downloadButton
                            visible: root.stableImageData && root.stableImageData.file_url
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Qt.rgba(0, 0, 0, 0.4)
                            colBackgroundHover: Qt.rgba(0, 0, 0, 0.6)
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: 18
                                color: "#ffffff"
                                text: "download"
                            }
                            onClicked: root.requestDownload(root.stableImageData)
                            StyledToolTip { content: "Download" }
                        }

                        // Save as wallpaper button
                        RippleButton {
                            id: wallpaperButton
                            visible: root.stableImageData && root.stableImageData.file_url
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Qt.rgba(0, 0, 0, 0.4)
                            colBackgroundHover: Qt.rgba(0, 0, 0, 0.6)
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: 18
                                color: "#ffffff"
                                text: "wallpaper"
                            }
                            onClicked: root.requestSaveWallpaper(root.stableImageData)
                            StyledToolTip { content: "Save as wallpaper" }
                        }

                        // Go to booru post button
                        RippleButton {
                            id: goToPostButton
                            property string postUrl: Booru.getPostUrl(root.provider, root.stableImageData ? root.stableImageData.id : "")
                            property string providerName: {
                                var p = Booru.providers[root.provider]
                                return p && p.name ? p.name : root.provider
                            }
                            visible: postUrl.length > 0
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Qt.rgba(0, 0, 0, 0.4)
                            colBackgroundHover: Qt.rgba(0, 0, 0, 0.6)
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: 18
                                color: "#ffffff"
                                text: "language"
                            }
                            onClicked: Qt.openUrlExternally(postUrl)
                            StyledToolTip { content: "View on " + goToPostButton.providerName }
                        }

                        // Open original source button (Pixiv, Twitter, etc.)
                        RippleButton {
                            id: openSourceButton
                            visible: root.stableImageData && root.stableImageData.source && root.stableImageData.source.length > 0
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Qt.rgba(0, 0, 0, 0.4)
                            colBackgroundHover: Qt.rgba(0, 0, 0, 0.6)
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: 18
                                color: "#ffffff"
                                text: "open_in_new"
                            }
                            onClicked: Qt.openUrlExternally(root.stableImageData.source)
                            StyledToolTip { content: "Open source" }
                        }

                        // Close button
                        RippleButton {
                            id: closeButton
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Qt.rgba(0, 0, 0, 0.4)
                            colBackgroundHover: Qt.rgba(0, 0, 0, 0.6)
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: 18
                                color: "#ffffff"
                                text: "close"
                            }
                            onClicked: root.requestClose()
                            StyledToolTip { content: "Close" }
                        }
                    }

                    // Content loader - switches between image/gif/video
                    Loader {
                        id: contentLoader
                        anchors.fill: parent
                        anchors.margins: 8

                        // Use stable media type to prevent unnecessary reloads
                        sourceComponent: {
                            if (root.stableMediaType === "video") return videoPreviewComponent
                            if (root.stableMediaType === "gif") return gifPreviewComponent
                            if (root.stableImageUrl.length > 0) return imagePreviewComponent
                            return null
                        }
                    }
                }
            }
        }
    }

    // Image preview component with zoom/pan support
    Component {
        id: imagePreviewComponent

        Item {
            id: zoomContainer

            Image {
                id: imagePreview
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                source: {
                    // If cache failed, use network URL directly
                    if (root.imageCacheTriedAndFailed && root.stableImageData) {
                        return root.stableImageData.file_url || root.stableImageData.sample_url || ""
                    }
                    return root.stableImageUrl
                }

                onStatusChanged: {
                    // If cached file:// source failed, fall back to network
                    if (status === Image.Error && root.stableImageUrl.indexOf("file://") === 0 && !root.imageCacheTriedAndFailed) {
                        console.log("[PreviewPanel] Cache miss, falling back to network:", root.stableImageUrl)
                        root.imageCacheTriedAndFailed = true
                    }
                }

                transform: [
                    Scale {
                        xScale: root.zoomLevel
                        yScale: root.zoomLevel
                        origin.x: imagePreview.width / 2
                        origin.y: imagePreview.height / 2
                    },
                    Translate {
                        x: root.panX
                        y: root.panY
                    }
                ]

                Behavior on scale {
                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton

                property real startX: 0
                property real startY: 0
                property real startPanX: 0
                property real startPanY: 0

                cursorShape: root.zoomLevel > 1.0 ? Qt.OpenHandCursor : Qt.ArrowCursor

                onPressed: function(mouse) {
                    startX = mouse.x
                    startY = mouse.y
                    startPanX = root.panX
                    startPanY = root.panY
                    if (root.zoomLevel > 1.0) cursorShape = Qt.ClosedHandCursor
                }

                onReleased: {
                    if (root.zoomLevel > 1.0) cursorShape = Qt.OpenHandCursor
                }

                onPositionChanged: function(mouse) {
                    if (pressed && root.zoomLevel > 1.0) {
                        root.panX = startPanX + (mouse.x - startX)
                        root.panY = startPanY + (mouse.y - startY)
                    }
                }

                onWheel: function(wheel) {
                    var zoomDelta = wheel.angleDelta.y > 0 ? 1.15 : 0.87
                    var newZoom = Math.max(root.minZoom, Math.min(root.maxZoom, root.zoomLevel * zoomDelta))
                    root.zoomLevel = newZoom
                    // Reset pan when zooming back to 1.0
                    if (newZoom <= 1.0) {
                        root.panX = 0
                        root.panY = 0
                    }
                    zoomIndicator.show()
                }

                onDoubleClicked: {
                    root.zoomLevel = 1.0
                    root.panX = 0
                    root.panY = 0
                    zoomIndicator.show()
                }
            }

            // Zoom percentage indicator
            Rectangle {
                id: zoomIndicator
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 16
                width: zoomText.implicitWidth + 16
                height: zoomText.implicitHeight + 8
                radius: Appearance.rounding.small
                color: Qt.rgba(0, 0, 0, 0.6)
                opacity: 0
                visible: opacity > 0

                function show() {
                    opacity = 1
                    hideTimer.restart()
                }

                Timer {
                    id: hideTimer
                    interval: 1000
                    onTriggered: zoomIndicator.opacity = 0
                }

                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }

                StyledText {
                    id: zoomText
                    anchors.centerIn: parent
                    text: Math.round(root.zoomLevel * 100) + "%"
                    font.pixelSize: Appearance.font.pixelSize.textSmall
                    color: "#ffffff"
                }
            }

            BusyIndicator {
                anchors.centerIn: parent
                running: imagePreview.status === Image.Loading
                visible: running
            }
        }
    }

    // GIF preview component with zoom/pan support
    Component {
        id: gifPreviewComponent

        Item {
            id: gifZoomContainer

            AnimatedImage {
                id: gifPreview
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                playing: true
                cache: true
                source: {
                    // If cache failed, use network URL directly
                    if (root.gifCacheTriedAndFailed && root.stableImageData) {
                        return root.stableImageData.file_url || root.stableImageData.sample_url || ""
                    }
                    return root.stableImageUrl
                }

                onStatusChanged: {
                    // If cached file:// source failed, fall back to network
                    if (status === Image.Error && root.stableImageUrl.indexOf("file://") === 0 && !root.gifCacheTriedAndFailed) {
                        console.log("[PreviewPanel] GIF cache miss, falling back to network:", root.stableImageUrl)
                        root.gifCacheTriedAndFailed = true
                    }
                }

                transform: [
                    Scale {
                        xScale: root.zoomLevel
                        yScale: root.zoomLevel
                        origin.x: gifPreview.width / 2
                        origin.y: gifPreview.height / 2
                    },
                    Translate {
                        x: root.panX
                        y: root.panY
                    }
                ]
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton

                property real startX: 0
                property real startY: 0
                property real startPanX: 0
                property real startPanY: 0

                cursorShape: root.zoomLevel > 1.0 ? Qt.OpenHandCursor : Qt.ArrowCursor

                onPressed: function(mouse) {
                    startX = mouse.x
                    startY = mouse.y
                    startPanX = root.panX
                    startPanY = root.panY
                    if (root.zoomLevel > 1.0) cursorShape = Qt.ClosedHandCursor
                }

                onReleased: {
                    if (root.zoomLevel > 1.0) cursorShape = Qt.OpenHandCursor
                }

                onPositionChanged: function(mouse) {
                    if (pressed && root.zoomLevel > 1.0) {
                        root.panX = startPanX + (mouse.x - startX)
                        root.panY = startPanY + (mouse.y - startY)
                    }
                }

                onWheel: function(wheel) {
                    var zoomDelta = wheel.angleDelta.y > 0 ? 1.15 : 0.87
                    var newZoom = Math.max(root.minZoom, Math.min(root.maxZoom, root.zoomLevel * zoomDelta))
                    root.zoomLevel = newZoom
                    if (newZoom <= 1.0) {
                        root.panX = 0
                        root.panY = 0
                    }
                    gifZoomIndicator.show()
                }

                onDoubleClicked: {
                    root.zoomLevel = 1.0
                    root.panX = 0
                    root.panY = 0
                    gifZoomIndicator.show()
                }
            }

            // Zoom percentage indicator
            Rectangle {
                id: gifZoomIndicator
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 16
                width: gifZoomText.implicitWidth + 16
                height: gifZoomText.implicitHeight + 8
                radius: Appearance.rounding.small
                color: Qt.rgba(0, 0, 0, 0.6)
                opacity: 0
                visible: opacity > 0

                function show() {
                    opacity = 1
                    gifHideTimer.restart()
                }

                Timer {
                    id: gifHideTimer
                    interval: 1000
                    onTriggered: gifZoomIndicator.opacity = 0
                }

                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }

                StyledText {
                    id: gifZoomText
                    anchors.centerIn: parent
                    text: Math.round(root.zoomLevel * 100) + "%"
                    font.pixelSize: Appearance.font.pixelSize.textSmall
                    color: "#ffffff"
                }
            }

            BusyIndicator {
                anchors.centerIn: parent
                running: gifPreview.status === AnimatedImage.Loading
                visible: running
            }
        }
    }

    // Video preview component
    Component {
        id: videoPreviewComponent

        Item {
            id: videoContainer

            // Expose player and audio for external control
            property alias mediaPlayer: mediaPlayer
            property alias audioOutput: audioOutput

            MediaPlayer {
                id: mediaPlayer
                // Use stable URL to prevent re-renders
                source: root.stableImageUrl
                audioOutput: audioOutput
                videoOutput: videoOutput
                loops: MediaPlayer.Infinite

                onSourceChanged: {
                    if (source.toString().length > 0) {
                        play()
                    }
                }
            }

            AudioOutput {
                id: audioOutput
                volume: 0.5
                muted: false
            }

            VideoOutput {
                id: videoOutput
                anchors.fill: parent
                anchors.bottomMargin: 60  // Space for controls
                fillMode: VideoOutput.PreserveAspectFit
            }

            // Video controls
            VideoControls {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                player: mediaPlayer
                audio: audioOutput
            }

            // Loading indicator
            BusyIndicator {
                anchors.centerIn: videoOutput
                running: mediaPlayer.playbackState === MediaPlayer.StoppedState && mediaPlayer.source.toString().length > 0
                visible: running
            }
        }
    }
}
