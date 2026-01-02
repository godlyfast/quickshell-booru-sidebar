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
        { name: "sort", description: "Set result sorting" },
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
            } else if (command === "sort" && args.length > 0) {
                var sortArg = args[0].toLowerCase();
                var sortOptions = Booru.getSortOptions();

                // Check if provider supports sorting
                if (sortOptions.length === 0) {
                    var providerObj = Booru.providers[Booru.currentProvider]
                    var providerName = providerObj && providerObj.name ? providerObj.name : Booru.currentProvider
                    Booru.addSystemMessage(providerName + " does not support sorting");
                }
                // Handle "default" or "none" to clear sorting
                else if (sortArg === "default" || sortArg === "none" || sortArg === "clear") {
                    Booru.currentSorting = "";
                    Booru.addSystemMessage("Sorting reset to default");
                }
                // Handle Wallhaven order specifically
                else if (Booru.currentProvider === "wallhaven" && (sortArg === "asc" || sortArg === "desc")) {
                    Booru.wallhavenOrder = sortArg;
                    Booru.addSystemMessage("Wallhaven order: " + sortArg);
                }
                // Handle Wallhaven toprange (e.g., /sort toprange 1w)
                else if (Booru.currentProvider === "wallhaven" && sortArg === "toprange") {
                    var rangeArg = args.length > 1 ? args[1] : "";
                    if (rangeArg && Booru.topRangeOptions.indexOf(rangeArg) !== -1) {
                        Booru.wallhavenTopRange = rangeArg;
                        Booru.addSystemMessage("Wallhaven toplist range: " + rangeArg);
                    } else {
                        Booru.addSystemMessage("Current toplist range: " + Booru.wallhavenTopRange + ". Options: " + Booru.topRangeOptions.join(", "));
                    }
                }
                // Check if sort option is valid for current provider
                else if (sortOptions.indexOf(sortArg) !== -1) {
                    Booru.currentSorting = sortArg;
                    var providerObj2 = Booru.providers[Booru.currentProvider]
                    var providerName2 = providerObj2 && providerObj2.name ? providerObj2.name : Booru.currentProvider
                    Booru.addSystemMessage(providerName2 + " sorting: " + sortArg);
                }
                // Invalid sort option
                else {
                    var validOptions = sortOptions.join(", ");
                    if (Booru.currentProvider === "wallhaven") {
                        validOptions += ", asc, desc";
                    }
                    Booru.addSystemMessage("Unknown sort option. Use: " + validOptions + ", default");
                }
            } else if (command === "sort") {
                // No argument - show current sorting
                var currentSort = Booru.currentSorting ? Booru.currentSorting : "default";
                var providerObj3 = Booru.providers[Booru.currentProvider]
                var providerName3 = providerObj3 && providerObj3.name ? providerObj3.name : Booru.currentProvider
                if (Booru.getSortOptions().length === 0) {
                    Booru.addSystemMessage(providerName3 + " does not support sorting");
                } else {
                    Booru.addSystemMessage(providerName3 + " sort: " + currentSort);
                }
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
                model: root.suggestionList.slice(0, 12)

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
                            text: modelData.displayName ? modelData.displayName : modelData.name
                            font.pixelSize: Appearance.font.pixelSize.textSmall
                            color: Appearance.m3colors.m3surfaceText
                        }

                        StyledText {
                            id: countText
                            visible: modelData.count !== undefined
                            text: modelData.count !== undefined ? modelData.count : ""
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
                                var parts = text.split(" ");
                                const query = parts.length > 1 ? parts[1] : "";
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

                            if (text.startsWith(`${root.commandPrefix}sort`)) {
                                var sortParts = text.split(" ");
                                const sortQuery = sortParts.length > 1 ? sortParts[1] : "";
                                var providerOptions = Booru.getSortOptions();

                                // If provider doesn't support sorting, show message
                                if (providerOptions.length === 0) {
                                    var noSortProvider = Booru.providers[Booru.currentProvider]
                                    var noSortName = noSortProvider && noSortProvider.name ? noSortProvider.name : Booru.currentProvider
                                    root.suggestionList = [{
                                        name: "/sort",
                                        displayName: "No sorting",
                                        description: noSortName + " does not support sorting"
                                    }];
                                    searchTimer.stop();
                                    return;
                                }

                                // Build options list: provider options + "default" + Wallhaven extras (if applicable)
                                var allSortOptions = providerOptions.slice();
                                allSortOptions.push("default");
                                if (Booru.currentProvider === "wallhaven") {
                                    allSortOptions.push("asc");
                                    allSortOptions.push("desc");
                                    allSortOptions.push("toprange");
                                }

                                // Check if user is typing "/sort toprange " to show range options
                                if (Booru.currentProvider === "wallhaven" && sortQuery.toLowerCase().startsWith("toprange ")) {
                                    var rangeQuery = sortQuery.substring(9).toLowerCase();
                                    root.suggestionList = Booru.topRangeOptions
                                        .filter(function(r) { return r.toLowerCase().indexOf(rangeQuery) !== -1; })
                                        .map(function(r) {
                                            return {
                                                name: "/sort toprange " + r,
                                                displayName: r,
                                                description: r === Booru.wallhavenTopRange ? "(current)" : ""
                                            };
                                        });
                                    searchTimer.stop();
                                    return;
                                }

                                root.suggestionList = allSortOptions
                                    .filter(function(s) { return s.indexOf(sortQuery.toLowerCase()) !== -1; })
                                    .map(function(s) {
                                        var desc = "";
                                        if (s === Booru.currentSorting) {
                                            desc = "(current)";
                                        } else if (s === "default" && (!Booru.currentSorting || Booru.currentSorting.length === 0)) {
                                            desc = "(current)";
                                        } else if (Booru.currentProvider === "wallhaven" && s === Booru.wallhavenOrder) {
                                            desc = "(current order)";
                                        } else if (s === "toprange") {
                                            desc = "(" + Booru.wallhavenTopRange + ")";
                                        }
                                        return {
                                            name: "/sort " + s,
                                            displayName: s,
                                            description: desc
                                        };
                                    });
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
                            text: {
                                var p = Booru.providers[Booru.currentProvider]
                                return p && p.name ? p.name : "yande.re"
                            }
                        }
                    }

                    StyledText {
                        text: "•"
                        color: Appearance.m3colors.m3secondaryText
                        visible: Booru.providerSupportsNsfw
                    }

                    // NSFW toggle (hidden for SFW-only providers like safebooru, e926, nekos.best)
                    Row {
                        spacing: 4
                        visible: Booru.providerSupportsNsfw

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

                    // Sort button
                    RippleButton {
                        implicitHeight: 24
                        implicitWidth: sortText.implicitWidth + 16
                        buttonRadius: 4
                        colBackground: Appearance.colors.colLayer1
                        visible: Booru.providerSupportsSorting

                        contentItem: StyledText {
                            id: sortText
                            anchors.centerIn: parent
                            font.pixelSize: 11
                            color: Appearance.m3colors.m3secondaryText
                            text: "/sort"
                        }

                        onClicked: {
                            tagInputField.text = "/sort ";
                            tagInputField.forceActiveFocus();
                        }
                    }

                    // Toprange selector (visible when Wallhaven + toplist sorting)
                    RippleButton {
                        implicitHeight: 24
                        implicitWidth: topRangeText.implicitWidth + 16
                        buttonRadius: 4
                        colBackground: Appearance.colors.colLayer1
                        visible: Booru.currentProvider === "wallhaven" &&
                                 (Booru.currentSorting === "toplist" ||
                                  (Booru.currentSorting === "" && Booru.wallhavenSorting === "toplist"))

                        contentItem: StyledText {
                            id: topRangeText
                            anchors.centerIn: parent
                            font.pixelSize: 11
                            color: Appearance.m3colors.m3secondaryText
                            text: Booru.wallhavenTopRange
                        }

                        onClicked: {
                            // Cycle through toprange options
                            var options = Booru.topRangeOptions
                            var currentIdx = options.indexOf(Booru.wallhavenTopRange)
                            var nextIdx = (currentIdx + 1) % options.length
                            Booru.wallhavenTopRange = options[nextIdx]
                        }
                    }

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
