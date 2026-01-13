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
import "../../services" as Services

/**
 * Left sidebar panel window containing the Booru browser.
 */
Scope {
    id: root
    property bool sidebarOpen: false

    // Handle sidebar open/close
    onSidebarOpenChanged: {
        Services.Logger.info("Sidebar", `Sidebar ${sidebarOpen ? "opened" : "closed"}`)
        if (sidebarOpen) {
            // Ensure keyboard focus when sidebar opens (delayed to ensure component is ready)
            focusTimer.start()
        } else {
            Services.Booru.stopAllVideos()
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

    // Delayed focus restore after input field releases
    // Uses 200ms delay to wait for UI re-render after clearResponses()
    Timer {
        id: focusRestoreTimer
        interval: 200
        onTriggered: {
            if (sidebarLoader.item && sidebarLoader.item.restoreFocus) {
                sidebarLoader.item.restoreFocus()
            }
        }
    }

    // Preview panel reference (alias for access from within Loader components)
    property alias previewPanelRef: previewPanel

    // Preview panel state
    property var previewImageData: null
    property bool previewActive: false
    property string previewCachedSource: ""
    property bool previewManualDownload: false
    property string previewProvider: ""
    property var tagInputFieldRef: null  // Reference to search input for clickable tags

    // Called by BooruImage when clicked to show preview
    function showPreview(imageData, cachedSource, manualDownload, provider) {
        Services.Logger.info("Sidebar", `showPreview: id=${imageData ? imageData.id : 'null'} provider=${provider}`)
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
        Services.Logger.debug("Sidebar", "hidePreview called")
        // Stop any playing video in preview before closing
        previewPanel.stopVideo()
        // Set flag BEFORE closing preview to prevent focus grab from closing sidebar
        root.closingPreviewIntentionally = true
        root.previewActive = false
    }

    // UI state
    property bool showKeybindingsHelp: false
    property bool showPickerDialog: false
    property bool showDebugPanel: false
    property bool closingPreviewIntentionally: false  // Flag to prevent focus grab clear from closing sidebar

    // Reactive computed properties for position indicator
    // These re-evaluate when Services.Booru.responses or previewImageData changes
    property int imageCount: {
        var count = 0
        var responses = Services.Booru.responses  // Creates reactive dependency
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
        var responses = Services.Booru.responses  // Creates reactive dependency
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
        var responses = Services.Booru.responses
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

    // Compute expected cache path for an image using CacheIndex for proper hires prioritization
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

        // Base identifier - md5 preferred (consistent), fallback to id
        var baseId = imageData.md5 ? imageData.md5 : imageData.id

        // Handle ugoira/archives specially - they convert to WebM with ugoira_ prefix
        if (ext === "zip" || ext === "rar" || ext === "7z") {
            var ugoiraName = "ugoira_" + baseId + ".webm"
            var ugoiraPath = Services.CacheIndex.lookup(ugoiraName)
            if (ugoiraPath) return ugoiraPath
            // Return constructed path for when cache hasn't been populated yet
            return "file://" + cacheDir + "/" + ugoiraName
        }

        // Use CacheIndex.lookup() which properly prioritizes hires_ files
        // This handles images, GIFs, and videos with proper prefix checking
        var cachedPath = Services.CacheIndex.lookup(fileName)
        if (cachedPath) return cachedPath

        // Fallback: construct expected path for files not yet in cache
        if (ext === "gif") {
            return "file://" + cacheDir + "/gif_" + fileName
        } else if (ext === "mp4" || ext === "webm") {
            return "file://" + cacheDir + "/video_" + baseId + "." + ext
        } else {
            // Images use hires_ prefix
            if (provider === "danbooru") {
                return "file://" + cacheDir + "/hires_" + baseId + "." + ext
            }
            return "file://" + cacheDir + "/hires_" + fileName
        }
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

            // Force focus back to sidebar after input field releases
            function restoreFocus() {
                // First clear any lingering focus from input
                if (animeContent.inputField) {
                    animeContent.inputField.focus = false
                }
                // Then force focus to sidebar background
                sidebarBackground.forceActiveFocus()
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
                // Keep focus grab active when visible (even when pinned) to receive keyboard events
                active: sidebarRoot.visible
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
                    // Only auto-close when not pinned
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

                // Click anywhere on sidebar to recover keyboard focus
                MouseArea {
                    anchors.fill: parent
                    propagateComposedEvents: true
                    onPressed: (mouse) => {
                        sidebarBackground.forceActiveFocus()
                        mouse.accepted = false  // Let clicks through to children
                    }
                }

                // Keyboard handler (delegates all key events)
                KeybindingHandler {
                    id: keyHandler
                    sidebarState: root
                    animeContent: animeContent
                    previewPanel: root.previewPanelRef  // Use explicit alias to access from within Loader
                    sidebarRoot: sidebarRoot
                    sidebarBackground: sidebarBackground
                }

                Keys.onPressed: (event) => {
                    event.accepted = keyHandler.handleKeyPress(event)
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
                    z: ZOrder.button

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 16
                        color: sidebarRoot.pinned ? Appearance.m3colors.m3surfaceText : Appearance.m3colors.m3secondaryText
                        text: sidebarRoot.pinned ? "push_pin" : "push_pin"
                    }

                    onClicked: {
                        Services.Logger.info("Sidebar", `Pin button: ${!sidebarRoot.pinned ? "pinned" : "unpinned"}`)
                        sidebarRoot.pinned = !sidebarRoot.pinned
                    }
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
                    onFocusReleased: root.focusRestoreTimer.restart()  // Delayed focus restore after search
                    // Use onInputFieldChanged to catch when Anime sets its inputField property
                    onInputFieldChanged: root.tagInputFieldRef = inputField
                }

                // Restore focus when API response finishes (ensures focus after UI re-renders)
                Connections {
                    target: Services.Booru
                    function onResponseFinished() {
                        // Small delay to let UI settle after response data is rendered
                        responseSettleTimer.restart()
                    }
                }

                Timer {
                    id: responseSettleTimer
                    interval: 50
                    onTriggered: sidebarBackground.forceActiveFocus()
                }

                // Provider picker overlay (inside sidebarBackground for proper z-order)
                PickerDialog {
                    id: pickerDialog
                    visible: root.showPickerDialog && root.sidebarOpen
                    anchors.fill: parent
                    z: ZOrder.overlay

                    onProviderSelected: function(key) {
                        Services.Booru.setProvider(key)
                    }

                    onClosed: {
                        root.showPickerDialog = false
                        sidebarBackground.forceActiveFocus()
                    }
                }

                // Debug panel overlay (F12 to open)
                DebugPanel {
                    id: debugPanel
                    parent: sidebarBackground
                    visible: root.showDebugPanel && root.sidebarOpen
                    z: ZOrder.modal

                    onClosed: {
                        root.showDebugPanel = false
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
        onRequestDownload: function(imageData) { DownloadManager.downloadImage(imageData, root.previewProvider, false) }
        onRequestSaveWallpaper: function(imageData) { DownloadManager.downloadImage(imageData, root.previewProvider, true) }
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
                            StyledText { text: "i      Focus search"; color: "#ffffff" }
                            StyledText { text: "z      Focus page"; color: "#ffffff" }
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
            Services.Logger.info("Sidebar", `GlobalShortcut: toggle → ${!root.sidebarOpen ? "open" : "close"}`)
            root.sidebarOpen = !root.sidebarOpen
        }
    }
}
