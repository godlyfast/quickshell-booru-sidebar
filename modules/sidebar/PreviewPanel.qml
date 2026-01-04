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

/**
 * Full-size preview panel that slides out from the sidebar edge.
 * Shows images, GIFs, and videos with playback controls.
 */
Scope {
    id: root

    // Input properties (from SidebarLeft)
    property var imageData: null
    property bool active: false
    property string cachedSource: ""
    property bool manualDownload: false
    property string provider: ""
    property real sidebarWidth: 420
    property real sidebarX: 8  // Left margin of sidebar

    // Computed properties
    property bool panelVisible: active && imageData !== null
    property bool isVideo: imageData ? (imageData.file_ext === "mp4" || imageData.file_ext === "webm") : false
    property bool isGif: imageData ? (imageData.file_ext === "gif") : false

    // Track if mouse is over the preview panel
    property bool mouseOverPreview: false

    // Close delay timer - prevents flicker when moving between sidebar and preview
    Timer {
        id: closeDelayTimer
        interval: 200
        onTriggered: {
            if (!root.mouseOverPreview) {
                root.active = false
            }
        }
    }

    // Signal to notify parent that preview wants to close
    signal requestClose()

    Loader {
        id: panelLoader
        active: true

        sourceComponent: PanelWindow {
            id: previewWindow
            visible: root.panelVisible

            // Panel dimensions - take up remaining screen width
            property real panelWidth: Math.min(screen.width - root.sidebarWidth - root.sidebarX - 24, 800)
            property real panelHeight: screen.height - 16

            // Width needs to include sidebar offset + preview panel width
            implicitWidth: root.sidebarX + root.sidebarWidth + 8 + panelWidth + 16
            implicitHeight: panelHeight

            // Layer shell configuration
            WlrLayershell.namespace: "quickshell:previewPanel"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            color: "transparent"

            // Anchor to left edge, use internal offset to position right of sidebar
            anchors {
                top: true
                left: true
                bottom: true
            }

            // Animated content wrapper - positioned to the right of sidebar
            Item {
                id: contentWrapper
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: previewWindow.panelWidth + 16

                // Position to right of sidebar + slide animation
                x: root.sidebarX + root.sidebarWidth + 8 + (root.panelVisible ? 0 : -30)
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

                // Mouse area for detecting hover over the entire panel
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onContainsMouseChanged: {
                        root.mouseOverPreview = containsMouse
                        if (!containsMouse) {
                            closeDelayTimer.restart()
                        } else {
                            closeDelayTimer.stop()
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

                        // Close button (top-right)
                        RippleButton {
                            id: closeButton
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 8
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Qt.rgba(0, 0, 0, 0.4)
                            colBackgroundHover: Qt.rgba(0, 0, 0, 0.6)
                            z: 100

                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: 18
                                color: "#ffffff"
                                text: "close"
                            }

                            onClicked: {
                                root.active = false
                                root.requestClose()
                            }
                        }

                        // Content loader - switches between image/gif/video
                        Loader {
                            id: contentLoader
                            anchors.fill: parent
                            anchors.margins: 8

                            sourceComponent: {
                                if (!root.imageData) return null
                                if (root.isVideo) return videoPreviewComponent
                                if (root.isGif) return gifPreviewComponent
                                return imagePreviewComponent
                            }
                        }
                    }
                }
            }
        }
    }

    // Image preview component
    Component {
        id: imagePreviewComponent

        Image {
            id: imagePreview
            fillMode: Image.PreserveAspectFit
            asynchronous: true

            source: {
                // 1. Use cached source if available
                if (root.cachedSource && root.cachedSource.length > 0) return root.cachedSource
                // 2. Use file_url or sample_url
                if (root.imageData && root.imageData.file_url) return root.imageData.file_url
                if (root.imageData && root.imageData.sample_url) return root.imageData.sample_url
                return ""
            }

            // Loading indicator
            BusyIndicator {
                anchors.centerIn: parent
                running: imagePreview.status === Image.Loading
                visible: running
            }
        }
    }

    // GIF preview component
    Component {
        id: gifPreviewComponent

        AnimatedImage {
            id: gifPreview
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            playing: true
            cache: true

            source: {
                if (root.cachedSource && root.cachedSource.length > 0) return root.cachedSource
                if (root.imageData && root.imageData.file_url) return root.imageData.file_url
                return ""
            }

            // Loading indicator
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

            MediaPlayer {
                id: mediaPlayer
                source: {
                    if (root.cachedSource && root.cachedSource.length > 0) return root.cachedSource
                    if (root.imageData && root.imageData.file_url) return root.imageData.file_url
                    return ""
                }
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
