import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../common"
import "../common/widgets"
import "../../services" as Services
import "../common/functions/levendist.js" as Fuzzy

/**
 * Neovim-style provider picker
 * /: search, j/k: nav, Enter: select, Esc: close, gg/G: top/bottom
 */
Rectangle {
    id: root
    color: Qt.rgba(0, 0, 0, 0.85)
    focus: visible

    property bool active: false
    property int selectedIndex: 0
    property string searchQuery: ""
    property bool searchMode: false
    property bool waitingForG: false  // For gg command

    signal closed()
    signal providerSelected(string providerKey)

    // Filtered provider list
    property var filteredProviders: {
        var providers = []
        var list = Services.Booru.providerList || []

        for (var i = 0; i < list.length; i++) {
            var key = list[i]
            var info = Services.Booru.providers[key]
            var name = info ? info.name : key

            if (searchQuery.length === 0) {
                providers.push({ key: key, name: name, score: 0 })
            } else {
                var score = Fuzzy.computeTextMatchScore(searchQuery.toLowerCase(), name.toLowerCase())
                if (score > 0.3) {
                    providers.push({ key: key, name: name, score: score })
                }
            }
        }

        if (searchQuery.length > 0) {
            providers.sort(function(a, b) { return b.score - a.score })
        }

        return providers
    }

    onFilteredProvidersChanged: {
        selectedIndex = 0
    }

    // Neovim-style keyboard handling
    Keys.onPressed: function(event) {
        event.accepted = true

        // Search mode: typing adds to query
        if (searchMode) {
            if (event.key === Qt.Key_Escape) {
                searchMode = false
                return
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                searchMode = false
                return
            }
            if (event.key === Qt.Key_Backspace) {
                if (searchQuery.length > 0) {
                    searchQuery = searchQuery.slice(0, -1)
                }
                return
            }
            if (event.text && event.text.length === 1) {
                searchQuery += event.text
                return
            }
            return
        }

        // Normal mode
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
            if (searchQuery.length > 0) {
                searchQuery = ""  // First Esc/q clears search
            } else {
                root.closed()
            }
            return
        }

        // / to enter search mode
        if (event.key === Qt.Key_Slash) {
            searchMode = true
            return
        }

        // Enter to select
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (filteredProviders.length > 0 && selectedIndex < filteredProviders.length) {
                Services.Logger.info("PickerDialog", `Selected provider: ${filteredProviders[selectedIndex].key}`)
                root.providerSelected(filteredProviders[selectedIndex].key)
                root.closed()
            }
            return
        }

        // j/Down: move down
        if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
            waitingForG = false
            if (selectedIndex < filteredProviders.length - 1) {
                selectedIndex++
                listView.positionViewAtIndex(selectedIndex, ListView.Contain)
            }
            return
        }

        // k/Up: move up
        if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
            waitingForG = false
            if (selectedIndex > 0) {
                selectedIndex--
                listView.positionViewAtIndex(selectedIndex, ListView.Contain)
            }
            return
        }

        // G: go to bottom (or gg: go to top)
        if (event.key === Qt.Key_G) {
            if (event.modifiers & Qt.ShiftModifier) {
                // Shift+G: go to bottom
                selectedIndex = filteredProviders.length - 1
                listView.positionViewAtIndex(selectedIndex, ListView.Contain)
                waitingForG = false
            } else if (waitingForG) {
                // gg: go to top
                selectedIndex = 0
                listView.positionViewAtIndex(selectedIndex, ListView.Contain)
                waitingForG = false
            } else {
                waitingForG = true
            }
            return
        }

        // Ctrl+D: half page down
        if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
            waitingForG = false
            var jump = Math.floor(listView.height / 84)  // ~2 items
            selectedIndex = Math.min(selectedIndex + jump, filteredProviders.length - 1)
            listView.positionViewAtIndex(selectedIndex, ListView.Contain)
            return
        }

        // Ctrl+U: half page up
        if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
            waitingForG = false
            var jumpUp = Math.floor(listView.height / 84)
            selectedIndex = Math.max(selectedIndex - jumpUp, 0)
            listView.positionViewAtIndex(selectedIndex, ListView.Contain)
            return
        }

        // Shift+1-9: Assign selected provider to favorite slot
        // Shift+number produces symbols: !@#$%^&*( = keys 33,64,35,36,37,94,38,42,40
        var shiftNumMap = {}
        shiftNumMap[Qt.Key_Exclam] = 0      // !
        shiftNumMap[Qt.Key_At] = 1          // @
        shiftNumMap[Qt.Key_NumberSign] = 2  // #
        shiftNumMap[Qt.Key_Dollar] = 3      // $
        shiftNumMap[Qt.Key_Percent] = 4     // %
        shiftNumMap[Qt.Key_AsciiCircum] = 5 // ^
        shiftNumMap[Qt.Key_Ampersand] = 6   // &
        shiftNumMap[Qt.Key_Asterisk] = 7    // *
        shiftNumMap[Qt.Key_ParenLeft] = 8   // (

        if (shiftNumMap[event.key] !== undefined) {
            waitingForG = false
            var slot = shiftNumMap[event.key]
            if (filteredProviders.length > 0 && selectedIndex < filteredProviders.length) {
                var providerKey = filteredProviders[selectedIndex].key
                var favorites = ConfigOptions.booru && ConfigOptions.booru.favorites
                    ? ConfigOptions.booru.favorites.slice()  // Copy array
                    : Services.Booru.providerList.slice(0, 9)

                // Remove provider from current position if exists
                var existingIdx = favorites.indexOf(providerKey)
                if (existingIdx !== -1) {
                    favorites.splice(existingIdx, 1)
                }

                // Ensure array is long enough
                while (favorites.length <= slot) {
                    favorites.push("")
                }

                // Insert at new position
                favorites.splice(slot, 0, providerKey)

                // Keep only first 9
                favorites = favorites.filter(function(f) { return f !== "" }).slice(0, 9)

                // Save to config and persist
                ConfigOptions.booru.favorites = favorites
                Services.ConfigLoader.saveConfig()
                Services.Logger.info("PickerDialog", `Assigned ${providerKey} to slot ${slot + 1}`)
            }
            return
        }

        // 1-9: Quick select from favorites
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            waitingForG = false
            var idx = event.key - Qt.Key_1
            var favs = ConfigOptions.booru && ConfigOptions.booru.favorites
                ? ConfigOptions.booru.favorites
                : Services.Booru.providerList.slice(0, 9)
            if (idx < favs.length && Services.Booru.providerList.indexOf(favs[idx]) !== -1) {
                Services.Logger.info("PickerDialog", `Quick select: ${favs[idx]} (slot ${idx + 1})`)
                root.providerSelected(favs[idx])
                root.closed()
            }
            return
        }

        // Reset g waiting on other keys
        waitingForG = false
    }

    // Click outside to close
    MouseArea {
        anchors.fill: parent
        onClicked: root.closed()
    }

    // Main dialog
    Rectangle {
        anchors.centerIn: parent
        width: 340
        height: Math.min(500, 80 + filteredProviders.length * 44)
        color: Appearance.colors && Appearance.colors.colLayer1 ? Appearance.colors.colLayer1 : "#1e1e2e"
        radius: 12
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.1)

        MouseArea {
            anchors.fill: parent
        }

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Search bar (vim command line style)
            Rectangle {
                width: parent.width
                height: 32
                radius: 6
                color: searchMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                border.width: searchMode ? 1 : 0
                border.color: "#89b4fa"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: searchMode ? "/" : (searchQuery.length > 0 ? "/" : "")
                        color: "#89b4fa"
                        font.pixelSize: 14
                        font.family: "JetBrainsMono Nerd Font Mono"
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 30
                        text: searchQuery.length > 0 ? searchQuery : (searchMode ? "" : "/ to search")
                        color: searchQuery.length > 0 || searchMode ? "#ffffff" : "#666666"
                        font.pixelSize: 14
                        font.family: "JetBrainsMono Nerd Font Mono"
                        elide: Text.ElideRight
                    }

                    // Cursor blink in search mode
                    Rectangle {
                        visible: searchMode
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2
                        height: 16
                        color: "#89b4fa"

                        SequentialAnimation on opacity {
                            running: searchMode
                            loops: Animation.Infinite
                            NumberAnimation { to: 0; duration: 500 }
                            NumberAnimation { to: 1; duration: 500 }
                        }
                    }
                }
            }

            // Provider list
            ListView {
                id: listView
                width: parent.width
                height: parent.height - 40
                clip: true
                model: filteredProviders
                spacing: 2

                delegate: Rectangle {
                    width: listView.width
                    height: 40
                    radius: 6
                    color: {
                        if (index === root.selectedIndex) {
                            return Appearance.m3colors && Appearance.m3colors.m3primaryContainer
                                ? Appearance.m3colors.m3primaryContainer
                                : "#45475a"
                        }
                        return "transparent"
                    }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        // Number badge (1-9 for favorites)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            property var favorites: ConfigOptions.booru && ConfigOptions.booru.favorites
                                ? ConfigOptions.booru.favorites
                                : Services.Booru.providerList.slice(0, 9)
                            property int favIndex: favorites.indexOf(modelData.key)
                            text: favIndex >= 0 && favIndex < 9 ? (favIndex + 1).toString() : " "
                            color: index === root.selectedIndex ? "#000000" : "#f9e2af"
                            font.pixelSize: 12
                            font.family: "JetBrainsMono Nerd Font Mono"
                            font.bold: favIndex >= 0
                            width: 14
                        }

                        // Selection indicator
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: index === root.selectedIndex ? ">" : " "
                            color: "#89b4fa"
                            font.pixelSize: 14
                            font.family: "JetBrainsMono Nerd Font Mono"
                            font.bold: true
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 80
                            text: modelData.name
                            color: index === root.selectedIndex ? "#000000" : "#cdd6f4"
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }

                        // Current provider checkmark
                        Text {
                            visible: modelData.key === Services.Booru.currentProvider
                            anchors.verticalCenter: parent.verticalCenter
                            text: "✓"
                            color: index === root.selectedIndex ? "#000000" : "#a6e3a1"
                            font.pixelSize: 14
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            Services.Logger.info("PickerDialog", `Clicked provider: ${modelData.key}`)
                            root.providerSelected(modelData.key)
                            root.closed()
                        }
                        onEntered: root.selectedIndex = index
                    }
                }
            }
        }
    }

    // Vim-style hint
    Text {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 8
        text: searchMode ? "Enter: confirm  Esc: cancel" : "j/k:nav  1-9:select  !@#:assign  /:search  q:close"
        color: "#585b70"
        font.pixelSize: 11
        font.family: "JetBrainsMono Nerd Font Mono"
    }

    Component.onCompleted: {
        Services.Logger.debug("PickerDialog", "Loaded!")
        searchQuery = ""
        selectedIndex = 0
        searchMode = false
        forceActiveFocus()
    }

    onVisibleChanged: {
        if (visible) {
            searchQuery = ""
            selectedIndex = 0
            searchMode = false
            waitingForG = false
            forceActiveFocus()
        }
    }
}
