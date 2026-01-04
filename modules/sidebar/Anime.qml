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

    // Preview signals - forwarded to SidebarLeft
    signal showPreview(var imageData, string cachedSource, bool manualDownload, string provider)
    signal hidePreview()

    // Currently previewed image ID (passed from SidebarLeft)
    property var previewImageId: null

    property var inputField: null
    readonly property var responses: Booru.responses
    property string previewDownloadPath: Directories.cacheDir + "/booru/previews"
    // homeDir has file:// prefix, must trim for shell commands
    property string downloadPath: FileUtils.trimFileProtocol(Directories.homeDir) + "/Pictures/booru"
    property string nsfwPath: FileUtils.trimFileProtocol(Directories.homeDir) + "/Pictures/booru/nsfw"
    property string commandPrefix: "/"
    property int tagSuggestionDelay: 250
    property var suggestionList: []
    property bool showControlsMenu: false
    property string lastTagQuery: ""  // Track last query to prevent stale suggestions

    // Expose ListView for keyboard navigation
    readonly property alias listView: booruResponseListView

    // Scroll functions for vim-like navigation
    function scrollUp(amount) {
        var newY = booruResponseListView.contentY - (amount || 100)
        booruResponseListView.contentY = Math.max(0, newY)
    }

    function scrollDown(amount) {
        var maxY = booruResponseListView.contentHeight - booruResponseListView.height
        var newY = booruResponseListView.contentY + (amount || 100)
        booruResponseListView.contentY = Math.min(Math.max(0, maxY), newY)
    }

    function scrollToTop() {
        booruResponseListView.contentY = 0
    }

    function scrollToBottom() {
        booruResponseListView.contentY = booruResponseListView.contentHeight - booruResponseListView.height
    }

    function scrollPageUp() {
        scrollUp(booruResponseListView.height * 0.8)
    }

    function scrollPageDown() {
        scrollDown(booruResponseListView.height * 0.8)
    }

    // Load next page
    function loadNextPage() {
        handleInput("+")
    }

    // Load previous page
    function loadPrevPage() {
        handleInput("/prev")
    }

    // Focus the input field
    function focusInput() {
        if (root.inputField) root.inputField.forceActiveFocus()
    }

    Connections {
        target: Booru
        function onTagSuggestion(query, suggestions) {
            // Only apply suggestions if query matches current input state
            // This prevents stale suggestions from appearing after input is cleared
            if (query === root.lastTagQuery && tagInputField.text.length > 0) {
                root.suggestionList = suggestions
            }
        }
    }

    property var allCommands: [
        { name: "mode", description: "Set the API provider" },
        { name: "mirror", description: "Switch provider mirror" },
        { name: "sort", description: "Set result sorting" },
        { name: "res", description: "Set Wallhaven resolution" },
        { name: "clear", description: "Clear image list" },
        { name: "next", description: "Get next page" },
        { name: "safe", description: "Disable NSFW" },
        { name: "lewd", description: "Allow NSFW" }
    ]

    function handleInput(inputText) {
        if (inputText.startsWith(root.commandPrefix)) {
            var command = inputText.split(" ")[0].substring(1)
            var args = inputText.split(" ").slice(1)

            if (command === "mode" && args.length > 0) {
                Booru.setProvider(args[0]);
            } else if (command === "clear") {
                Booru.clearResponses();
            } else if (command === "next") {
                if (Booru.responses.length > 0) {
                    Booru.makeRequest(Booru.currentTags, Booru.allowNsfw, Booru.limit, Booru.currentPage + 1)
                }
            } else if (command === "prev") {
                if (Booru.responses.length > 0 && Booru.currentPage > 1) {
                    Booru.makeRequest(Booru.currentTags, Booru.allowNsfw, Booru.limit, Booru.currentPage - 1)
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
            } else if (command === "res" && args.length > 0) {
                // Set Wallhaven resolution
                if (Booru.currentProvider !== "wallhaven") {
                    Booru.addSystemMessage("Resolution filter only applies to Wallhaven");
                } else {
                    var resArg = args[0].toLowerCase();
                    // Check for friendly names (720p, 1080p, etc)
                    var resValue = resArg;
                    for (var key in Booru.resolutionLabels) {
                        if (Booru.resolutionLabels[key].toLowerCase() === resArg) {
                            resValue = key;
                            break;
                        }
                    }
                    if (Booru.resolutionOptions.indexOf(resValue) !== -1) {
                        Booru.wallhavenResolution = resValue;
                        var label = Booru.resolutionLabels[resValue] || resValue;
                        Booru.addSystemMessage("Wallhaven resolution: " + label);
                    } else {
                        Booru.addSystemMessage("Resolution options: " + Booru.resolutionOptions.map(function(r) {
                            return Booru.resolutionLabels[r] || r;
                        }).join(", "));
                    }
                }
            } else if (command === "res") {
                // No argument - show current resolution
                if (Booru.currentProvider !== "wallhaven") {
                    Booru.addSystemMessage("Resolution filter only applies to Wallhaven");
                } else {
                    var label2 = Booru.resolutionLabels[Booru.wallhavenResolution] || Booru.wallhavenResolution;
                    Booru.addSystemMessage("Wallhaven resolution: " + label2);
                }
            } else if (command === "mirror" && args.length > 0) {
                // Set mirror for current provider
                if (!Booru.providerHasMirrors(Booru.currentProvider)) {
                    var providerName4 = Booru.providers[Booru.currentProvider].name || Booru.currentProvider;
                    Booru.addSystemMessage(providerName4 + " does not have mirrors");
                } else {
                    var mirrorArg = args[0].toLowerCase();
                    var mirrorList = Booru.getMirrorList(Booru.currentProvider);
                    // Find mirror matching the argument
                    var matchedMirror = null;
                    for (var k = 0; k < mirrorList.length; k++) {
                        if (mirrorList[k].toLowerCase().indexOf(mirrorArg) !== -1) {
                            matchedMirror = mirrorList[k];
                            break;
                        }
                    }
                    if (matchedMirror) {
                        Booru.setMirror(Booru.currentProvider, matchedMirror);
                        Booru.addSystemMessage("Mirror: " + matchedMirror);
                    } else {
                        Booru.addSystemMessage("Available mirrors: " + mirrorList.join(", "));
                    }
                }
            } else if (command === "mirror") {
                // No argument - show current mirror
                if (!Booru.providerHasMirrors(Booru.currentProvider)) {
                    var providerName5 = Booru.providers[Booru.currentProvider].name || Booru.currentProvider;
                    Booru.addSystemMessage(providerName5 + " does not have mirrors");
                } else {
                    var currentMirror = Booru.getCurrentMirror(Booru.currentProvider);
                    var mirrorData = Booru.providers[Booru.currentProvider].mirrors[currentMirror];
                    var mirrorDesc = mirrorData && mirrorData.description ? " (" + mirrorData.description + ")" : "";
                    Booru.addSystemMessage("Current mirror: " + currentMirror + mirrorDesc);
                }
            } else {
                Booru.addSystemMessage("Unknown command: " + command);
            }
        } else if (inputText.trim() === "+") {
            root.handleInput(root.commandPrefix + "next")
        } else {
            var tagList = inputText.split(/\s+/).filter(function(tag) { return tag.length > 0 })
            var pageIndex = 1
            for (var i = 0; i < tagList.length; ++i) {
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

        // Image list (single page at a time)
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
                previewImageId: root.previewImageId
                onShowPreview: function(imageData, cachedSource, manualDownload, provider) {
                    root.showPreview(imageData, cachedSource, manualDownload, provider)
                }
                onHidePreview: root.hidePreview()
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
                model: root.suggestionList.slice(0, 20)

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
                        var words = tagInputField.text.trim().split(/\s+/)
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
                                var words = tagInputField.text.trim().split(/\s+/)
                                if (words.length > 0 && words[words.length - 1].length > 0) {
                                    root.lastTagQuery = words[words.length - 1]
                                    Booru.triggerTagSearch(root.lastTagQuery)
                                }
                            }
                        }

                        onTextChanged: {
                            if (text.length === 0) {
                                root.suggestionList = []
                                root.lastTagQuery = ""  // Clear to prevent stale suggestions
                                searchTimer.stop()
                                return
                            }

                            if (text.startsWith(root.commandPrefix + "mode")) {
                                var parts = text.split(" ");
                                var query = parts.length > 1 ? parts[1] : ""
                                root.suggestionList = Booru.providerList
                                    .filter(function(p) { return p.includes(query.toLowerCase()) })
                                    .map(function(p) { return {
                                        name: "/mode " + p,
                                        displayName: Booru.providers[p].name,
                                        description: Booru.providers[p].description
                                    }})
                                searchTimer.stop();
                                return;
                            }

                            // /mirror autocomplete
                            if (text.startsWith(root.commandPrefix + "mirror")) {
                                var mirrorParts = text.split(" ");
                                var mirrorQuery = mirrorParts.length > 1 ? mirrorParts[1].toLowerCase() : "";

                                // Check if provider has mirrors
                                if (!Booru.providerHasMirrors(Booru.currentProvider)) {
                                    var noMirrorProvider = Booru.providers[Booru.currentProvider];
                                    var noMirrorName = noMirrorProvider && noMirrorProvider.name ? noMirrorProvider.name : Booru.currentProvider;
                                    root.suggestionList = [{
                                        name: "/mirror",
                                        displayName: "No mirrors",
                                        description: noMirrorName + " does not have mirrors"
                                    }];
                                    searchTimer.stop();
                                    return;
                                }

                                var mirrors = Booru.getMirrorList(Booru.currentProvider);
                                var currentMirror = Booru.getCurrentMirror(Booru.currentProvider);
                                var providerMirrors = Booru.providers[Booru.currentProvider].mirrors;

                                root.suggestionList = mirrors
                                    .filter(function(m) { return m.toLowerCase().indexOf(mirrorQuery) !== -1; })
                                    .map(function(m) {
                                        var mData = providerMirrors[m];
                                        var desc = mData && mData.description ? mData.description : "";
                                        if (m === currentMirror) {
                                            desc = desc ? "(" + desc + ", current)" : "(current)";
                                        } else if (desc) {
                                            desc = "(" + desc + ")";
                                        }
                                        return {
                                            name: "/mirror " + m,
                                            displayName: m,
                                            description: desc
                                        };
                                    });
                                searchTimer.stop();
                                return;
                            }

                            if (text.startsWith(root.commandPrefix + "sort")) {
                                var sortParts = text.split(" ");
                                var sortQuery = sortParts.length > 1 ? sortParts[1] : ""
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

                            // /res autocomplete (Wallhaven resolution)
                            if (text.startsWith(root.commandPrefix + "res ")) {
                                var resParts = text.split(" ");
                                var resQuery = resParts.length > 1 ? resParts[1].toLowerCase() : "";

                                root.suggestionList = Booru.resolutionOptions
                                    .filter(function(r) {
                                        var label = Booru.resolutionLabels[r] || r;
                                        return label.toLowerCase().indexOf(resQuery) !== -1 ||
                                               r.toLowerCase().indexOf(resQuery) !== -1;
                                    })
                                    .map(function(r) {
                                        var label = Booru.resolutionLabels[r] || r;
                                        return {
                                            name: "/res " + label.toLowerCase(),
                                            displayName: label,
                                            description: r === Booru.wallhavenResolution ? "(current)" : ""
                                        };
                                    });
                                searchTimer.stop();
                                return;
                            }

                            if (text.startsWith(root.commandPrefix)) {
                                root.suggestionList = root.allCommands
                                    .filter(function(cmd) { return cmd.name.startsWith(text.substring(1)) })
                                    .map(function(cmd) { return {
                                        name: root.commandPrefix + cmd.name,
                                        description: cmd.description
                                    }})
                                searchTimer.stop()
                                return
                            }

                            searchTimer.restart()
                        }

                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                                if (!(event.modifiers & Qt.ShiftModifier)) {
                                    root.handleInput(text)
                                    text = ""
                                    event.accepted = true
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

                // Expandable controls menu (shown when settings icon is clicked)
                Flow {
                    id: controlsMenu
                    visible: root.showControlsMenu
                    Layout.fillWidth: true
                    spacing: 6

                    // NSFW toggle chip (hidden for SFW-only providers)
                    RippleButton {
                        visible: Booru.providerSupportsNsfw
                        implicitHeight: 26
                        implicitWidth: nsfwChipContent.implicitWidth + 14
                        buttonRadius: Appearance.rounding.full
                        colBackground: Booru.allowNsfw ? Appearance.colors.colLayer2Active : Appearance.colors.colLayer1
                        toggled: Booru.allowNsfw

                        contentItem: Row {
                            id: nsfwChipContent
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                iconSize: 13
                                color: Booru.allowNsfw ? Appearance.m3colors.m3accentPrimaryText : Appearance.m3colors.m3secondaryText
                                text: Booru.allowNsfw ? "visibility" : "visibility_off"
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 11
                                color: Booru.allowNsfw ? Appearance.m3colors.m3accentPrimaryText : Appearance.m3colors.m3surfaceText
                                text: "NSFW"
                            }
                        }

                        onClicked: Booru.allowNsfw = !Booru.allowNsfw
                    }

                    // Mirror chip (visible when provider has mirrors)
                    RippleButton {
                        visible: Booru.providerHasMirrors(Booru.currentProvider)
                        implicitHeight: 26
                        implicitWidth: mirrorChipContent.implicitWidth + 14
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer1

                        contentItem: Row {
                            id: mirrorChipContent
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                iconSize: 13
                                color: Appearance.m3colors.m3secondaryText
                                text: "language"
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 11
                                color: Appearance.m3colors.m3surfaceText
                                text: Booru.getCurrentMirror(Booru.currentProvider) || "Mirror"
                            }
                        }

                        onClicked: {
                            // Cycle to next mirror
                            var mirrors = Booru.getMirrorList(Booru.currentProvider);
                            var current = Booru.getCurrentMirror(Booru.currentProvider);
                            var idx = mirrors.indexOf(current);
                            var next = mirrors[(idx + 1) % mirrors.length];
                            Booru.setMirror(Booru.currentProvider, next);
                        }
                    }

                    // Sort chip (visible when provider supports sorting)
                    RippleButton {
                        visible: Booru.providerSupportsSorting
                        implicitHeight: 26
                        implicitWidth: sortChipContent.implicitWidth + 14
                        buttonRadius: Appearance.rounding.full
                        colBackground: Booru.currentSorting ? Appearance.colors.colLayer2Active : Appearance.colors.colLayer1
                        toggled: Booru.currentSorting ? true : false

                        contentItem: Row {
                            id: sortChipContent
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                iconSize: 13
                                color: Booru.currentSorting ? Appearance.m3colors.m3accentPrimaryText : Appearance.m3colors.m3secondaryText
                                text: "sort"
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 11
                                color: Booru.currentSorting ? Appearance.m3colors.m3accentPrimaryText : Appearance.m3colors.m3surfaceText
                                text: Booru.currentSorting ? Booru.currentSorting : "Sort"
                            }
                        }

                        onClicked: {
                            tagInputField.text = "/sort ";
                            tagInputField.forceActiveFocus();
                            root.showControlsMenu = false;
                        }
                    }

                    // Toprange chip (visible when Wallhaven + toplist sorting)
                    RippleButton {
                        visible: Booru.currentProvider === "wallhaven" &&
                                 (Booru.currentSorting === "toplist" ||
                                  (Booru.currentSorting === "" && Booru.wallhavenSorting === "toplist"))
                        implicitHeight: 26
                        implicitWidth: topRangeChipContent.implicitWidth + 14
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer1

                        contentItem: Row {
                            id: topRangeChipContent
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                iconSize: 13
                                color: Appearance.m3colors.m3secondaryText
                                text: "date_range"
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 11
                                color: Appearance.m3colors.m3surfaceText
                                text: Booru.wallhavenTopRange
                            }
                        }

                        onClicked: {
                            var options = Booru.topRangeOptions
                            var currentIdx = options.indexOf(Booru.wallhavenTopRange)
                            var nextIdx = (currentIdx + 1) % options.length
                            Booru.wallhavenTopRange = options[nextIdx]
                        }
                    }

                    // Resolution chip (visible when Wallhaven)
                    RippleButton {
                        visible: Booru.currentProvider === "wallhaven"
                        implicitHeight: 26
                        implicitWidth: resChipContent.implicitWidth + 14
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer1

                        contentItem: Row {
                            id: resChipContent
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                iconSize: 13
                                color: Appearance.m3colors.m3secondaryText
                                text: "aspect_ratio"
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 11
                                color: Appearance.m3colors.m3surfaceText
                                text: Booru.resolutionLabels[Booru.wallhavenResolution] || Booru.wallhavenResolution
                            }
                        }

                        onClicked: {
                            var options = Booru.resolutionOptions
                            var currentIdx = options.indexOf(Booru.wallhavenResolution)
                            var nextIdx = (currentIdx + 1) % options.length
                            Booru.wallhavenResolution = options[nextIdx]
                        }
                    }

                    // Age chip (visible for Danbooru-compatible APIs - prevents search timeout)
                    RippleButton {
                        visible: Booru.providerSupportsAgeFilter
                        implicitHeight: 26
                        implicitWidth: ageChipContent.implicitWidth + 14
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer1

                        contentItem: Row {
                            id: ageChipContent
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                iconSize: 13
                                color: Appearance.m3colors.m3secondaryText
                                text: "schedule"
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 11
                                color: Appearance.m3colors.m3surfaceText
                                text: Booru.danbooruAgeLabels[Booru.danbooruAge] || Booru.danbooruAge
                            }
                        }

                        onClicked: {
                            var options = Booru.danbooruAgeOptions
                            var currentIdx = options.indexOf(Booru.danbooruAge)
                            var nextIdx = (currentIdx + 1) % options.length
                            Booru.danbooruAge = options[nextIdx]
                        }
                    }

                    // Mode chip
                    RippleButton {
                        implicitHeight: 26
                        implicitWidth: modeChipContent.implicitWidth + 14
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer1

                        contentItem: Row {
                            id: modeChipContent
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                iconSize: 13
                                color: Appearance.m3colors.m3secondaryText
                                text: "swap_horiz"
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 11
                                color: Appearance.m3colors.m3surfaceText
                                text: "Provider"
                            }
                        }

                        onClicked: {
                            tagInputField.text = "/mode ";
                            tagInputField.forceActiveFocus();
                            root.showControlsMenu = false;
                        }
                    }

                    // Clear chip
                    RippleButton {
                        implicitHeight: 26
                        implicitWidth: clearChipContent.implicitWidth + 14
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer1

                        contentItem: Row {
                            id: clearChipContent
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                iconSize: 13
                                color: Appearance.m3colors.m3secondaryText
                                text: "delete_sweep"
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 11
                                color: Appearance.m3colors.m3surfaceText
                                text: "Clear"
                            }
                        }

                        onClicked: {
                            Booru.clearResponses();
                            tagInputField.text = "";
                            root.showControlsMenu = false;
                        }
                    }
                }

                // Controls row - provider indicator + settings button
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Provider indicator (always visible)
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

                    Item { Layout.fillWidth: true }

                    // Settings button (toggles controls menu)
                    RippleButton {
                        implicitHeight: 24
                        implicitWidth: settingsText.implicitWidth + 16
                        buttonRadius: 4
                        colBackground: Appearance.colors.colLayer1

                        contentItem: StyledText {
                            id: settingsText
                            anchors.centerIn: parent
                            font.pixelSize: 11
                            color: Appearance.m3colors.m3secondaryText
                            text: root.showControlsMenu ? "Hide" : "More"
                        }

                        onClicked: root.showControlsMenu = !root.showControlsMenu
                    }
                }
            }
        }
    }
}
