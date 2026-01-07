pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Singleton service for tracking hovered UI elements.
 * Extracted from Booru.qml to reduce god-object responsibilities.
 *
 * Used by:
 *   - BooruImage.qml: Sets hovered references on mouse enter/exit
 *   - KeybindingHandler.qml: Reads references for keyboard shortcuts (TAB, W, Y, M, Space)
 */
Singleton {
    id: root

    // Currently hovered video player (for Space/M keys)
    property var hoveredVideoPlayer: null
    property var hoveredAudioOutput: null

    // Currently hovered image component (for TAB/W/Y/Space keys)
    property var hoveredBooruImage: null

    // Clear all hover state (called when sidebar closes)
    function clear() {
        hoveredVideoPlayer = null
        hoveredAudioOutput = null
        hoveredBooruImage = null
    }
}
