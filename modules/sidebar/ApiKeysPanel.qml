import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../common"
import "../common/widgets"
import "../../services" as Services

/**
 * Overlay panel for managing API keys (Gelbooru, Rule34, Wallhaven, Danbooru).
 * Follows the PickerDialog overlay pattern: dark background, centered card, Esc to close.
 */
Rectangle {
    id: root
    color: Qt.rgba(0, 0, 0, 0.85)
    focus: visible

    signal closed()

    // Debounce timer for saving config after edits
    Timer {
        id: saveDebounce
        interval: 500
        onTriggered: Services.ConfigLoader.saveConfig()
    }

    function scheduleSave() {
        saveDebounce.restart()
    }

    // Close on Escape (other keys pass through to TextInput children)
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            event.accepted = true
            root.closed()
        }
    }

    // Click outside card to close
    MouseArea {
        anchors.fill: parent
        onClicked: root.closed()
    }

    // --- Inline Components ---

    component StatusDot: Rectangle {
        property string status: "empty"  // "empty", "partial", "complete"
        width: 8
        height: 8
        radius: 4
        color: status === "complete" ? "#a6e3a1"
             : status === "partial"  ? "#f9e2af"
             : "#585b70"
    }

    component ApiKeyField: ColumnLayout {
        id: apiKeyFieldRoot
        property string label: ""
        property string value: ""
        property string placeholder: ""
        property var editCallback: null  // function(newValue)
        spacing: 4

        StyledText {
            font.pixelSize: 11
            color: Appearance.m3colors?.m3secondaryText ?? "#585b70"
            text: apiKeyFieldRoot.label
        }

        Rectangle {
            Layout.fillWidth: true
            height: 32
            radius: 6
            color: fieldInput.activeFocus ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
            border.width: fieldInput.activeFocus ? 1 : 0
            border.color: Appearance.m3colors?.m3primary ?? "#89b4fa"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                spacing: 4

                TextInput {
                    id: fieldInput
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: apiKeyFieldRoot.value
                    color: "#cdd6f4"
                    selectionColor: Appearance.m3colors?.m3primary ?? "#89b4fa"
                    selectedTextColor: "#000000"
                    font.pixelSize: 13
                    font.family: "JetBrainsMono Nerd Font Mono"
                    echoMode: fieldInput.activeFocus || showToggle.revealed
                        ? TextInput.Normal : TextInput.Password
                    clip: true

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: !fieldInput.text && !fieldInput.activeFocus
                        text: apiKeyFieldRoot.placeholder
                        color: "#585b70"
                        font: fieldInput.font
                    }

                    onTextEdited: {
                        if (apiKeyFieldRoot.editCallback)
                            apiKeyFieldRoot.editCallback(text)
                    }
                }

                // Eye toggle button
                RippleButton {
                    id: showToggle
                    property bool revealed: false
                    implicitWidth: 24
                    implicitHeight: 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Qt.rgba(1, 1, 1, 0.1)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 14
                        color: "#585b70"
                        text: showToggle.revealed ? "visibility" : "visibility_off"
                    }

                    onClicked: revealed = !revealed
                }
            }
        }
    }

    component ProviderKeySection: ColumnLayout {
        id: providerSectionRoot
        property string providerName: ""
        property string status: "empty"
        property string hintUrl: ""
        property string hintText: ""
        spacing: 8

        RowLayout {
            spacing: 8

            StatusDot {
                Layout.alignment: Qt.AlignVCenter
                status: providerSectionRoot.status
            }

            StyledText {
                font.pixelSize: 14
                font.bold: true
                color: "#cdd6f4"
                text: providerSectionRoot.providerName
            }

            Item { Layout.fillWidth: true }

            // Clickable URL hint
            StyledText {
                visible: providerSectionRoot.hintUrl.length > 0
                font.pixelSize: 10
                color: Appearance.m3colors?.m3primary ?? "#89b4fa"
                text: providerSectionRoot.hintText
                opacity: hintMouse.containsMouse ? 1.0 : 0.7

                MouseArea {
                    id: hintMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.openUrlExternally(providerSectionRoot.hintUrl)
                }
            }
        }
    }

    // --- Main Dialog Card ---

    Rectangle {
        anchors.centerIn: parent
        width: 380
        // 90 = header(28) + separator(1) + spacing(24) + margins(32) + padding
        height: Math.min(parent.height - 48, sectionsColumn.implicitHeight + 90)
        color: Appearance.colors.colLayer1 ?? "#1e1e2e"
        radius: 12
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.1)

        // Prevent click-through to close handler
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // Header
            RowLayout {
                Layout.fillWidth: true

                MaterialSymbol {
                    iconSize: 20
                    color: Appearance.m3colors?.m3primary ?? "#89b4fa"
                    text: "vpn_key"
                }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.textLarge
                    font.bold: true
                    color: "#ffffff"
                    text: "API Keys"
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Qt.rgba(1, 1, 1, 0.1)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 16
                        color: Appearance.m3colors?.m3secondaryText ?? "#585b70"
                        text: "close"
                    }

                    onClicked: root.closed()
                }
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(1, 1, 1, 0.08)
            }

            // Scrollable content
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: sectionsColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: sectionsColumn
                    width: parent.width
                    spacing: 20

                    // === Gelbooru ===
                    ProviderKeySection {
                        Layout.fillWidth: true
                        providerName: "Gelbooru"
                        hintUrl: "https://gelbooru.com/index.php?page=account&s=options"
                        hintText: "gelbooru.com \u2192 options"
                        status: {
                            const k = ConfigOptions.booru.gelbooruApiKey
                            const u = ConfigOptions.booru.gelbooruUserId
                            if (k && u) return "complete"
                            if (k || u) return "partial"
                            return "empty"
                        }
                    }

                    ApiKeyField {
                        Layout.fillWidth: true
                        label: "API Key"
                        value: ConfigOptions.booru.gelbooruApiKey
                        placeholder: "paste api_key here"
                        editCallback: (v) => { ConfigOptions.booru.gelbooruApiKey = v; root.scheduleSave() }
                    }

                    ApiKeyField {
                        Layout.fillWidth: true
                        label: "User ID"
                        value: ConfigOptions.booru.gelbooruUserId
                        placeholder: "paste user_id here"
                        editCallback: (v) => { ConfigOptions.booru.gelbooruUserId = v; root.scheduleSave() }
                    }

                    // Spacer between sections
                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.05) }

                    // === Rule34 ===
                    ProviderKeySection {
                        Layout.fillWidth: true
                        providerName: "Rule34"
                        hintUrl: "https://rule34.xxx/index.php?page=account&s=options"
                        hintText: "rule34.xxx \u2192 options"
                        status: {
                            const k = ConfigOptions.booru.rule34ApiKey
                            const u = ConfigOptions.booru.rule34UserId
                            if (k && u) return "complete"
                            if (k || u) return "partial"
                            return "empty"
                        }
                    }

                    ApiKeyField {
                        Layout.fillWidth: true
                        label: "API Key"
                        value: ConfigOptions.booru.rule34ApiKey
                        placeholder: "paste api_key here"
                        editCallback: (v) => { ConfigOptions.booru.rule34ApiKey = v; root.scheduleSave() }
                    }

                    ApiKeyField {
                        Layout.fillWidth: true
                        label: "User ID"
                        value: ConfigOptions.booru.rule34UserId
                        placeholder: "paste user_id here"
                        editCallback: (v) => { ConfigOptions.booru.rule34UserId = v; root.scheduleSave() }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.05) }

                    // === Wallhaven ===
                    ProviderKeySection {
                        Layout.fillWidth: true
                        providerName: "Wallhaven"
                        hintUrl: "https://wallhaven.cc/settings/account"
                        hintText: "wallhaven.cc \u2192 settings"
                        status: ConfigOptions.booru.wallhavenApiKey ? "complete" : "empty"
                    }

                    ApiKeyField {
                        Layout.fillWidth: true
                        label: "API Key"
                        value: ConfigOptions.booru.wallhavenApiKey
                        placeholder: "paste apikey here"
                        editCallback: (v) => { ConfigOptions.booru.wallhavenApiKey = v; root.scheduleSave() }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.05) }

                    // === Danbooru ===
                    ProviderKeySection {
                        Layout.fillWidth: true
                        providerName: "Danbooru"
                        hintUrl: "https://danbooru.donmai.us/profile"
                        hintText: "danbooru.donmai.us \u2192 profile"
                        status: {
                            const l = ConfigOptions.booru.danbooruLogin
                            const k = ConfigOptions.booru.danbooruApiKey
                            if (l && k) return "complete"
                            if (l || k) return "partial"
                            return "empty"
                        }
                    }

                    ApiKeyField {
                        Layout.fillWidth: true
                        label: "Login"
                        value: ConfigOptions.booru.danbooruLogin
                        placeholder: "your username"
                        editCallback: (v) => { ConfigOptions.booru.danbooruLogin = v; root.scheduleSave() }
                    }

                    ApiKeyField {
                        Layout.fillWidth: true
                        label: "API Key"
                        value: ConfigOptions.booru.danbooruApiKey
                        placeholder: "paste api_key here"
                        editCallback: (v) => { ConfigOptions.booru.danbooruApiKey = v; root.scheduleSave() }
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
        text: "Esc: close  \u2022  Keys auto-save after 500ms"
        color: "#585b70"
        font.pixelSize: 11
        font.family: "JetBrainsMono Nerd Font Mono"
    }

    onVisibleChanged: {
        if (visible) {
            forceActiveFocus()
        }
    }
}
