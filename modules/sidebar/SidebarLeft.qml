import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../common"
import "../common/widgets"
import "../../services"

/**
 * Left sidebar panel window containing the Booru browser.
 */
Scope {
    id: root
    property bool sidebarOpen: false

    // Auto-preload when sidebar opens with no results
    onSidebarOpenChanged: {
        if (sidebarOpen && Booru.responses.length === 0) {
            // Set defaults: wallhaven provider, safe mode, then search
            Booru.setProvider("wallhaven")
            Booru.allowNsfw = false
            Booru.makeRequest([], false, Booru.limit, 1)
        }
    }

    Loader {
        id: sidebarLoader
        active: true

        sourceComponent: PanelWindow {
            id: sidebarRoot
            visible: root.sidebarOpen

            property real sidebarWidth: 420

            function hide() {
                root.sidebarOpen = false
            }

            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            implicitWidth: sidebarWidth + 20
            WlrLayershell.namespace: "quickshell:sidebarLeft"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors {
                top: true
                left: true
                bottom: true
            }

            mask: Region {
                item: sidebarBackground
            }

            property bool pinned: false

            HyprlandFocusGrab {
                id: grab
                windows: [sidebarRoot]
                active: sidebarRoot.visible && !sidebarRoot.pinned
                onActiveChanged: {
                    if (active) {
                        sidebarBackground.forceActiveFocus()
                    }
                }
                onCleared: {
                    if (!sidebarRoot.pinned) sidebarRoot.hide()
                }
            }

            // Shadow
            Rectangle {
                anchors.fill: sidebarBackground
                anchors.margins: -4
                radius: sidebarBackground.radius + 4
                color: "transparent"
                border.width: 8
                border.color: Qt.rgba(0, 0, 0, 0.3)
                z: -1
            }

            // Main background
            Rectangle {
                id: sidebarBackground
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: 8
                anchors.leftMargin: 8
                width: sidebarRoot.sidebarWidth
                height: parent.height - 16
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.m3colors.m3borderSecondary
                radius: Appearance.rounding.large

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        sidebarRoot.hide();
                        event.accepted = true;
                    }
                }

                // Pin button
                RippleButton {
                    id: pinButton
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: sidebarRoot.pinned ? Appearance.colors.colLayer2Active : Qt.rgba(0, 0, 0, 0.2)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    z: 10

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 16
                        color: sidebarRoot.pinned ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3secondaryText
                        text: sidebarRoot.pinned ? "push_pin" : "push_pin"
                    }

                    onClicked: sidebarRoot.pinned = !sidebarRoot.pinned
                }

                // Content
                Anime {
                    anchors.fill: parent
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            root.sidebarOpen = !root.sidebarOpen
        }

        function close(): void {
            root.sidebarOpen = false
        }

        function open(): void {
            root.sidebarOpen = true
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles Booru sidebar"

        onPressed: {
            root.sidebarOpen = !root.sidebarOpen
        }
    }
}
