pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick

/**
 * Centralized z-order constants for consistent layer stacking.
 * Higher values appear above lower values.
 */
QtObject {
    id: root

    // Base layer - normal content
    readonly property int base: 0

    // UI indicators (hover states, selection highlights)
    readonly property int indicator: 5

    // Floating buttons (pin, settings)
    readonly property int button: 10

    // Overlays (dialogs, panels)
    readonly property int overlay: 100

    // Modal dialogs (confirmation, critical alerts)
    readonly property int modal: 200

    // Debug UI (always on top when active)
    readonly property int debug: 300

    // Hover detection (must be highest to capture events)
    readonly property int hoverDetector: 999
}
