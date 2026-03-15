import QtQuick
import Quickshell
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {

    property QtObject appearance: QtObject {
        property int fakeScreenRounding: 1 // 0: None | 1: Always | 2: When not fullscreen
    }

    property QtObject overview: QtObject {
        property real scale: 0.15 // Relative to screen size
        property real numOfRows: 2
        property real numOfCols: 5
        property bool showXwaylandIndicator: true
        property real windowPadding: 6 
        property real position: 1 // 0: top | 1: middle | 2: bottom
        property real workspaceNumberSize: 120 // Set 0, dynamic calculation based on monitor size
        property bool showAllMonitors: true // Show windows from all monitors
    }

    property QtObject resources: QtObject {
        property int updateInterval: 3000
    }

    property QtObject hacks: QtObject {
        property int arbitraryRaceConditionDelay: 20 // milliseconds
    }

    property QtObject search: QtObject {
    property bool searchEnabled: false
    property int nonAppResultDelay: 30 // This prevents lagging when typing
    property QtObject prefix: QtObject {
            property string action: "/"
            property string clipboard: ";"
            property string emojis: ":"
        }
    }
    
    property QtObject bar: QtObject {
    property bool bottom: false // Instead of top
    }

    property QtObject booru: QtObject {
        property string filenameTemplate: "%website% %id% - %artist%.%ext%"
        property string gelbooruApiKey: ""
        property string gelbooruUserId: ""
        property string rule34ApiKey: ""
        property string rule34UserId: ""
        property string wallhavenApiKey: ""
        property string danbooruLogin: ""
        property string danbooruApiKey: ""
        // Last used provider (restored on startup)
        property string activeProvider: "wallhaven"
        // Wallhaven minimum resolution filter (e.g., "3840x2160", "2560x1440", "any")
        property string wallhavenResolution: "3840x2160"
        // Provider picker favorites (1-9 keys)
        property var favorites: ["yandere", "wallhaven", "danbooru", "gelbooru", "konachan", "e621", "safebooru", "aibooru", "sankaku"]
        // Provider usage counts for popularity sorting
        property var providerUsage: ({})
        // Per-provider settings: { "provider": { sorting: "", ageFilter: "", nsfw: false } }
        property var providerSettings: ({})
        // Video player pool settings
        // Set to 0 to disable sidebar video playback entirely (saves resources)
        // Videos will only play in the preview panel (single player instance)
        property int maxSidebarPlayers: 0
        property bool videoAutoplay: false
    }
}
