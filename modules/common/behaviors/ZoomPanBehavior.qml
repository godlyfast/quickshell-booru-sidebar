import QtQuick
import "../widgets"
import ".."

/**
 * Reusable zoom and pan behavior for images and GIFs.
 *
 * Usage:
 *   Image {
 *       id: myImage
 *       transform: zoomBehavior.transform
 *   }
 *   ZoomPanBehavior {
 *       id: zoomBehavior
 *       target: myImage
 *       zoomLevel: root.zoomLevel  // Bind to external state
 *       onZoomLevelChanged: root.zoomLevel = zoomLevel
 *       // ...same for panX, panY
 *   }
 */
Item {
    id: root

    // Required: the item to apply zoom/pan to
    property Item target: null

    // Zoom/pan state (bidirectional - can be externally bound)
    property real zoomLevel: 1.0
    property real panX: 0
    property real panY: 0

    // Configuration
    property real minZoom: 1.0
    property real maxZoom: 10.0
    property real zoomFactor: 1.15  // Multiplier per wheel tick

    // Transform list to apply to target
    // Usage: target.transform: zoomBehavior.targetTransform
    readonly property list<QtObject> targetTransform: [
        Scale {
            xScale: root.zoomLevel
            yScale: root.zoomLevel
            origin.x: root.target ? root.target.width / 2 : 0
            origin.y: root.target ? root.target.height / 2 : 0
        },
        Translate {
            x: root.panX
            y: root.panY
        }
    ]

    // Fill parent to capture all mouse events
    anchors.fill: parent

    // Drag handling
    MouseArea {
        id: dragArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton

        property real startX: 0
        property real startY: 0
        property real startPanX: 0
        property real startPanY: 0

        cursorShape: root.zoomLevel > 1.0 ? Qt.OpenHandCursor : Qt.ArrowCursor

        onPressed: function(mouse) {
            startX = mouse.x
            startY = mouse.y
            startPanX = root.panX
            startPanY = root.panY
            if (root.zoomLevel > 1.0) cursorShape = Qt.ClosedHandCursor
        }

        onReleased: {
            if (root.zoomLevel > 1.0) cursorShape = Qt.OpenHandCursor
        }

        onPositionChanged: function(mouse) {
            if (pressed && root.zoomLevel > 1.0) {
                root.panX = startPanX + (mouse.x - startX)
                root.panY = startPanY + (mouse.y - startY)
            }
        }

        onWheel: function(wheel) {
            var zoomDelta = wheel.angleDelta.y > 0 ? root.zoomFactor : (1 / root.zoomFactor)
            var newZoom = Math.max(root.minZoom, Math.min(root.maxZoom, root.zoomLevel * zoomDelta))
            root.zoomLevel = newZoom
            // Reset pan when zooming back to 1.0
            if (newZoom <= 1.0) {
                root.panX = 0
                root.panY = 0
            }
            zoomIndicator.show()
        }

        onDoubleClicked: {
            root.zoomLevel = 1.0
            root.panX = 0
            root.panY = 0
            zoomIndicator.show()
        }
    }

    // Zoom percentage indicator
    Rectangle {
        id: zoomIndicator
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 16
        width: zoomText.implicitWidth + 16
        height: zoomText.implicitHeight + 8
        radius: Appearance.rounding.small
        color: Qt.rgba(0, 0, 0, 0.6)
        opacity: 0
        visible: opacity > 0
        z: 10  // Above content

        function show() {
            opacity = 1
            hideTimer.restart()
        }

        Timer {
            id: hideTimer
            interval: 1000
            onTriggered: zoomIndicator.opacity = 0
        }

        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }

        StyledText {
            id: zoomText
            anchors.centerIn: parent
            text: Math.round(root.zoomLevel * 100) + "%"
            font.pixelSize: Appearance.font.pixelSize.textSmall
            color: "#ffffff"
        }
    }
}
