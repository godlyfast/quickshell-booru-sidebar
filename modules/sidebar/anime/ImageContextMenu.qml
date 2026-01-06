import QtQuick
import QtQuick.Controls
import Quickshell
import "../../common"
import "../../common/widgets"
import "../../common/functions/shell_utils.js" as ShellUtils
import "../../../services" as Services

/**
 * Context menu popup for BooruImage actions.
 * Extracted to reduce BooruImage.qml complexity.
 */
Popup {
    id: root

    // Required properties
    required property var imageData
    required property string fileName
    required property string provider
    required property bool isVideo
    required property bool useGrabber
    required property string downloadPath
    required property string nsfwPath
    required property var grabberDownloader
    required property var wallpaperDownloader

    // Anchor reference
    required property Item menuButton

    // Signals
    signal downloadStarted()
    signal wallpaperStarted()
    signal menuClosed()

    y: menuButton.y + menuButton.height + 4
    x: Math.max(4, Math.min(parent.width - 164, menuButton.x + menuButton.width - 160))
    width: 160
    height: menuColumn.implicitHeight + 16
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onClosed: root.menuClosed()

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
                Services.Logger.info("ImageContextMenu", `Open file link: id=${root.imageData.id}`)
                root.close()
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
                root.close()
                if (root.isVideo) {
                    Services.Logger.info("ImageContextMenu", `Play in mpv: id=${root.imageData.id}`)
                    Quickshell.execDetached(["mpv", "--loop", "--user-agent=Mozilla/5.0 BooruSidebar/1.0", root.imageData.file_url])
                } else {
                    Services.Logger.info("ImageContextMenu", `Open in viewer: id=${root.imageData.id}`)
                    const tmpFile = "/tmp/booru_" + root.fileName
                    const escapedUrl = ShellUtils.shellEscape(root.imageData.file_url)
                    const escapedTmp = ShellUtils.shellEscape(tmpFile)
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
                Services.Logger.info("ImageContextMenu", `Go to source: id=${root.imageData.id} source=${root.imageData.source.substring(0, 50)}`)
                root.close()
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
                Services.Logger.info("ImageContextMenu", `Download: id=${root.imageData.id} useGrabber=${root.useGrabber}`)
                root.close()
                root.downloadStarted()
                const targetPath = root.imageData.is_nsfw ? root.nsfwPath : root.downloadPath
                if (root.useGrabber) {
                    root.grabberDownloader.outputPath = targetPath
                    root.grabberDownloader.startDownload()
                } else {
                    const escapedPath = ShellUtils.shellEscape(targetPath)
                    const escapedUrl = ShellUtils.shellEscape(root.imageData.file_url)
                    const escapedFile = ShellUtils.shellEscape(root.fileName)
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
                Services.Logger.info("ImageContextMenu", `Save as wallpaper: id=${root.imageData.id}`)
                root.close()
                root.wallpaperStarted()
                const wallpaperPath = root.downloadPath.replace(/\/booru$/, '/wallpapers')
                if (root.useGrabber) {
                    root.wallpaperDownloader.outputPath = wallpaperPath
                    root.wallpaperDownloader.startDownload()
                } else {
                    const escapedWpPath = ShellUtils.shellEscape(wallpaperPath)
                    const escapedUrl = ShellUtils.shellEscape(root.imageData.file_url)
                    const escapedFile = ShellUtils.shellEscape(root.fileName)
                    Quickshell.execDetached(["bash", "-c",
                        "mkdir -p '" + escapedWpPath + "' && curl -sL -A 'Mozilla/5.0 BooruSidebar/1.0' '" + escapedUrl + "' -o '" + escapedWpPath + "/" + escapedFile + "' && notify-send 'Wallpaper saved' '" + escapedWpPath + "/" + escapedFile + "' -a 'Booru'"
                    ])
                }
            }
        }
    }
}
