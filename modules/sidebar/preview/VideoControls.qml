import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import "../../common"
import "../../common/widgets"

/**
 * Video playback controls: play/pause, seek bar, volume, playback speed.
 */
Rectangle {
    id: root

    property MediaPlayer player
    property AudioOutput audio

    height: 56
    color: Qt.rgba(0, 0, 0, 0.7)
    radius: Appearance.rounding.small

    // Format milliseconds to mm:ss
    function formatTime(ms) {
        if (!ms || ms < 0) return "0:00"
        var totalSeconds = Math.floor(ms / 1000)
        var minutes = Math.floor(totalSeconds / 60)
        var seconds = totalSeconds % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }

    // Cycle through playback speeds
    function cycleSpeed() {
        var speeds = [0.5, 1.0, 1.5, 2.0]
        var currentIdx = -1
        for (var i = 0; i < speeds.length; i++) {
            if (Math.abs(root.player.playbackRate - speeds[i]) < 0.01) {
                currentIdx = i
                break
            }
        }
        var nextIdx = (currentIdx + 1) % speeds.length
        root.player.playbackRate = speeds[nextIdx]
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        // Seek bar (full width)
        StyledSlider {
            id: seekSlider
            Layout.fillWidth: true
            Layout.preferredHeight: 16

            from: 0
            to: root.player ? root.player.duration : 0
            value: root.player ? root.player.position : 0

            trackColor: Qt.rgba(255, 255, 255, 0.3)
            progressColor: Appearance.m3colors.m3accentPrimary
            handleColor: "#ffffff"

            onMoved: {
                if (root.player) {
                    root.player.position = value
                }
            }
        }

        // Controls row
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Play/Pause button
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Qt.rgba(255, 255, 255, 0.2)

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: 22
                    color: "#ffffff"
                    text: root.player && root.player.playbackState === MediaPlayer.PlayingState ? "pause" : "play_arrow"
                }

                onClicked: {
                    if (!root.player) return
                    if (root.player.playbackState === MediaPlayer.PlayingState) {
                        root.player.pause()
                    } else {
                        root.player.play()
                    }
                }
            }

            // Time display
            StyledText {
                color: "#ffffff"
                font.pixelSize: Appearance.font.pixelSize.textSmall
                text: formatTime(root.player ? root.player.position : 0) + " / " + formatTime(root.player ? root.player.duration : 0)
            }

            // Spacer
            Item { Layout.fillWidth: true }

            // Volume controls
            RowLayout {
                spacing: 4

                RippleButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Qt.rgba(255, 255, 255, 0.2)

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 18
                        color: "#ffffff"
                        text: {
                            if (!root.audio) return "volume_up"
                            if (root.audio.muted || root.audio.volume === 0) return "volume_off"
                            if (root.audio.volume < 0.5) return "volume_down"
                            return "volume_up"
                        }
                    }

                    onClicked: {
                        if (root.audio) {
                            root.audio.muted = !root.audio.muted
                        }
                    }
                }

                StyledSlider {
                    id: volumeSlider
                    implicitWidth: 70
                    Layout.preferredHeight: 16

                    from: 0
                    to: 1
                    value: root.audio ? root.audio.volume : 0.5

                    trackColor: Qt.rgba(255, 255, 255, 0.3)
                    progressColor: "#ffffff"
                    handleColor: "#ffffff"
                    showHandle: false

                    onMoved: {
                        if (root.audio) {
                            root.audio.volume = value
                            if (value > 0) root.audio.muted = false
                        }
                    }
                }
            }

            // Playback speed button
            RippleButton {
                implicitWidth: 40
                implicitHeight: 28
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                colBackgroundHover: Qt.rgba(255, 255, 255, 0.2)

                contentItem: StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    color: "#ffffff"
                    font.pixelSize: Appearance.font.pixelSize.textSmall
                    text: (root.player ? root.player.playbackRate : 1) + "x"
                }

                onClicked: cycleSpeed()
            }
        }
    }
}
