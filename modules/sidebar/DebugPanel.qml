import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../common"
import "../common/widgets"
import "../../services" as Services

/**
 * Debug Panel - Debugging interface for development.
 * Shows inside the sidebar area.
 * Open with F12
 */
Popup {
    id: root

    // Fill parent (sidebar)
    width: parent ? parent.width : 400
    height: parent ? parent.height : 600
    x: 0
    y: 0
    modal: true
    closePolicy: Popup.CloseOnEscape

    // Filter state
    property int selectedLogLevel: 0
    property string selectedCategory: ""

    background: Rectangle {
        color: Appearance.m3colors.m3layerBackground2
    }

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

    contentItem: ColumnLayout {
        spacing: 0

        // Header
        Rectangle {
            Layout.fillWidth: true
            height: 44
            color: Appearance.m3colors.m3layerBackground3

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 8

                StyledText {
                    text: "Debug Panel"
                    font.pixelSize: 16
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    implicitWidth: 70
                    implicitHeight: 26
                    buttonRadius: 4
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: "Clear"
                        font.pixelSize: 11
                    }
                    onClicked: Services.Logger.clearBuffer()
                }

                RippleButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: 13
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 16
                    }
                    onClicked: root.close()
                }
            }
        }

        // Tab bar
        TabBar {
            id: tabBar
            Layout.fillWidth: true
            background: Rectangle { color: Appearance.m3colors.m3layerBackground2 }

            TabButton {
                text: "Logs"
                width: implicitWidth
                contentItem: StyledText {
                    text: parent.text
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    opacity: parent.checked ? 1.0 : 0.6
                }
                background: Rectangle {
                    color: parent.checked ? Appearance.m3colors.m3accentPrimary : "transparent"
                    opacity: parent.checked ? 0.2 : 1
                    radius: 4
                }
            }

            TabButton {
                text: "State"
                width: implicitWidth
                contentItem: StyledText {
                    text: parent.text
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    opacity: parent.checked ? 1.0 : 0.6
                }
                background: Rectangle {
                    color: parent.checked ? Appearance.m3colors.m3accentPrimary : "transparent"
                    opacity: parent.checked ? 0.2 : 1
                    radius: 4
                }
            }

            TabButton {
                text: "Cache"
                width: implicitWidth
                contentItem: StyledText {
                    text: parent.text
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    opacity: parent.checked ? 1.0 : 0.6
                }
                background: Rectangle {
                    color: parent.checked ? Appearance.m3colors.m3accentPrimary : "transparent"
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
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        StyledText { text: "Level:"; font.pixelSize: 11 }

                        ComboBox {
                            model: ["DEBUG", "INFO", "WARN", "ERROR"]
                            currentIndex: root.selectedLogLevel
                            onCurrentIndexChanged: root.selectedLogLevel = currentIndex
                            implicitWidth: 90
                            implicitHeight: 26
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            // Depend on logGeneration for reactivity (avoids array copy)
                            text: (void(Services.Logger.logGeneration), Services.Logger.logBuffer.length) + " entries"
                            font.pixelSize: 10
                            opacity: 0.6
                        }
                    }

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
                            // Depend on logGeneration for reactivity (avoids array copy)
                            model: (void(Services.Logger.logGeneration), Services.Logger.logBuffer.filter(entry => entry.levelNum >= root.selectedLogLevel))

                            delegate: Rectangle {
                                width: logList.width
                                height: logText.implicitHeight + 4
                                color: index % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.02)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    spacing: 4

                                    Rectangle {
                                        width: 44
                                        height: 14
                                        radius: 2
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
                                            font.pixelSize: 8
                                            font.bold: true
                                            color: modelData.level === "WARN" ? "#000" : "#fff"
                                        }
                                    }

                                    StyledText {
                                        text: "[" + modelData.category + "]"
                                        font.pixelSize: 10
                                        font.family: Appearance.font.family.codeFont
                                        opacity: 0.6
                                        Layout.preferredWidth: 70
                                    }

                                    StyledText {
                                        id: logText
                                        text: modelData.message
                                        font.pixelSize: 10
                                        font.family: Appearance.font.family.codeFont
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            onCountChanged: {
                                if (atYEnd) Qt.callLater(() => positionViewAtEnd())
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
                        spacing: 10

                        StateSection {
                            title: "Booru Service"
                            Layout.fillWidth: true
                            properties: [
                                { key: "Provider", value: Services.Booru.currentProvider },
                                { key: "NSFW", value: Services.Booru.allowNsfw ? "On" : "Off" },
                                { key: "Sorting", value: Services.Booru.currentSorting || "(default)" },
                                { key: "Responses", value: Services.Booru.responses.length },
                                { key: "Pending XHR", value: Services.Booru.pendingXhrRequests.length }
                            ]
                        }

                        StateSection {
                            title: "Cache Index"
                            Layout.fillWidth: true
                            properties: [
                                { key: "Initialized", value: Services.CacheIndex.initialized ? "Yes" : "No" },
                                { key: "Files", value: Object.keys(Services.CacheIndex.index).length }
                            ]
                        }

                        StateSection {
                            title: "Video Pool"
                            Layout.fillWidth: true
                            properties: [
                                { key: "Active", value: Services.VideoPlayerPool.activeSlots.length + "/" + Services.VideoPlayerPool.maxSlots }
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

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        CacheStat { label: "Total"; value: Object.keys(Services.CacheIndex.index).length }
                        CacheStat { label: "Hi-Res"; value: root.countByPrefix("hires_") }
                        CacheStat { label: "Videos"; value: root.countByPrefix("video_") }
                        CacheStat { label: "GIFs"; value: root.countByPrefix("gif_") }
                        Item { Layout.fillWidth: true }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Appearance.m3colors.m3layerBackground1
                        radius: 4

                        ListView {
                            anchors.fill: parent
                            anchors.margins: 4
                            clip: true
                            model: Object.keys(Services.CacheIndex.index).slice(0, 50)

                            delegate: StyledText {
                                width: parent.width
                                text: modelData
                                font.pixelSize: 9
                                font.family: Appearance.font.family.codeFont
                                elide: Text.ElideMiddle
                            }
                        }
                    }
                }
            }
        }
    }

    // === Inline Components ===

    component StateSection: Rectangle {
        property string title: ""
        property var properties: []

        implicitHeight: col.implicitHeight + 12
        color: Appearance.m3colors.m3layerBackground1
        radius: 6

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            StyledText {
                text: title
                font.pixelSize: 12
                font.bold: true
            }

            Repeater {
                model: properties
                RowLayout {
                    spacing: 6
                    StyledText {
                        text: modelData.key + ":"
                        font.pixelSize: 10
                        opacity: 0.6
                        Layout.preferredWidth: 80
                    }
                    StyledText {
                        text: String(modelData.value)
                        font.pixelSize: 10
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
            font.pixelSize: 16
            font.bold: true
        }
        StyledText {
            text: label
            font.pixelSize: 10
            opacity: 0.6
        }
    }
}
