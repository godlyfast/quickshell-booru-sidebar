import QtQuick
import "../../common"
import "../../common/widgets"

/**
 * Download status badges (downloaded, wallpaper) for BooruImage.
 * Shows in bottom-right corner of image card.
 */
Row {
    id: root

    required property bool isSavedLocally
    required property bool isSavedAsWallpaper

    spacing: 4

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
