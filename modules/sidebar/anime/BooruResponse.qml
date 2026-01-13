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

    // Currently previewed image ID (null if no preview)
    property var previewImageId: null

    // Preview signals - forwarded to Anime
    signal showPreview(var imageData, string cachedSource, bool manualDownload, string provider)
    signal hidePreview()
    signal updatePreviewSource(string cachedSource)

    property real availableWidth: parent ? parent.width : 400
    property real rowTooShortThreshold: 150
    property real imageSpacing: 5
    property real responsePadding: 8

    // Cached layout result - only recomputed when width changes (debounced)
    property var cachedLayout: []

    // Compute layout rows from images - called once per debounced width change
    function computeLayout() {
        var i = 0
        var rows = []
        var responseList = root.responseData.images || []
        var minRowHeight = root.rowTooShortThreshold
        var availableImageWidth = root.availableWidth - root.imageSpacing - (root.responsePadding * 2)

        while (i < responseList.length) {
            var row = { height: 0, images: [] }
            var j = i
            var combinedAspect = 0
            var rowHeight = 0

            while (j < responseList.length) {
                combinedAspect += responseList[j].aspect_ratio || 1
                var imagesInRow = j - i + 1
                var totalSpacing = root.imageSpacing * (imagesInRow - 1)
                var rowAvailableWidth = availableImageWidth - totalSpacing
                rowHeight = rowAvailableWidth / combinedAspect

                if (rowHeight < minRowHeight) {
                    combinedAspect -= responseList[j].aspect_ratio || 1
                    imagesInRow -= 1
                    totalSpacing = root.imageSpacing * (imagesInRow - 1)
                    rowAvailableWidth = availableImageWidth - totalSpacing
                    rowHeight = rowAvailableWidth / combinedAspect
                    break
                }
                j++
            }

            if (j === i) {
                row.images.push(responseList[i])
                row.height = availableImageWidth / (responseList[i].aspect_ratio || 1)
                rows.push(row)
                i++
            } else {
                for (var k = i; k < j; k++) {
                    row.images.push(responseList[k])
                }
                imagesInRow = j - i
                totalSpacing = root.imageSpacing * (imagesInRow - 1)
                rowAvailableWidth = availableImageWidth - totalSpacing
                row.height = rowAvailableWidth / combinedAspect
                rows.push(row)
                i = j
            }
        }
        return rows
    }

    anchors.left: parent ? parent.left : undefined
    anchors.right: parent ? parent.right : undefined
    implicitHeight: columnLayout.implicitHeight + root.responsePadding * 2

    Component.onCompleted: {
        availableWidth = parent ? parent.width : 400
        cachedLayout = computeLayout()
        var imageCount = root.responseData && root.responseData.images ? root.responseData.images.length : 0
        var tagCount = root.responseData && root.responseData.tags ? root.responseData.tags.length : 0
        Logger.debug("BooruResponse", `Rendered: ${root.responseData.provider} page=${root.responseData.page} images=${imageCount} tags=${tagCount}`)
    }

    Connections {
        target: parent
        enabled: parent !== null
        function onWidthChanged() {
            updateWidthTimer.restart()
        }
    }

    Timer {
        id: updateWidthTimer
        interval: 16  // ~60fps for smooth resize
        onTriggered: {
            availableWidth = parent ? parent.width : 400
            cachedLayout = computeLayout()
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

        // Image grid - uses cached layout to avoid recalculation on every binding evaluation
        Repeater {
            model: root.cachedLayout

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
                        provider: root.responseData.provider
                        manualDownload: Booru.providerRequiresManualDownload(root.responseData.provider)
                        previewDownloadPath: root.previewDownloadPath
                        downloadPath: root.downloadPath
                        nsfwPath: root.nsfwPath
                        isPreviewActive: root.previewImageId !== null && modelData.id === root.previewImageId
                        onShowPreview: function(imageData, cachedSource, manualDownload, provider) {
                            root.showPreview(imageData, cachedSource, manualDownload, provider)
                        }
                        onHidePreview: root.hidePreview()
                        onUpdatePreviewSource: function(cachedSource) {
                            root.updatePreviewSource(cachedSource)
                        }
                    }
                }
            }
        }

        // Pagination navigation (Prev/Next)
        RowLayout {
            visible: root.responseData.page > 0
            Layout.fillWidth: true
            spacing: 8

            // Previous button
            RippleButton {
                implicitHeight: 32
                implicitWidth: prevRow.implicitWidth + 20
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer2
                enabled: root.responseData.page > 1
                opacity: enabled ? 1.0 : 0.4

                onClicked: {
                    Booru.makeRequest(
                        root.responseData.tags || [],
                        Booru.allowNsfw,
                        Booru.limit,
                        parseInt(root.responseData.page) - 1
                    )
                }

                contentItem: Row {
                    id: prevRow
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

            // Next button
            RippleButton {
                implicitHeight: 32
                implicitWidth: nextRow.implicitWidth + 20
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer2

                onClicked: {
                    Booru.makeRequest(
                        root.responseData.tags || [],
                        Booru.allowNsfw,
                        Booru.limit,
                        parseInt(root.responseData.page) + 1
                    )
                }

                contentItem: Row {
                    id: nextRow
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
