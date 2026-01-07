import ".."
import "./"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ToolTip {
    id: root
    property string content
    property bool extraVisibleCondition: true
    property bool alternativeVisibleCondition: false
    property bool internalVisibleCondition: {
        // Don't show tooltip if content is empty
        if (!content || content.length === 0) return false
        const ans = (extraVisibleCondition && (parent.hovered === undefined || parent?.hovered)) || alternativeVisibleCondition
        return ans
    }
    verticalPadding: 5
    horizontalPadding: 10
    opacity: internalVisibleCondition ? 1 : 0
    visible: opacity > 0

    // Track dynamically created animations for cleanup
    property var _animations: []

    function _createAnimation(parent) {
        const anim = Appearance?.animation.elementMoveFast.numberAnimation.createObject(parent)
        if (anim) _animations.push(anim)
        return anim
    }

    Component.onDestruction: {
        // Clean up dynamically created animation objects
        for (const anim of _animations) {
            if (anim) anim.destroy()
        }
    }

    Behavior on opacity {
        animation: root._createAnimation(this)
    }

    background: null

    contentItem: Item {
        id: contentItemBackground
        implicitWidth: tooltipTextObject.width + 2 * root.horizontalPadding
        implicitHeight: tooltipTextObject.height + 2 * root.verticalPadding

        Rectangle {
            id: backgroundRectangle
            anchors.bottom: contentItemBackground.bottom
            anchors.horizontalCenter: contentItemBackground.horizontalCenter
            color: Appearance?.m3colors.colTooltip ?? "#3C4043"
            radius: Appearance?.rounding.verysmall ?? 7
            width: internalVisibleCondition ? (tooltipTextObject.width + 2 * padding) : 0
            height: internalVisibleCondition ? (tooltipTextObject.height + 2 * padding) : 0
            clip: true

            Behavior on width {
                animation: root._createAnimation(this)
            }
            Behavior on height {
                animation: root._createAnimation(this)
            }

            StyledText {
                id: tooltipTextObject
                anchors.centerIn: parent
                text: content
                font.pixelSize: Appearance?.font.pixelSize.textSmall ?? 14
                font.hintingPreference: Font.PreferNoHinting // Prevent shaky text
                color: Appearance?.m3colors.colOnTooltip ?? "#FFFFFF"
                wrapMode: Text.Wrap
            }
        }   
    }
}