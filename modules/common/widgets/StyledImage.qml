import QtQuick
import ".."

/**
 * Async image with loading fade-in and optional fallback.
 */
Image {
    id: root
    property string fallbackSource: ""

    asynchronous: true
    cache: true
    fillMode: Image.PreserveAspectCrop

    opacity: status === Image.Ready ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutQuad
        }
    }

    onStatusChanged: {
        if (status === Image.Error && fallbackSource.length > 0) {
            source = fallbackSource
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer2
        visible: root.status !== Image.Ready
        radius: parent.radius ?? 0

        Text {
            anchors.centerIn: parent
            text: root.status === Image.Loading ? "..." : ""
            color: Appearance.m3colors.m3secondaryText
            font.pixelSize: 14
        }
    }
}
