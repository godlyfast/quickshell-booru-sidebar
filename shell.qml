//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import "./modules/sidebar"
import "./modules/common"
import "./services"
import QtQuick
import Quickshell

/**
 * Booru Sidebar shell entry point.
 * Run with: qs -c /path/to/quickshell-booru-sidebar
 *
 * Or symlink to ~/.config/quickshell/booru-sidebar and run: qs -c booru-sidebar
 */
ShellRoot {
    // Sidebar state
    property bool __sidebarLeftOpen: false

    SidebarLeft {
        sidebarOpen: __sidebarLeftOpen
        onSidebarOpenChanged: __sidebarLeftOpen = sidebarOpen
    }
}
