import "../"
import QtQuick

Text {
    id: root
    property real iconSize: Appearance?.font.pixelSize.textBase ?? 16
    property real fill: 0

    // Map icon names to unicode codepoints (Qt doesn't process rlig for variable fonts)
    readonly property var iconMap: ({
        "arrow_upward": "\ue5d8",
        "bookmark_heart": "\uf455",
        "chevron_left": "\ue5cb",
        "chevron_right": "\ue5cc",
        "more_vert": "\ue5d4",
        "play_arrow": "\ue037",
        "push_pin": "\uf10d",
        "search": "\ue8b6",
        "close": "\ue5cd",
        "menu": "\ue5d2",
        "settings": "\ue8b8",
        "download": "\uf090",
        "open_in_new": "\ue89e",
        "refresh": "\ue5d5",
        "check": "\ue5ca",
        "expand_more": "\ue5cf",
        "expand_less": "\ue5ce",
        "arrow_back": "\ue5c4",
        "arrow_forward": "\ue5c8",
        "favorite": "\ue87d",
        "star": "\ue838",
        "home": "\ue88a",
        "delete": "\ue872",
        "edit": "\ue3c9",
        "add": "\ue145",
        "remove": "\ue15b",
        "visibility": "\ue8f4",
        "visibility_off": "\ue8f5",
        "content_copy": "\ue14d",
        "share": "\ue80d",
        "info": "\ue88e",
        "warning": "\ue002",
        "error": "\ue000",
        "help": "\ue887",
        "keyboard_arrow_down": "\ue313",
        "keyboard_arrow_up": "\ue316",
        "keyboard_arrow_left": "\ue314",
        "keyboard_arrow_right": "\ue315",
        "image": "\ue3f4",
        "photo": "\ue410",
        "filter": "\ue3d3",
        "sort": "\ue164",
        "fullscreen": "\ue5d0",
        "fullscreen_exit": "\ue5d1"
    })

    function resolveIcon(name) {
        return iconMap[name] !== undefined ? iconMap[name] : name
    }

    onTextChanged: {
        if (iconMap[text] !== undefined) {
            text = iconMap[text]
        }
    }

    renderType: Text.NativeRendering
    font.hintingPreference: Font.PreferFullHinting
    verticalAlignment: Text.AlignVCenter
    font.family: "Material Symbols Rounded"
    font.pixelSize: iconSize
    color: Appearance.m3colors.m3primaryText

    Behavior on fill {
        NumberAnimation {
            duration: Appearance?.animation.elementMoveFast.duration ?? 200
            easing.type: Appearance?.animation.elementMoveFast.type ?? Easing.BezierSpline
            easing.bezierCurve: Appearance?.animation.elementMoveFast.bezierCurve ?? [0.34, 0.80, 0.34, 1.00, 1, 1]
        }
    }

    font.variableAxes: {
        "FILL": fill,
        "opsz": iconSize,
    }
}
