import QtQuick
import ".."

/**
 * ListView with custom scroll behavior.
 */
ListView {
    id: root
    property real touchpadScrollFactor: 1.0
    property real mouseScrollFactor: 1.0

    clip: true
    boundsBehavior: Flickable.DragAndOvershootBounds

    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
    }
}
