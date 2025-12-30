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

    // Force ConfigLoader to initialize and load config.json
    Component.onCompleted: {
        ConfigLoader.loadConfig()
    }

    SidebarLeft {
        sidebarOpen: __sidebarLeftOpen
        onSidebarOpenChanged: __sidebarLeftOpen = sidebarOpen
    }
}
