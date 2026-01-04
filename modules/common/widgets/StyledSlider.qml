import QtQuick
import QtQuick.Controls
import ".."

/**
 * Material-style slider for seek bars, volume controls, etc.
 */
Slider {
    id: root

    property color trackColor: Appearance.colors.colLayer2
    property color progressColor: Appearance.m3colors.m3accentPrimary
    property color handleColor: Appearance.m3colors.m3accentPrimary
    property bool showHandle: true

    background: Rectangle {
        x: root.leftPadding
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: root.availableWidth
        height: 4
        radius: 2
        color: root.trackColor

        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            radius: 2
            color: root.progressColor
        }
    }

    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * root.availableWidth - width / 2
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: root.showHandle ? 12 : 0
        height: root.showHandle ? 12 : 0
        radius: 6
        color: root.handleColor
        visible: root.showHandle

        scale: root.pressed ? 1.3 : (root.hovered ? 1.1 : 1.0)
        Behavior on scale { NumberAnimation { duration: 100 } }
    }
}
