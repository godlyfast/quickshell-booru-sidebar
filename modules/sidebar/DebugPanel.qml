import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../common"
import "../common/widgets"
import "../../services" as Services

/**
 * Debug Panel - Live debugging interface for development.
 * Features:
 * - Live log viewer with level/category filtering
 * - Application state inspector
 * - Cache browser with file counts
 * - Performance metrics dashboard
 *
 * Open with F12 or Ctrl+Shift+D
 */
Popup {
    id: root

    // Size and positioning
    width: Math.min(700, parent.width - 40)
    height: Math.min(500, parent.height - 40)
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    modal: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // Filter state
    property int selectedLogLevel: 0  // 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR
    property string selectedCategory: ""  // Empty = all categories

    background: Rectangle {
        color: Appearance.m3colors.m3layerBackground2
        radius: Appearance.rounding.medium
        border.color: Appearance.m3colors.outline
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 0

        // Header with title and close button
        Rectangle {
            Layout.fillWidth: true
            height: 44
            color: Appearance.m3colors.m3layerBackground3
            radius: Appearance.rounding.medium

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 12

                StyledText {
                    text: "Debug Panel"
                    font.pixelSize: Appearance.font.pixelSize.textMedium
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                // Quick actions
                RippleButton {
                    implicitWidth: 80
                    implicitHeight: 28
                    buttonRadius: 4
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: "Clear Logs"
                        font.pixelSize: 11
                    }
                    onClicked: Services.Logger.clearBuffer()
                }

                RippleButton {
                    implicitWidth: 80
                    implicitHeight: 28
                    buttonRadius: 4
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: "Dump State"
                        font.pixelSize: 11
                    }
                    onClicked: {
                        var state = Services.Logger.dumpState()
                        Services.Logger.info("Debug", "State dump:\n" + JSON.stringify(state, null, 2))
                    }
                }

                RippleButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: 14
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 18
                    }
                    onClicked: root.close()
                }
            }
        }

        // Tab bar
        TabBar {
            id: tabBar
            Layout.fillWidth: true
            background: Rectangle {
                color: Appearance.m3colors.m3layerBackground2
            }

            TabButton {
                text: "Logs"
                width: implicitWidth
                contentItem: StyledText {
                    text: parent.text
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    opacity: parent.checked ? 1.0 : 0.6
                }
                background: Rectangle {
                    color: parent.checked ? Appearance.m3colors.primary : "transparent"
                    opacity: parent.checked ? 0.2 : 1
                    radius: 4
                }
            }

            TabButton {
                text: "State"
                width: implicitWidth
                contentItem: StyledText {
                    text: parent.text
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    opacity: parent.checked ? 1.0 : 0.6
                }
                background: Rectangle {
                    color: parent.checked ? Appearance.m3colors.primary : "transparent"
                    opacity: parent.checked ? 0.2 : 1
                    radius: 4
                }
            }

            TabButton {
                text: "Cache"
                width: implicitWidth
                contentItem: StyledText {
                    text: parent.text
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    opacity: parent.checked ? 1.0 : 0.6
                }
                background: Rectangle {
                    color: parent.checked ? Appearance.m3colors.primary : "transparent"
                    opacity: parent.checked ? 0.2 : 1
                    radius: 4
                }
            }

            TabButton {
                text: "Metrics"
                width: implicitWidth
                contentItem: StyledText {
                    text: parent.text
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    opacity: parent.checked ? 1.0 : 0.6
                }
                background: Rectangle {
                    color: parent.checked ? Appearance.m3colors.primary : "transparent"
                    opacity: parent.checked ? 0.2 : 1
                    radius: 4
                }
            }
        }

        // Tab content
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            // === Logs Tab ===
            Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    // Log filters
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            text: "Level:"
                            font.pixelSize: 12
                        }

                        ComboBox {
                            id: levelFilter
                            model: ["DEBUG", "INFO", "WARN", "ERROR"]
                            currentIndex: root.selectedLogLevel
                            onCurrentIndexChanged: root.selectedLogLevel = currentIndex
                            implicitWidth: 100
                            implicitHeight: 28
                        }

                        StyledText {
                            text: "Category:"
                            font.pixelSize: 12
                        }

                        ComboBox {
                            id: categoryFilter
                            model: ["All"].concat(Services.Logger.getCategories())
                            currentIndex: 0
                            onCurrentIndexChanged: {
                                root.selectedCategory = currentIndex === 0 ? "" : currentTextInput.text
                            }
                            implicitWidth: 120
                            implicitHeight: 28
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            text: Services.Logger.logBuffer.length + " entries"
                            font.pixelSize: 11
                            opacity: 0.7
                        }
                    }

                    // Log list
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Appearance.m3colors.m3layerBackground1
                        radius: 4

                        ListView {
                            id: logList
                            anchors.fill: parent
                            anchors.margins: 4
                            clip: true
                            model: Services.Logger.logBuffer.filter(entry => {
                                if (entry.levelNum < root.selectedLogLevel) return false
                                if (root.selectedCategory && entry.category !== root.selectedCategory) return false
                                return true
                            })

                            delegate: Rectangle {
                                width: logList.width
                                height: logText.implicitHeight + 6
                                color: index % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.03)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    spacing: 6

                                    // Level badge
                                    Rectangle {
                                        width: 50
                                        height: 16
                                        radius: 3
                                        color: {
                                            switch(modelData.level) {
                                                case "DEBUG": return "#6c757d"
                                                case "INFO": return "#0d6efd"
                                                case "WARN": return "#ffc107"
                                                case "ERROR": return "#dc3545"
                                                default: return "#6c757d"
                                            }
                                        }

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: modelData.level
                                            font.pixelSize: 9
                                            font.bold: true
                                            color: modelData.level === "WARN" ? "#000" : "#fff"
                                        }
                                    }

                                    // Category
                                    StyledText {
                                        text: "[" + modelData.category + "]"
                                        font.pixelSize: 11
                                        font.family: Appearance.font.family.codeFont
                                        opacity: 0.7
                                        Layout.preferredWidth: 80
                                    }

                                    // Message
                                    StyledText {
                                        id: logText
                                        text: modelData.message
                                        font.pixelSize: 11
                                        font.family: Appearance.font.family.codeFont
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }

                                    // Timestamp
                                    StyledText {
                                        text: modelData.timestamp.split("T")[1].split(".")[0]
                                        font.pixelSize: 10
                                        opacity: 0.5
                                    }
                                }
                            }

                            // Auto-scroll to bottom on new entries
                            onCountChanged: {
                                if (atYEnd) {
                                    Qt.callLater(() => positionViewAtEnd())
                                }
                            }
                        }
                    }
                }
            }

            // === State Tab ===
            Item {
                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 8

                    ColumnLayout {
                        width: parent.width
                        spacing: 12

                        // Booru State
                        StateSection {
                            title: "Booru Service"
                            Layout.fillWidth: true
                            properties: [
                                { key: "Provider", value: Services.Booru.currentProvider },
                                { key: "NSFW Mode", value: Services.Booru.allowNsfw ? "Enabled" : "Disabled" },
                                { key: "Sorting", value: Services.Booru.currentSorting || "(default)" },
                                { key: "Age Filter", value: Services.Booru.ageFilter },
                                { key: "Responses", value: Services.Booru.responses.length },
                                { key: "Running Requests", value: Services.Booru.runningRequests },
                                { key: "Pending XHR", value: Services.Booru.pendingXhrRequests.length }
                            ]
                        }

                        // Cache State
                        StateSection {
                            title: "Cache Index"
                            Layout.fillWidth: true
                            properties: [
                                { key: "Initialized", value: Services.CacheIndex.initialized ? "Yes" : "No" },
                                { key: "Scanning", value: Services.CacheIndex.scanning ? "Yes" : "No" },
                                { key: "Indexed Files", value: Object.keys(Services.CacheIndex.index).length }
                            ]
                        }

                        // Video Pool State
                        StateSection {
                            title: "Video Player Pool"
                            Layout.fillWidth: true
                            properties: [
                                { key: "Active Slots", value: Services.VideoPlayerPool.activeSlots.length },
                                { key: "Max Slots", value: Services.VideoPlayerPool.maxSlots },
                                { key: "Slot IDs", value: Services.VideoPlayerPool.activeSlots.map(s => s.imageId).join(", ") || "(none)" }
                            ]
                        }
                    }
                }
            }

            // === Cache Tab ===
            Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    // Cache stats
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        CacheStat {
                            label: "Total Files"
                            value: Object.keys(Services.CacheIndex.index).length
                        }

                        CacheStat {
                            label: "Preview Dir"
                            value: countByPrefix("")
                        }

                        CacheStat {
                            label: "Hi-Res"
                            value: countByPrefix("hires_")
                        }

                        CacheStat {
                            label: "Videos"
                            value: countByPrefix("video_")
                        }

                        CacheStat {
                            label: "GIFs"
                            value: countByPrefix("gif_")
                        }

                        Item { Layout.fillWidth: true }
                    }

                    // Cache file list (sample)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Appearance.m3colors.m3layerBackground1
                        radius: 4

                        ListView {
                            anchors.fill: parent
                            anchors.margins: 4
                            clip: true
                            model: Object.keys(Services.CacheIndex.index).slice(0, 100)

                            delegate: StyledText {
                                width: parent.width
                                text: modelData
                                font.pixelSize: 10
                                font.family: Appearance.font.family.codeFont
                                elide: Text.ElideMiddle
                            }
                        }

                        StyledText {
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.margins: 8
                            text: "Showing first 100 of " + Object.keys(Services.CacheIndex.index).length
                            font.pixelSize: 10
                            opacity: 0.6
                        }
                    }
                }
            }

            // === Metrics Tab ===
            Item {
                GridLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    columns: 2
                    rowSpacing: 16
                    columnSpacing: 24

                    MetricCard {
                        title: "Total Requests"
                        value: Services.Logger.metrics.totalRequests
                        Layout.fillWidth: true
                    }

                    MetricCard {
                        title: "Failed Requests"
                        value: Services.Logger.metrics.failedRequests
                        valueColor: Services.Logger.metrics.failedRequests > 0 ? "#dc3545" : Appearance.m3colors.onBackground
                        Layout.fillWidth: true
                    }

                    MetricCard {
                        title: "Avg Response Time"
                        value: Services.Logger.metrics.avgResponseTime + "ms"
                        Layout.fillWidth: true
                    }

                    MetricCard {
                        title: "Cache Hits"
                        value: Services.Logger.metrics.cacheHits
                        valueColor: "#28a745"
                        Layout.fillWidth: true
                    }

                    MetricCard {
                        title: "Cache Misses"
                        value: Services.Logger.metrics.cacheMisses
                        Layout.fillWidth: true
                    }

                    MetricCard {
                        title: "Hit Rate"
                        value: {
                            var total = Services.Logger.metrics.cacheHits + Services.Logger.metrics.cacheMisses
                            if (total === 0) return "N/A"
                            return Math.round(Services.Logger.metrics.cacheHits / total * 100) + "%"
                        }
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    // Helper function to count cache files by prefix
    function countByPrefix(prefix) {
        var count = 0
        var keys = Object.keys(Services.CacheIndex.index)
        for (var i = 0; i < keys.length; i++) {
            if (prefix === "" ? !keys[i].startsWith("hires_") && !keys[i].startsWith("video_") && !keys[i].startsWith("gif_") : keys[i].startsWith(prefix)) {
                count++
            }
        }
        return count
    }

    // === Inline Components ===

    component StateSection: Rectangle {
        property string title: ""
        property var properties: []

        implicitHeight: sectionContent.implicitHeight + 8
        color: Appearance.m3colors.m3layerBackground1
        radius: 6

        ColumnLayout {
            id: sectionContent
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            StyledText {
                text: title
                font.pixelSize: 13
                font.bold: true
            }

            Repeater {
                model: properties
                RowLayout {
                    spacing: 8
                    StyledText {
                        text: modelData.key + ":"
                        font.pixelSize: 11
                        opacity: 0.7
                        Layout.preferredWidth: 120
                    }
                    StyledText {
                        text: String(modelData.value)
                        font.pixelSize: 11
                        font.family: Appearance.font.family.codeFont
                    }
                }
            }
        }
    }

    component CacheStat: ColumnLayout {
        property string label: ""
        property var value: 0

        StyledText {
            text: String(value)
            font.pixelSize: 18
            font.bold: true
        }
        StyledText {
            text: label
            font.pixelSize: 11
            opacity: 0.7
        }
    }

    component MetricCard: Rectangle {
        property string title: ""
        property var value: 0
        property color valueColor: Appearance.m3colors.onBackground

        implicitHeight: 80
        color: Appearance.m3colors.m3layerBackground1
        radius: 8

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4

            StyledText {
                text: String(value)
                font.pixelSize: 24
                font.bold: true
                color: valueColor
                Layout.alignment: Qt.AlignHCenter
            }
            StyledText {
                text: title
                font.pixelSize: 12
                opacity: 0.7
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
