import QtQuick
import QtMultimedia
import "../common"
import "../../services"

/**
 * Keyboard event handler for sidebar navigation and actions.
 * Call handleKeyPress() from the parent's Keys.onPressed handler.
 * Returns true if the event was handled.
 */
QtObject {
    id: root

    // Context references (set by parent)
    required property var sidebarState     // Preview state, navigation
    required property var animeContent     // Scroll functions, input focus
    required property var previewPanel     // Video controls, zoom
    required property var sidebarRoot      // Pinned state, hide function
    required property var sidebarBackground // Focus target
    property var clipboardProcess: null    // Optional: for URL copy

    // Multi-key sequence state
    property string pendingKey: ""

    /**
     * Handle a key press event.
     * @returns true if the event was handled
     */
    function handleKeyPress(event) {
        // Skip if input field is focused
        if (animeContent.inputField && animeContent.inputField.activeFocus) {
            if (event.key === Qt.Key_Escape) {
                animeContent.inputField.focus = false
                sidebarBackground.forceActiveFocus()
                return true
            }
            return false
        }

        // Multi-key sequences (gg)
        if (pendingKey === "g") {
            pendingKey = ""
            if (event.key === Qt.Key_G) {
                animeContent.scrollToTop()
                return true
            }
        }

        // === HELP ===
        if (event.key === Qt.Key_Question || (event.key === Qt.Key_Slash && event.modifiers & Qt.ShiftModifier)) {
            Logger.debug("Keybindings", `?: toggle help (${!sidebarState.showKeybindingsHelp})`)
            sidebarState.showKeybindingsHelp = !sidebarState.showKeybindingsHelp
            return true
        }

        // === DEBUG PANEL (F12) ===
        if (event.key === Qt.Key_F12) {
            Logger.debug("Keybindings", `F12: toggle debug panel (${!sidebarState.showDebugPanel})`)
            sidebarState.showDebugPanel = !sidebarState.showDebugPanel
            return true
        }

        // === CLOSE/QUIT ===
        if (event.key === Qt.Key_Q || event.key === Qt.Key_Escape) {
            if (sidebarState.showDebugPanel) {
                Logger.debug("Keybindings", "q/Esc: close debug panel")
                sidebarState.showDebugPanel = false
            } else if (sidebarState.showKeybindingsHelp) {
                Logger.debug("Keybindings", "q/Esc: close help")
                sidebarState.showKeybindingsHelp = false
            } else if (sidebarState.previewActive) {
                Logger.debug("Keybindings", "q/Esc: close preview")
                sidebarState.hidePreview()
            } else {
                Logger.debug("Keybindings", "q/Esc: hide sidebar")
                sidebarRoot.hide()
            }
            return true
        }

        // === TAB: Toggle preview for hovered image ===
        if (event.key === Qt.Key_Tab && Booru.hoveredBooruImage) {
            Logger.debug("Keybindings", "Tab: toggle preview for hovered image")
            Booru.hoveredBooruImage.togglePreview()
            return true
        }

        // === W: Save hovered image as wallpaper (when not in preview) ===
        if (event.key === Qt.Key_W && !sidebarState.previewActive && Booru.hoveredBooruImage) {
            Logger.debug("Keybindings", "W: save hovered image as wallpaper")
            Booru.hoveredBooruImage.saveAsWallpaper()
            return true
        }

        // === Y: Copy hovered image URL to clipboard (when not in preview) ===
        if (event.key === Qt.Key_Y && !sidebarState.previewActive && Booru.hoveredBooruImage) {
            var hoveredData = Booru.hoveredBooruImage.imageData
            if (hoveredData && hoveredData.file_url) {
                Logger.debug("Keybindings", "Y: copy hovered image URL to clipboard")
                DownloadManager.copyToClipboard(hoveredData.file_url)
            }
            return true
        }

        // === HOVERED VIDEO CONTROLS ===
        if (handleHoveredVideoControls(event)) return true

        // === BLOCK SPACE ON HOVERED NON-VIDEO IMAGES ===
        if (event.key === Qt.Key_Space && Booru.hoveredBooruImage && !sidebarState.previewActive) {
            return true
        }

        // === PREVIEW MODE CONTROLS ===
        if (sidebarState.previewActive) {
            if (handlePreviewControls(event)) return true
        }

        // === h/l: Navigate images (when preview not active) ===
        if (!sidebarState.previewActive) {
            if (event.key === Qt.Key_H) {
                sidebarState.navigatePreview(-1)
                return true
            }
            if (event.key === Qt.Key_L) {
                sidebarState.navigatePreview(1)
                return true
            }
        }

        // === VIEWPORT SCROLLING ===
        if (handleScrolling(event)) return true

        // === PAGINATION ===
        if (handlePagination(event)) return true

        // === TOGGLES ===
        if (handleToggles(event)) return true

        // === RELOAD ===
        if (handleReload(event)) return true

        // === QUICK PROVIDER SWITCH (1-9) ===
        if (handleProviderSwitch(event)) return true

        return false
    }

    // --- Helper functions for organized key handling ---

    function handleHoveredVideoControls(event) {
        const hoverPlayer = Booru.hoveredVideoPlayer
        const hasValidSource = hoverPlayer && hoverPlayer.source && hoverPlayer.source.toString().length > 0
        if (!hasValidSource) return false

        if (event.key === Qt.Key_M && Booru.hoveredAudioOutput) {
            Logger.debug("Keybindings", `M: toggle mute on hovered video (${!Booru.hoveredAudioOutput.muted})`)
            Booru.hoveredAudioOutput.muted = !Booru.hoveredAudioOutput.muted
            return true
        }
        if (event.key === Qt.Key_Right) {
            Logger.debug("Keybindings", "→: seek +5s on hovered video")
            hoverPlayer.position = Math.min(hoverPlayer.duration, hoverPlayer.position + 5000)
            return true
        }
        if (event.key === Qt.Key_Left) {
            Logger.debug("Keybindings", "←: seek -5s on hovered video")
            hoverPlayer.position = Math.max(0, hoverPlayer.position - 5000)
            return true
        }
        if (event.key === Qt.Key_Space) {
            const playing = hoverPlayer.playbackState === MediaPlayer.PlayingState
            Logger.debug("Keybindings", `Space: ${playing ? "pause" : "play"} hovered video`)
            if (playing) {
                hoverPlayer.pause()
            } else {
                hoverPlayer.play()
            }
            return true
        }
        return false
    }

    function handlePreviewControls(event) {
        const isVideo = previewPanel.isVideo

        // Video controls
        if (isVideo) {
            if (event.key === Qt.Key_Space) {
                previewPanel.togglePlayPause()
                return true
            }
            if (event.key === Qt.Key_M) {
                previewPanel.toggleMute()
                return true
            }
            if (event.key === Qt.Key_Up) {
                previewPanel.changeVolume(0.1)
                return true
            }
            if (event.key === Qt.Key_Down) {
                previewPanel.changeVolume(-0.1)
                return true
            }
            if (event.key === Qt.Key_Comma || event.key === Qt.Key_Less) {
                previewPanel.changeSpeed(-1)
                return true
            }
            if (event.key === Qt.Key_Period || event.key === Qt.Key_Greater) {
                previewPanel.changeSpeed(1)
                return true
            }
            if (event.key === Qt.Key_Left) {
                previewPanel.seekRelative(-5000)
                return true
            }
            if (event.key === Qt.Key_Right) {
                previewPanel.seekRelative(5000)
                return true
            }
        }

        // Image panning (non-video only)
        if (!isVideo) {
            const panStep = 50
            if (event.key === Qt.Key_Up) {
                previewPanel.panY += panStep
                return true
            }
            if (event.key === Qt.Key_Down) {
                previewPanel.panY -= panStep
                return true
            }
            if (event.key === Qt.Key_Left) {
                previewPanel.panX += panStep
                return true
            }
            if (event.key === Qt.Key_Right) {
                previewPanel.panX -= panStep
                return true
            }
        }

        // h/l: prev/next image
        if (event.key === Qt.Key_H) {
            sidebarState.navigatePreview(-1)
            return true
        }
        if (event.key === Qt.Key_L) {
            sidebarState.navigatePreview(1)
            return true
        }

        // Zoom controls
        if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
            previewPanel.zoomLevel = Math.min(previewPanel.maxZoom, previewPanel.zoomLevel * 1.15)
            return true
        }
        if (event.key === Qt.Key_Minus) {
            previewPanel.zoomLevel = Math.max(previewPanel.minZoom, previewPanel.zoomLevel * 0.87)
            return true
        }
        if (event.key === Qt.Key_0 || event.key === Qt.Key_R) {
            previewPanel.zoomLevel = 1.0
            previewPanel.panX = 0
            previewPanel.panY = 0
            return true
        }

        // Preview actions
        if (event.key === Qt.Key_D) {
            Logger.debug("Keybindings", "D: download preview image")
            DownloadManager.downloadImage(sidebarState.previewImageData, sidebarState.previewProvider, false)
            return true
        }
        if (event.key === Qt.Key_W) {
            Logger.debug("Keybindings", "W: save preview as wallpaper")
            DownloadManager.downloadImage(sidebarState.previewImageData, sidebarState.previewProvider, true)
            return true
        }
        if (event.key === Qt.Key_G) {
            Logger.debug("Keybindings", "G: go to post page")
            const postUrl = Booru.getPostUrl(sidebarState.previewProvider, sidebarState.previewImageData ? sidebarState.previewImageData.id : "")
            if (postUrl) Qt.openUrlExternally(postUrl)
            return true
        }
        if (event.key === Qt.Key_S) {
            Logger.debug("Keybindings", "S: open source URL")
            if (sidebarState.previewImageData && sidebarState.previewImageData.source) {
                Qt.openUrlExternally(sidebarState.previewImageData.source)
            }
            return true
        }
        if (event.key === Qt.Key_Y) {
            Logger.debug("Keybindings", "Y: copy URL to clipboard")
            if (sidebarState.previewImageData && sidebarState.previewImageData.file_url) {
                DownloadManager.copyToClipboard(sidebarState.previewImageData.file_url)
            }
            return true
        }
        if (event.key === Qt.Key_I) {
            Logger.debug("Keybindings", `I: toggle info panel (${!previewPanel.showInfoPanel})`)
            previewPanel.showInfoPanel = !previewPanel.showInfoPanel
            return true
        }

        return false
    }

    function handleScrolling(event) {
        if (event.key === Qt.Key_J) {
            animeContent.scrollDown(100)
            return true
        }
        if (event.key === Qt.Key_K) {
            animeContent.scrollUp(100)
            return true
        }
        if (event.key === Qt.Key_G && !(event.modifiers & Qt.ShiftModifier)) {
            pendingKey = "g"
            return true
        }
        if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
            animeContent.scrollToBottom()
            return true
        }
        if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
            animeContent.scrollPageDown()
            return true
        }
        if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
            animeContent.scrollPageUp()
            return true
        }
        return false
    }

    function handlePagination(event) {
        if (event.key === Qt.Key_N && !(event.modifiers & Qt.ShiftModifier)) {
            animeContent.loadNextPage()
            return true
        }
        if (event.key === Qt.Key_N && (event.modifiers & Qt.ShiftModifier)) {
            animeContent.loadPrevPage()
            return true
        }
        return false
    }

    function handleToggles(event) {
        if (event.key === Qt.Key_P) {
            if (event.modifiers & Qt.ShiftModifier) {
                Logger.debug("Keybindings", `Shift+P: toggle pin (${!sidebarRoot.pinned})`)
                sidebarRoot.pinned = !sidebarRoot.pinned
            } else {
                Logger.debug("Keybindings", "P: open provider picker")
                sidebarState.showPickerDialog = true
            }
            return true
        }
        if (event.key === Qt.Key_X) {
            Logger.debug("Keybindings", `X: toggle NSFW (${!Booru.allowNsfw})`)
            Booru.allowNsfw = !Booru.allowNsfw
            return true
        }
        if (event.key === Qt.Key_I) {
            Logger.debug("Keybindings", "I: focus input")
            animeContent.focusInput()
            return true
        }
        return false
    }

    function handleReload(event) {
        if (event.key === Qt.Key_R && !sidebarState.previewActive) {
            if (event.modifiers & Qt.ShiftModifier) {
                animeContent.cleanCacheAndReload()
            } else {
                animeContent.reloadCurrentPage()
            }
            return true
        }
        return false
    }

    function handleProviderSwitch(event) {
        let numKey = -1
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            numKey = event.key - Qt.Key_1
        }
        if (numKey >= 0) {
            const favorites = (ConfigOptions.booru && ConfigOptions.booru.favorites)
                ? ConfigOptions.booru.favorites
                : Booru.providerList.slice(0, 9)
            if (numKey < favorites.length) {
                Logger.debug("Keybindings", `${numKey + 1}: switch to ${favorites[numKey]}`)
                Booru.setProvider(favorites[numKey])
            }
            return true
        }
        return false
    }
}
