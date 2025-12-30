import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
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
    property string fileName: decodeURIComponent((imageData.file_url ?? "").substring((imageData.file_url ?? "").lastIndexOf('/') + 1))
    property string filePath: `${root.previewDownloadPath}/${root.fileName}`
    property real imageRadius: Appearance.rounding.small

    property bool showActions: false

    ImageDownloaderProcess {
        id: imageDownloader
        enabled: root.manualDownload
        filePath: root.filePath
        sourceUrl: root.imageData.preview_url ?? root.imageData.sample_url
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

    StyledToolTip {
        text: root.imageData.tags ?? ""
    }

    padding: 0
    implicitWidth: root.rowHeight * (modelData.aspect_ratio || 1)
    implicitHeight: root.rowHeight

    background: Rectangle {
        implicitWidth: root.rowHeight * (modelData.aspect_ratio || 1)
        implicitHeight: root.rowHeight
        radius: imageRadius
        color: Appearance.colors.colLayer2
    }

    contentItem: Item {
        anchors.fill: parent

        Image {
            id: imageObject
            anchors.fill: parent
            width: root.rowHeight * (modelData.aspect_ratio || 1)
            height: root.rowHeight
            fillMode: Image.PreserveAspectCrop
            source: modelData.preview_url ?? ""
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

        // Loading indicator
        Rectangle {
            anchors.fill: parent
            radius: imageRadius
            color: Appearance.colors.colLayer2
            visible: imageObject.status !== Image.Ready

            StyledText {
                anchors.centerIn: parent
                text: imageObject.status === Image.Loading ? "..." : ""
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

        // Context menu
        Loader {
            id: contextMenuLoader
            active: root.showActions
            anchors.top: menuButton.bottom
            anchors.right: parent.right
            anchors.margins: 4

            sourceComponent: Rectangle {
                id: contextMenu
                width: 160
                height: menuColumn.implicitHeight + 16
                radius: Appearance.rounding.small
                color: Appearance.m3colors.m3layerBackground2

                Column {
                    id: menuColumn
                    anchors.centerIn: parent
                    width: parent.width - 8
                    spacing: 2

                    RippleButton {
                        width: parent.width
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
                        visible: root.imageData.source && root.imageData.source.length > 0
                        width: parent.width
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
                        width: parent.width
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
