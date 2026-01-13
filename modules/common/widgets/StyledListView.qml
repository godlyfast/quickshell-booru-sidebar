import QtQuick
import ".."

/**
 * ListView with custom scroll behavior.
 */
ListView {
    id: root

    clip: true
    boundsBehavior: Flickable.DragAndOvershootBounds

    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
    }
}
