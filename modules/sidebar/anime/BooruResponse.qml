import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../common"
import "../../common/widgets"
import "../../../services"

/**
 * A single booru response showing provider, tags, and image grid.
 */
Rectangle {
    id: root
    property var responseData
    property var tagInputField

    property string previewDownloadPath
    property string downloadPath
    property string nsfwPath

    property real availableWidth: parent ? parent.width : 400
    property real rowTooShortThreshold: 150
    property real imageSpacing: 5
    property real responsePadding: 8

    anchors.left: parent ? parent.left : undefined
    anchors.right: parent ? parent.right : undefined
    implicitHeight: columnLayout.implicitHeight + root.responsePadding * 2

    Component.onCompleted: {
        availableWidth = parent ? parent.width : 400
    }

    Connections {
        target: parent
        function onWidthChanged() {
            updateWidthTimer.restart()
        }
    }

    Timer {
        id: updateWidthTimer
        interval: 100
        onTriggered: {
            availableWidth = parent ? parent.width : 400
        }
    }

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: columnLayout
        anchors.fill: parent
        anchors.margins: responsePadding
        spacing: root.imageSpacing

        // Header row
        RowLayout {
            Layout.fillWidth: true

            Rectangle {
                color: Appearance.colors.colPrimary
                radius: Appearance.rounding.small
                implicitWidth: providerName.implicitWidth + 16
                implicitHeight: 28

                StyledText {
                    id: providerName
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.textSmall
                    color: Appearance.m3colors.m3accentPrimaryText
                    text: {
                        var p = Booru.providers[root.responseData.provider]
                        return p && p.name ? p.name : root.responseData.provider
                    }
                }
            }

            Item { Layout.fillWidth: true }

            StyledText {
                visible: root.responseData.page > 0
                font.pixelSize: Appearance.font.pixelSize.textSmall
                color: Appearance.m3colors.m3secondaryText
                text: "Page " + root.responseData.page
            }
        }

        // Tags row
        Flow {
            id: tagsFlow
            visible: root.responseData.tags && root.responseData.tags.length > 0
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: root.responseData.tags || []

                RippleButton {
                    implicitHeight: 24
                    implicitWidth: tagText.implicitWidth + 16
                    buttonRadius: 4
                    colBackground: Appearance.colors.colLayer2

                    contentItem: StyledText {
                        id: tagText
                        anchors.centerIn: parent
                        font.pixelSize: Appearance.font.pixelSize.textSmall
                        color: Appearance.m3colors.m3secondaryText
                        text: modelData
                    }

                    onClicked: {
                        if (root.tagInputField) {
                            if (root.tagInputField.text.length > 0) root.tagInputField.text += " "
                            root.tagInputField.text += modelData
                        }
                    }
                }
            }
        }

        // Message (if any)
        StyledText {
            visible: root.responseData.message && root.responseData.message.length > 0
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.textSmall
            color: Appearance.m3colors.m3secondaryText
            text: root.responseData.message || ""
            wrapMode: Text.WordWrap
        }

        // Image grid
        Repeater {
            model: {
                // Greedily add images to rows
                let i = 0;
                let rows = [];
                const responseList = root.responseData.images || [];
                const minRowHeight = root.rowTooShortThreshold;
                const availableImageWidth = root.availableWidth - root.imageSpacing - (root.responsePadding * 2);

                while (i < responseList.length) {
                    let row = { height: 0, images: [] };
                    let j = i;
                    let combinedAspect = 0;
                    let rowHeight = 0;

                    while (j < responseList.length) {
                        combinedAspect += responseList[j].aspect_ratio || 1;
                        let imagesInRow = j - i + 1;
                        let totalSpacing = root.imageSpacing * (imagesInRow - 1);
                        let rowAvailableWidth = availableImageWidth - totalSpacing;
                        rowHeight = rowAvailableWidth / combinedAspect;

                        if (rowHeight < minRowHeight) {
                            combinedAspect -= responseList[j].aspect_ratio || 1;
                            imagesInRow -= 1;
                            totalSpacing = root.imageSpacing * (imagesInRow - 1);
                            rowAvailableWidth = availableImageWidth - totalSpacing;
                            rowHeight = rowAvailableWidth / combinedAspect;
                            break;
                        }
                        j++;
                    }

                    if (j === i) {
                        row.images.push(responseList[i]);
                        row.height = availableImageWidth / (responseList[i].aspect_ratio || 1);
                        rows.push(row);
                        i++;
                    } else {
                        for (let k = i; k < j; k++) {
                            row.images.push(responseList[k]);
                        }
                        let imagesInRow = j - i;
                        let totalSpacing = root.imageSpacing * (imagesInRow - 1);
                        let rowAvailableWidth = availableImageWidth - totalSpacing;
                        row.height = rowAvailableWidth / combinedAspect;
                        rows.push(row);
                        i = j;
                    }
                }
                return rows;
            }

            delegate: RowLayout {
                id: imageRow
                required property var modelData
                property real rowHeight: modelData.height || 150
                spacing: root.imageSpacing

                Repeater {
                    model: modelData.images

                    BooruImage {
                        required property var modelData
                        imageData: modelData
                        rowHeight: imageRow.rowHeight
                        imageRadius: Appearance.rounding.small
                        manualDownload: ["danbooru", "waifu.im"].includes(root.responseData.provider)
                        previewDownloadPath: root.previewDownloadPath
                        downloadPath: root.downloadPath
                        nsfwPath: root.nsfwPath
                    }
                }
            }
        }

        // Pagination buttons
        RowLayout {
            visible: root.responseData.page > 0
            Layout.fillWidth: true
            spacing: 8

            // Previous page button
            RippleButton {
                visible: root.responseData.page > 1
                implicitHeight: 32
                implicitWidth: prevPageRow.implicitWidth + 20
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer2

                onClicked: {
                    if (root.tagInputField) {
                        Booru.replaceOnNextResponse = true
                        root.tagInputField.text = (root.responseData.tags || []).join(" ") + " " + (parseInt(root.responseData.page) - 1)
                        root.tagInputField.accepted()
                    }
                }

                contentItem: Row {
                    id: prevPageRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        iconSize: 18
                        color: Appearance.m3colors.m3surfaceText
                        text: "chevron_left"
                    }

                    StyledText {
                        text: "Prev"
                        font.pixelSize: Appearance.font.pixelSize.textSmall
                        color: Appearance.m3colors.m3surfaceText
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Next page button
            RippleButton {
                implicitHeight: 32
                implicitWidth: nextPageRow.implicitWidth + 20
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer2

                onClicked: {
                    if (root.tagInputField) {
                        Booru.replaceOnNextResponse = true
                        root.tagInputField.text = (root.responseData.tags || []).join(" ") + " " + (parseInt(root.responseData.page) + 1)
                        root.tagInputField.accepted()
                    }
                }

                contentItem: Row {
                    id: nextPageRow
                    anchors.centerIn: parent
                    spacing: 4

                    StyledText {
                        text: "Next"
                        font.pixelSize: Appearance.font.pixelSize.textSmall
                        color: Appearance.m3colors.m3surfaceText
                    }

                    MaterialSymbol {
                        iconSize: 18
                        color: Appearance.m3colors.m3surfaceText
                        text: "chevron_right"
                    }
                }
            }
        }
    }
}
