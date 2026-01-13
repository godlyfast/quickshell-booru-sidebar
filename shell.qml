//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import "./modules/sidebar"
import "./modules/common"
import "./services"
import QtQuick
import Quickshell

/**
 * Sidebar shell entry point.
 * Run with: qs -c sidebar
 */
ShellRoot {
    // GlobalStates must be defined here since it's a singleton
    property bool __sidebarLeftOpen: false

    // Auto-exit timer: kill process after configured minutes of being hidden
    // Set idleExitMinutes to 0 in config.json to disable
    Timer {
        id: idleExitTimer
        interval: ConfigOptions.booru.idleExitMinutes * 60 * 1000
        repeat: false
        running: false
        onTriggered: {
            Logger.info("Shell", `Idle timeout reached (${ConfigOptions.booru.idleExitMinutes} minutes hidden) - exiting`)
            Qt.quit()
        }
    }

    // Helper to start idle timer only if enabled
    function startIdleTimerIfEnabled() {
        if (ConfigOptions.booru.idleExitMinutes > 0) {
            Logger.debug("Shell", `Sidebar hidden - starting ${ConfigOptions.booru.idleExitMinutes} minute idle exit timer`)
            idleExitTimer.restart()
        }
    }

    // Track sidebar visibility changes to manage idle timer
    on__SidebarLeftOpenChanged: {
        if (__sidebarLeftOpen) {
            // Sidebar opened - stop idle timer
            if (idleExitTimer.running) {
                Logger.debug("Shell", "Sidebar opened - cancelling idle exit timer")
                idleExitTimer.stop()
            }
        } else {
            // Sidebar hidden - start idle timer if enabled
            startIdleTimerIfEnabled()
        }
    }

    // Force ConfigLoader to initialize and load config.json
    Component.onCompleted: {
        ConfigLoader.loadConfig()
        // Start idle timer if sidebar starts hidden (default state)
        if (!__sidebarLeftOpen) {
            startIdleTimerIfEnabled()
        }
    }

    SidebarLeft {
        sidebarOpen: __sidebarLeftOpen
        onSidebarOpenChanged: __sidebarLeftOpen = sidebarOpen
    }
}
