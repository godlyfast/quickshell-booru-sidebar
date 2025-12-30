import QtQuick
import QtQuick.Controls
import ".."

/**
 * Material-style toggle switch.
 */
Switch {
    id: root

    indicator: Rectangle {
        implicitWidth: 40
        implicitHeight: 20
        x: root.leftPadding
        y: parent.height / 2 - height / 2
        radius: height / 2
        color: root.checked ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
        border.color: root.checked ? Appearance.colors.colPrimary : Appearance.m3colors.m3borderSecondary

        Behavior on color {
            ColorAnimation { duration: 150 }
        }

        Rectangle {
            x: root.checked ? parent.width - width - 2 : 2
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            radius: 8
            color: root.checked ? "#ffffff" : Appearance.m3colors.m3secondaryText

            Behavior on x {
                NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
            }
        }
    }
}
