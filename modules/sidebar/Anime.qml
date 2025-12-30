import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../common"
import "../common/widgets"
import "../common/functions/file_utils.js" as FileUtils
import "./anime"
import "../../services"

/**
 * Main Booru browser interface with search, tag suggestions, and image grid.
 */
Item {
    id: root
    property real padding: 8

    property var inputField: null
    readonly property var responses: Booru.responses
    property string previewDownloadPath: Directories.cacheDir + "/booru/previews"
    // homeDir has file:// prefix, must trim for shell commands
    property string downloadPath: FileUtils.trimFileProtocol(Directories.homeDir) + "/Pictures/booru"
    property string nsfwPath: FileUtils.trimFileProtocol(Directories.homeDir) + "/Pictures/booru/nsfw"
    property string commandPrefix: "/"
    property int tagSuggestionDelay: 250
    property var suggestionList: []

    Connections {
        target: Booru
        function onTagSuggestion(query, suggestions) {
            root.suggestionList = suggestions;
        }
    }

    property var allCommands: [
        { name: "mode", description: "Set the API provider" },
        { name: "clear", description: "Clear image list" },
        { name: "next", description: "Get next page" },
        { name: "safe", description: "Disable NSFW" },
        { name: "lewd", description: "Allow NSFW" }
    ]

    function handleInput(inputText) {
        if (inputText.startsWith(root.commandPrefix)) {
            const command = inputText.split(" ")[0].substring(1);
            const args = inputText.split(" ").slice(1);

            if (command === "mode" && args.length > 0) {
                Booru.setProvider(args[0]);
            } else if (command === "clear") {
                Booru.clearResponses();
            } else if (command === "next") {
                if (root.responses.length > 0) {
                    const lastResponse = root.responses[root.responses.length - 1];
                    root.handleInput(`${lastResponse.tags.join(" ")} ${parseInt(lastResponse.page) + 1}`);
                }
            } else if (command === "safe") {
                Booru.allowNsfw = false;
                Booru.addSystemMessage("NSFW content disabled");
            } else if (command === "lewd") {
                Booru.allowNsfw = true;
                Booru.addSystemMessage("NSFW content enabled");
            } else {
                Booru.addSystemMessage("Unknown command: " + command);
            }
        } else if (inputText.trim() === "+") {
            root.handleInput(`${root.commandPrefix}next`);
        } else {
            const tagList = inputText.split(/\s+/).filter(tag => tag.length > 0);
            let pageIndex = 1;
            for (let i = 0; i < tagList.length; ++i) {
                if (/^\d+$/.test(tagList[i])) {
                    pageIndex = parseInt(tagList[i], 10);
                    tagList.splice(i, 1);
                    break;
                }
            }
            Booru.makeRequest(tagList, Booru.allowNsfw, Booru.limit, pageIndex);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: root.padding

        // Image list
        ListView {
            id: booruResponseListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            clip: true
            boundsBehavior: Flickable.DragAndOvershootBounds

            model: root.responses
            delegate: BooruResponse {
                responseData: modelData
                tagInputField: root.inputField
                previewDownloadPath: root.previewDownloadPath
                downloadPath: root.downloadPath
                nsfwPath: root.nsfwPath
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            // Placeholder
            Rectangle {
                anchors.centerIn: parent
                visible: root.responses.length === 0
                width: 200
                height: 100
                color: "transparent"

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialSymbol {
                        anchors.horizontalCenter: parent.horizontalCenter
                        iconSize: 48
                        color: Appearance.m3colors.m3secondaryText
                        text: "bookmark_heart"
                    }

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Anime Boorus"
                        font.pixelSize: Appearance.font.pixelSize.textLarge
                        color: Appearance.m3colors.m3secondaryText
                    }

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Enter tags to search"
                        font.pixelSize: Appearance.font.pixelSize.textSmall
                        color: Appearance.m3colors.m3secondaryText
                    }
                }
            }

            // Loading indicator
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 20
                visible: Booru.runningRequests > 0
                width: 100
                height: 32
                radius: 16
                color: Appearance.colors.colLayer2

                StyledText {
                    anchors.centerIn: parent
                    text: "Loading..."
                    font.pixelSize: Appearance.font.pixelSize.textSmall
                    color: Appearance.m3colors.m3surfaceText
                }
            }
        }

        // Tag suggestions
        Flow {
            id: tagSuggestions
            visible: root.suggestionList.length > 0 && tagInputField.text.length > 0
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: root.suggestionList.slice(0, 8)

                RippleButton {
                    implicitHeight: 28
                    implicitWidth: suggestionText.implicitWidth + countText.implicitWidth + 20
                    buttonRadius: 4
                    colBackground: Appearance.colors.colLayer2

                    contentItem: Row {
                        anchors.centerIn: parent
                        spacing: 6

                        StyledText {
                            id: suggestionText
                            text: modelData.displayName ?? modelData.name
                            font.pixelSize: Appearance.font.pixelSize.textSmall
                            color: Appearance.m3colors.m3surfaceText
                        }

                        StyledText {
                            id: countText
                            visible: modelData.count !== undefined
                            text: modelData.count ?? ""
                            font.pixelSize: 10
                            color: Appearance.m3colors.m3secondaryText
                        }
                    }

                    onClicked: {
                        const words = tagInputField.text.trim().split(/\s+/);
                        if (words.length > 0) {
                            words[words.length - 1] = modelData.name;
                        } else {
                            words.push(modelData.name);
                        }
                        tagInputField.text = words.join(" ") + " ";
                        tagInputField.forceActiveFocus();
                    }
                }
            }
        }

        // Input area
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: inputColumn.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            clip: true

            ColumnLayout {
                id: inputColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                // Text input row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledTextArea {
                        id: tagInputField
                        Layout.fillWidth: true
                        wrapMode: TextArea.Wrap
                        placeholderText: 'Enter tags, or "/" for commands'
                        color: Appearance.m3colors.m3surfaceText

                        signal accepted()

                        property Timer searchTimer: Timer {
                            interval: root.tagSuggestionDelay
                            repeat: false
                            onTriggered: {
                                const words = tagInputField.text.trim().split(/\s+/);
                                if (words.length > 0 && words[words.length - 1].length > 0) {
                                    Booru.triggerTagSearch(words[words.length - 1]);
                                }
                            }
                        }

                        onTextChanged: {
                            if (text.length === 0) {
                                root.suggestionList = [];
                                searchTimer.stop();
                                return;
                            }

                            if (text.startsWith(`${root.commandPrefix}mode`)) {
                                const query = text.split(" ")[1] ?? "";
                                root.suggestionList = Booru.providerList
                                    .filter(p => p.includes(query.toLowerCase()))
                                    .map(p => ({
                                        name: `/mode ${p}`,
                                        displayName: Booru.providers[p].name,
                                        description: Booru.providers[p].description
                                    }));
                                searchTimer.stop();
                                return;
                            }

                            if (text.startsWith(root.commandPrefix)) {
                                root.suggestionList = root.allCommands
                                    .filter(cmd => cmd.name.startsWith(text.substring(1)))
                                    .map(cmd => ({
                                        name: `${root.commandPrefix}${cmd.name}`,
                                        description: cmd.description
                                    }));
                                searchTimer.stop();
                                return;
                            }

                            searchTimer.restart();
                        }

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                                if (!(event.modifiers & Qt.ShiftModifier)) {
                                    root.handleInput(text);
                                    text = "";
                                    event.accepted = true;
                                }
                            }
                        }

                        onAccepted: {
                            root.handleInput(text);
                            text = "";
                        }

                        Component.onCompleted: {
                            root.inputField = tagInputField;
                        }
                    }

                    RippleButton {
                        id: sendButton
                        implicitWidth: 40
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.small
                        enabled: tagInputField.text.length > 0
                        toggled: enabled

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 22
                            color: sendButton.enabled ? Appearance.m3colors.m3accentPrimaryText : Appearance.m3colors.m3secondaryText
                            text: "arrow_upward"
                        }

                        onClicked: {
                            root.handleInput(tagInputField.text);
                            tagInputField.text = "";
                        }
                    }
                }

                // Controls row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Provider indicator
                    Rectangle {
                        implicitWidth: providerText.implicitWidth + 16
                        implicitHeight: 24
                        radius: 4
                        color: Appearance.colors.colLayer1

                        StyledText {
                            id: providerText
                            anchors.centerIn: parent
                            font.pixelSize: 11
                            color: Appearance.m3colors.m3secondaryText
                            text: Booru.providers[Booru.currentProvider]?.name ?? "yande.re"
                        }
                    }

                    StyledText {
                        text: "•"
                        color: Appearance.m3colors.m3secondaryText
                    }

                    // NSFW toggle
                    Row {
                        spacing: 4

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: 11
                            color: Appearance.m3colors.m3secondaryText
                            text: "NSFW"
                        }

                        StyledSwitch {
                            scale: 0.6
                            checked: Booru.allowNsfw
                            onCheckedChanged: Booru.allowNsfw = checked
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Mode button
                    RippleButton {
                        implicitHeight: 24
                        implicitWidth: modeText.implicitWidth + 16
                        buttonRadius: 4
                        colBackground: Appearance.colors.colLayer1

                        contentItem: StyledText {
                            id: modeText
                            anchors.centerIn: parent
                            font.pixelSize: 11
                            color: Appearance.m3colors.m3secondaryText
                            text: "/mode"
                        }

                        onClicked: {
                            tagInputField.text = "/mode ";
                            tagInputField.forceActiveFocus();
                        }
                    }

                    // Clear button
                    RippleButton {
                        implicitHeight: 24
                        implicitWidth: clearText.implicitWidth + 16
                        buttonRadius: 4
                        colBackground: Appearance.colors.colLayer1

                        contentItem: StyledText {
                            id: clearText
                            anchors.centerIn: parent
                            font.pixelSize: 11
                            color: Appearance.m3colors.m3secondaryText
                            text: "/clear"
                        }

                        onClicked: {
                            Booru.clearResponses();
                            tagInputField.text = "";
                        }
                    }
                }
            }
        }
    }
}
