import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtMultimedia
import Quickshell
import Quickshell.Hyprland
import "../../common"
import "../../common/widgets"
import "../../common/utils"

/**
 * Individual booru image card with context menu.
 */
Button {
    id: root
    property var imageData
    property real rowHeight
    property bool manualDownload: false
    property string previewDownloadPath
    property string downloadPath
    property string nsfwPath
    property string fileName: {
        var url = imageData.file_url ? imageData.file_url : ""
        return decodeURIComponent(url.substring(url.lastIndexOf('/') + 1))
    }
    property string filePath: root.previewDownloadPath + "/" + root.fileName
    property real imageRadius: Appearance.rounding.small

    property bool showActions: false

    // Video detection - fallback to extracting from URL if file_ext not provided
    property string fileExt: {
        var ext = imageData.file_ext ? imageData.file_ext.toLowerCase() : ""
        if (!ext && imageData.file_url) {
            ext = imageData.file_url.split('.').pop().toLowerCase()
        }
        return ext
    }
    property bool isVideo: (fileExt === "mp4" || fileExt === "webm")
    property bool isGif: fileExt === "gif"

    // Manual download for static images (providers that block direct requests)
    ImageDownloaderProcess {
        id: imageDownloader
        enabled: root.manualDownload && !root.isGif && !root.isVideo
        filePath: root.filePath
        sourceUrl: root.imageData.preview_url ? root.imageData.preview_url : root.imageData.sample_url
        onDone: (path, width, height) => {
            imageObject.source = ""
            imageObject.source = "file://" + path
            if (!modelData.width || !modelData.height) {
                modelData.width = width
                modelData.height = height
                modelData.aspect_ratio = width / height
            }
        }
    }

    // Manual download for GIFs (providers that block direct requests)
    property string gifFileName: {
        var url = modelData.file_url ? modelData.file_url : ""
        return decodeURIComponent(url.substring(url.lastIndexOf('/') + 1))
    }
    property string gifFilePath: root.previewDownloadPath + "/gif_" + root.gifFileName
    property string localGifSource: ""

    ImageDownloaderProcess {
        id: gifDownloader
        enabled: root.manualDownload && root.isGif
        filePath: root.gifFilePath
        sourceUrl: modelData.file_url ? modelData.file_url : ""
        onDone: (path, width, height) => {
            root.localGifSource = "file://" + path
        }
    }

    StyledToolTip {
        // Show first 5 tags, truncated to max 200 chars
        property var tagList: (root.imageData.tags ? root.imageData.tags : "").split(" ").filter(t => t.length > 0)
        property string rawContent: tagList.slice(0, 5).join(", ") + (tagList.length > 5 ? " ..." : "")
        content: rawContent.length > 200 ? rawContent.substring(0, 200) + "..." : rawContent
    }

    padding: 0
    implicitWidth: root.rowHeight * (modelData.aspect_ratio || 1)
    implicitHeight: root.rowHeight
    z: showActions ? 100 : 0

    background: Rectangle {
        implicitWidth: root.rowHeight * (modelData.aspect_ratio || 1)
        implicitHeight: root.rowHeight
        radius: imageRadius
        color: Appearance.colors.colLayer2
    }

    contentItem: Item {
        anchors.fill: parent

        // Static image display (non-GIF, non-video)
        Image {
            id: imageObject
            anchors.fill: parent
            visible: !root.isVideo && !root.isGif
            fillMode: Image.PreserveAspectCrop
            source: (root.isVideo || root.isGif) ? "" : (modelData.preview_url ? modelData.preview_url : "")
            sourceSize.width: root.rowHeight * (modelData.aspect_ratio || 1)
            sourceSize.height: root.rowHeight
            asynchronous: true
            cache: true

            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: root.rowHeight * (modelData.aspect_ratio || 1)
                    height: root.rowHeight
                    radius: imageRadius
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
            // Use local file if manual download, otherwise direct URL
            source: {
                if (!root.isGif) return ""
                if (root.manualDownload) return root.localGifSource
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

        // Video display (MediaPlayer + VideoOutput)
        Item {
            id: videoContainer
            anchors.fill: parent
            visible: root.isVideo

            MediaPlayer {
                id: mediaPlayer
                source: root.isVideo ? (root.imageData.file_url ? root.imageData.file_url : "") : ""
                loops: MediaPlayer.Infinite
                audioOutput: AudioOutput { muted: true }
                videoOutput: videoOutput

                Component.onCompleted: {
                    if (root.isVideo) play()
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

            // Play icon overlay (shown when paused)
            Rectangle {
                anchors.centerIn: parent
                width: 40
                height: 40
                radius: 20
                color: Qt.rgba(0, 0, 0, 0.6)
                visible: mediaPlayer.playbackState !== MediaPlayer.PlayingState

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 24
                    color: "#ffffff"
                    text: "play_arrow"
                }
            }
        }

        // Loading indicator (static images)
        Rectangle {
            anchors.fill: parent
            radius: imageRadius
            color: Appearance.colors.colLayer2
            visible: !root.isVideo && !root.isGif && imageObject.status !== Image.Ready

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
                            // mpv can stream URLs directly
                            Quickshell.execDetached(["mpv", "--loop", root.imageData.file_url])
                        } else {
                            // Download to temp and open with system default
                            const tmpFile = `/tmp/booru_${root.fileName}`
                            Quickshell.execDetached(["bash", "-c",
                                `curl -sL '${root.imageData.file_url}' -o '${tmpFile}' && xdg-open '${tmpFile}'`
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
                        const targetPath = root.imageData.is_nsfw ? root.nsfwPath : root.downloadPath
                        Quickshell.execDetached(["bash", "-c",
                            `mkdir -p '${targetPath}' && curl -sL '${root.imageData.file_url}' -o '${targetPath}/${root.fileName}' && notify-send 'Download complete' '${targetPath}/${root.fileName}' -a 'Booru'`
                        ])
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
                        const wallpaperPath = root.downloadPath.replace(/\/booru$/, '/wallpapers')
                        Quickshell.execDetached(["bash", "-c",
                            `mkdir -p '${wallpaperPath}' && curl -sL '${root.imageData.file_url}' -o '${wallpaperPath}/${root.fileName}' && notify-send 'Wallpaper saved' '${wallpaperPath}/${root.fileName}' -a 'Booru'`
                        ])
                    }
                }
            }
        }
    }

    onClicked: {
        if (!showActions) {
            Qt.openUrlExternally(imageData.source || imageData.file_url)
        }
    }
}
