pragma Singleton
pragma ComponentBehavior: Bound

import "../modules/common"
import "../modules/common/utils"
import QtQuick
import Quickshell
import Quickshell.Io

// Import API family mappers to reduce code duplication
import "BooruApiTypes.js" as ApiTypes

/**
 * A service for interacting with various booru APIs.
 * Simplified version adapted from end-4/dots-hyprland
 */
Singleton {
    id: root

    Component.onCompleted: {
        console.log("=== BOORU SERVICE LOADED ===")
        console.log("Provider count: " + providerList.length)
        console.log("Providers: " + providerList.join(", "))
    }

    // Restore provider settings after config is loaded
    Connections {
        target: ConfigLoader
        function onConfigLoaded() {
            var savedProvider = ConfigOptions.booru.activeProvider
            if (savedProvider && savedProvider.length > 0 && providerList.indexOf(savedProvider) !== -1) {
                loadingSettings = true
                currentProvider = savedProvider
                loadProviderSettings(savedProvider)
                loadingSettings = false
                console.log("[Booru] Restored active provider:", savedProvider)
            }
            // Now allow property change handlers to save
            configReady = true
        }
    }

    property Component booruResponseDataComponent: BooruResponseData {}

    signal tagSuggestion(string query, var suggestions)
    signal responseFinished()
    signal providerUsageUpdated()
    signal stopAllVideos()

    // Hovered video player tracking - for keyboard controls on grid videos
    property var hoveredVideoPlayer: null
    property var hoveredAudioOutput: null
    // Hovered image tracking - for TAB key preview toggle
    property var hoveredBooruImage: null

    property string failMessage: "That didn't work. Tips:\n- Check your tags and NSFW settings\n- If you don't have a tag in mind, type a page number"
    property var responses: []
    property int runningRequests: 0
    property var pendingXhrRequests: []  // Track XHR for abort on clear

    // Pagination state (single page at a time)
    property int currentPage: 1
    property var currentTags: []
    property string defaultUserAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
    property var providerList: {
        var list = Object.keys(providers).filter(function(provider) {
            // Include providers with API or useGrabberFallback
            return provider !== "system" && (providers[provider].api || providers[provider].useGrabberFallback)
        })
        console.log("[Booru] providerList: " + list.join(", "))
        return list
    }

    // Persistent state
    property string currentProvider: "wallhaven"
    property bool allowNsfw: false
    property int limit: 20

    // Wallhaven sorting options (legacy, kept for backwards compatibility)
    property string wallhavenSorting: "toplist"  // date_added, relevance, random, views, favorites, toplist
    property string wallhavenOrder: "desc"       // desc, asc
    property var wallhavenSortOptions: ["toplist", "random", "date_added", "relevance", "views", "favorites"]

    // Wallhaven toplist time range (only applies when sorting=toplist)
    property string wallhavenTopRange: "1M"  // 1d, 3d, 1w, 1M, 3M, 6M, 1y
    readonly property var topRangeOptions: ["1d", "3d", "1w", "1M", "3M", "6M", "1y"]

    // Wallhaven minimum resolution filter
    property string wallhavenResolution: "3840x2160"  // Default: 4K
    readonly property var resolutionOptions: ["1280x720", "1920x1080", "2560x1440", "3840x2160", "any"]
    readonly property var resolutionLabels: ({"1280x720": "720p", "1920x1080": "1080p", "2560x1440": "1440p", "3840x2160": "4K", "any": "Any"})

    // Unified age filter (prevents timeout on score/favcount sorting)
    // Works with Danbooru-compatible APIs: danbooru, aibooru, yandere, konachan
    property string ageFilter: "1month"  // 1day, 1week, 1month, 3months, 1year, any
    property alias danbooruAge: root.ageFilter  // Backwards compatibility
    readonly property var ageFilterOptions: ["1day", "1week", "1month", "3months", "1year", "any"]
    readonly property var ageFilterLabels: ({"1day": "1d", "1week": "1w", "1month": "1M", "3months": "3M", "1year": "1y", "any": "All"})
    // Backwards compatibility aliases
    readonly property alias danbooruAgeOptions: root.ageFilterOptions
    readonly property alias danbooruAgeLabels: root.ageFilterLabels
    // Providers that support the age: metatag
    // Only providers that support the age: metatag (Danbooru/Moebooru with date indexing)
    // Note: sakugabooru and 3dbooru do NOT support age: metatag despite being Moebooru
    readonly property var ageFilterProviders: ["danbooru", "aibooru", "yandere", "konachan"]
    property bool providerSupportsAgeFilter: ageFilterProviders.indexOf(currentProvider) !== -1

    // Universal sorting - works with all providers that support it
    property string currentSorting: ""  // Empty = provider default

    // Debounce timer for saving settings on property changes
    Timer {
        id: settingsSaveTimer
        interval: 500  // Save after 500ms of no changes
        repeat: false
        onTriggered: {
            saveProviderSettings()
            ConfigLoader.saveConfig()
        }
    }

    // Track if we're loading settings to avoid save loops
    property bool loadingSettings: false
    // Don't save until config has been loaded at least once
    property bool configReady: false

    onCurrentSortingChanged: {
        if (configReady && !loadingSettings && currentProvider.length > 0) {
            settingsSaveTimer.restart()
        }
    }

    onAgeFilterChanged: {
        if (configReady && !loadingSettings && currentProvider.length > 0) {
            settingsSaveTimer.restart()
        }
    }

    onAllowNsfwChanged: {
        if (configReady && !loadingSettings && currentProvider.length > 0) {
            settingsSaveTimer.restart()
        }
    }

    // Per-provider sort options (empty array = no sorting support)
    // Based on API documentation for each booru type
    property var providerSortOptions: ({
        // Moebooru (order: metatag) - yande.re, konachan, sakugabooru, 3dbooru
        "yandere": ["score", "score_asc", "favcount", "random", "rank", "id", "id_desc", "change", "comment", "mpixels", "landscape", "portrait"],
        "konachan": ["score", "score_asc", "favcount", "random", "rank", "id", "id_desc", "change", "comment", "mpixels", "landscape", "portrait"],
        "sakugabooru": ["score", "score_asc", "favcount", "random", "rank", "id", "id_desc", "change", "comment", "mpixels", "landscape", "portrait"],
        "3dbooru": ["score", "score_asc", "favcount", "random", "rank", "id", "id_desc", "change", "comment", "mpixels", "landscape", "portrait"],

        // Danbooru (order: metatag)
        "danbooru": ["rank", "score", "favcount", "random", "id", "id_desc", "change", "comment", "comment_bumped", "note", "mpixels", "landscape", "portrait"],
        "aibooru": ["rank", "score", "favcount", "random", "id", "id_desc", "change", "comment", "comment_bumped", "note", "mpixels", "landscape", "portrait"],

        // e621 (order: metatag) - e926 is now a mirror of e621
        "e621": ["score", "favcount", "random", "id", "id_asc", "comment_count", "tagcount", "mpixels", "filesize", "landscape", "portrait"],

        // Gelbooru-style (sort: metatag)
        "gelbooru": ["score", "score:asc", "score:desc", "id", "id:asc", "updated", "random"],
        "safebooru": ["score", "score:asc", "score:desc", "id", "id:asc", "updated", "random"],
        "rule34": ["score", "score:asc", "score:desc", "id", "id:asc", "updated", "random"],
        "xbooru": ["score", "score:asc", "score:desc", "id", "id:asc", "updated", "random"],
        "tbib": ["score", "score:asc", "score:desc", "id", "id:asc", "updated"],
        "hypnohub": ["score", "score:asc", "score:desc", "id", "id:asc", "updated"],

        // Wallhaven (URL params)
        "wallhaven": ["toplist", "random", "date_added", "relevance", "views", "favorites", "hot"],

        // Zerochan (s param)
        "zerochan": ["id", "fav"],

        // Sankaku (order: metatag) - NOTE: favcount causes API timeout errors
        "sankaku": ["popularity", "date", "quality", "score", "random", "id", "id_asc", "recently_favorited", "recently_voted"],
        "idol_sankaku": ["popularity", "date", "quality", "score", "random", "id", "id_asc", "recently_favorited", "recently_voted"],

        // Derpibooru (sf param)
        "derpibooru": ["score", "wilson_score", "relevance", "random", "created_at", "updated_at", "first_seen_at", "width", "height", "comment_count", "tag_count"],

        // No sorting support
        "waifu.im": [],
        "nekos_best": [],
        "paheal": []
    })

    // Get sort options for current provider
    function getSortOptions() {
        var options = providerSortOptions[currentProvider]
        return options ? options : []
    }

    // Check if current provider supports sorting
    property bool providerSupportsSorting: getSortOptions().length > 0

    // SFW-only providers where NSFW toggle doesn't apply
    // safebooru.org, nekos.best, zerochan are all SFW-only by design
    // Note: konachan and e926 are now determined by mirror selection
    property var sfwOnlyProviders: ["safebooru", "nekos_best", "zerochan"]
    // NSFW-only providers - rating filter doesn't apply (all content is NSFW)
    property var nsfwOnlyProviders: ["rule34", "xbooru", "tbib", "paheal", "hypnohub"]
    // Provider supports NSFW if: not in sfwOnlyProviders AND current mirror isn't SFW-only
    property bool providerSupportsNsfw: sfwOnlyProviders.indexOf(currentProvider) === -1 && !currentMirrorIsSfwOnly(currentProvider)

    // Gelbooru API credentials (configured in config.json under "booru")
    // Get your key at: https://gelbooru.com/index.php?page=account&s=options
    property string gelbooruApiKey: (ConfigOptions.booru && ConfigOptions.booru.gelbooruApiKey) ? ConfigOptions.booru.gelbooruApiKey : ""
    property string gelbooruUserId: (ConfigOptions.booru && ConfigOptions.booru.gelbooruUserId) ? ConfigOptions.booru.gelbooruUserId : ""

    // Rule34 API credentials (configured in config.json under "booru")
    // Get your key at: https://rule34.xxx/index.php?page=account&s=options
    property string rule34ApiKey: (ConfigOptions.booru && ConfigOptions.booru.rule34ApiKey) ? ConfigOptions.booru.rule34ApiKey : ""
    property string rule34UserId: (ConfigOptions.booru && ConfigOptions.booru.rule34UserId) ? ConfigOptions.booru.rule34UserId : ""

    // Wallhaven API key (required for NSFW content)
    // Get your key at: https://wallhaven.cc/settings/account
    property string wallhavenApiKey: (ConfigOptions.booru && ConfigOptions.booru.wallhavenApiKey) ? ConfigOptions.booru.wallhavenApiKey : ""

    // Providers that require curl (User-Agent header needed, XHR can't set it)
    property var curlProviders: ["zerochan"]

    // Danbooru API credentials (higher rate limits, access to restricted content)
    // Get your key at: https://danbooru.donmai.us/profile → API Key
    property string danbooruLogin: (ConfigOptions.booru && ConfigOptions.booru.danbooruLogin) ? ConfigOptions.booru.danbooruLogin : ""
    property string danbooruApiKey: (ConfigOptions.booru && ConfigOptions.booru.danbooruApiKey) ? ConfigOptions.booru.danbooruApiKey : ""

    // Grabber filename template for downloads
    // Tokens: %website%, %id%, %md5%, %artist%, %copyright%, %character%, %ext%
    property string filenameTemplate: (ConfigOptions.booru && ConfigOptions.booru.filenameTemplate) ? ConfigOptions.booru.filenameTemplate : "%website% %id%.%ext%"

    // Grabber source names for each provider (used for CLI downloads)
    // Maps our provider keys to Grabber's expected source names
    readonly property var grabberSources: ({
        "yandere": "yande.re",
        "konachan": "konachan.com",      // Uses .com mirror for Grabber
        "sakugabooru": "www.sakugabooru.com",
        "danbooru": "danbooru.donmai.us",
        "gelbooru": "gelbooru.com",
        "safebooru": "safebooru.org",
        "rule34": "api.rule34.xxx",
        "e621": "e621.net",
        "wallhaven": "wallhaven.cc",
        "xbooru": "xbooru.com",
        "hypnohub": "hypnohub.net",
        "aibooru": "aibooru.online",
        "zerochan": "www.zerochan.net",
        "sankaku": "chan.sankakucomplex.com",
        "idol_sankaku": "idol.sankakucomplex.com",
        "derpibooru": "derpibooru.org",
        "3dbooru": "behoimi.org",
        "anime_pictures": "anime-pictures.net",
        "e_shuushuu": "e-shuushuu.net"
        // Note: waifu.im, nekos_best, tbib, paheal not supported by Grabber
    })

    // Check if provider supports Grabber downloads
    function getGrabberSource(provider) {
        return grabberSources[provider] ? grabberSources[provider] : null
    }

    // Get the booru post URL for viewing on the site
    function getPostUrl(provider, imageId) {
        var p = providers[provider]
        if (!p || !imageId) return ""

        var baseUrl = p.url
        var apiType = p.apiType || ""

        // URL patterns by API type
        switch (apiType) {
            case "moebooru":
                return baseUrl + "/post/show/" + imageId
            case "danbooru":
                return baseUrl + "/posts/" + imageId
            case "gelbooru":
            case "gelbooruNsfw":
                return baseUrl + "/index.php?page=post&s=view&id=" + imageId
            case "e621":
                return baseUrl + "/posts/" + imageId
            case "wallhaven":
                return baseUrl + "/w/" + imageId
            case "sankaku":
                return baseUrl + "/post/show/" + imageId
            case "shimmie":
                return baseUrl + "/post/view/" + imageId
            case "philomena":
                return baseUrl + "/images/" + imageId
            case "zerochan":
                return baseUrl + "/" + imageId
            default:
                // waifuIm, nekosBest don't have post pages
                return ""
        }
    }

    // Providers that should use Grabber for API requests (bypasses Cloudflare)
    // Toggle via /grabber command
    property bool useGrabberFallback: true
    // Providers that prefer Grabber over direct API (bypasses User-Agent/Cloudflare issues)
    // Note: zerochan requires authentication, not currently supported
    property var grabberPreferredProviders: ["danbooru"]

    // Check if provider should use Grabber for requests
    function shouldUseGrabber(provider) {
        if (!useGrabberFallback) return false
        // Grabber-only providers always use Grabber
        if (providers[provider] && providers[provider].useGrabberFallback) return true
        // Check if this provider is in the preferred list and has a Grabber source
        return grabberPreferredProviders.indexOf(provider) !== -1 && grabberSources[provider]
    }

    // Component for creating GrabberRequest instances
    property Component grabberRequestComponent: Component {
        GrabberRequest {}
    }

    // Mirror system - tracks current mirror selection per provider
    property var currentMirrors: ({})

    // Check if provider has mirrors
    function providerHasMirrors(provider) {
        return providers[provider] && providers[provider].mirrors ? true : false
    }

    // Get list of mirror keys for a provider
    function getMirrorList(provider) {
        if (!providerHasMirrors(provider)) return []
        return Object.keys(providers[provider].mirrors)
    }

    // Get current mirror key for a provider (defaults to first mirror)
    function getCurrentMirror(provider) {
        if (!providerHasMirrors(provider)) return null
        var mirrors = providers[provider].mirrors
        var current = currentMirrors[provider]
        if (current && mirrors[current]) return current
        return Object.keys(mirrors)[0]
    }

    // Set mirror for a provider
    function setMirror(provider, mirrorKey) {
        if (!providerHasMirrors(provider)) return
        if (!providers[provider].mirrors[mirrorKey]) return
        var newMirrors = JSON.parse(JSON.stringify(currentMirrors))
        newMirrors[provider] = mirrorKey
        currentMirrors = newMirrors
        console.log("[Booru] Mirror set: " + provider + " -> " + mirrorKey)
    }

    // Get effective API URL for provider (respects mirror selection)
    function getEffectiveApiUrl(provider) {
        var p = providers[provider]
        if (!p) return ""
        if (p.mirrors) {
            var mirror = getCurrentMirror(provider)
            return p.mirrors[mirror].api
        }
        return p.api
    }

    // Get effective tag search URL for provider (respects mirror selection)
    function getEffectiveTagApiUrl(provider) {
        var p = providers[provider]
        if (!p) return ""
        if (p.mirrors) {
            var mirror = getCurrentMirror(provider)
            var m = p.mirrors[mirror]
            return m.tagApi ? m.tagApi : p.tagSearchTemplate
        }
        return p.tagSearchTemplate ? p.tagSearchTemplate.split("?")[0] : ""
    }

    // Check if current mirror is SFW-only
    function currentMirrorIsSfwOnly(provider) {
        if (!providerHasMirrors(provider)) return false
        var mirror = getCurrentMirror(provider)
        return providers[provider].mirrors[mirror].sfwOnly === true
    }

    property var providers: {
        "system": { "name": "System" },
        "yandere": {
            "name": "yande.re",
            "url": "https://yande.re",
            "api": "https://yande.re/post.json",
            "apiType": "moebooru",
            "description": "All-rounder | Good quality, decent quantity",
            "tagSearchTemplate": "https://yande.re/tag.json?order=count&limit=10&name={{query}}*"
        },
        "konachan": {
            "name": "Konachan",
            "url": "https://konachan.net",
            "api": "https://konachan.net/post.json",
            "apiType": "moebooru",
            "description": "For desktop wallpapers | Good quality",
            "mirrors": {
                "konachan.net": {
                    "url": "https://konachan.net",
                    "api": "https://konachan.net/post.json",
                    "tagApi": "https://konachan.net/tag.json",
                    "description": "SFW-focused",
                    "sfwOnly": true
                },
                "konachan.com": {
                    "url": "https://konachan.com",
                    "api": "https://konachan.com/post.json",
                    "tagApi": "https://konachan.com/tag.json",
                    "description": "More NSFW",
                    "sfwOnly": false
                }
            },
            "tagSearchTemplate": "https://konachan.net/tag.json?order=count&limit=10&name={{query}}*"
        },
        "sakugabooru": {
            "name": "Sakugabooru",
            "url": "https://www.sakugabooru.com",
            "api": "https://www.sakugabooru.com/post.json",
            "apiType": "moebooru",
            "description": "Animation sakuga clips | Video-focused",
            "tagSearchTemplate": "https://www.sakugabooru.com/tag.json?order=count&limit=10&name={{query}}*"
        },
        "danbooru": {
            "name": "Danbooru",
            "url": "https://danbooru.donmai.us",
            "api": "https://danbooru.donmai.us/posts.json",
            "apiType": "danbooru",
            "description": "The popular one | Best quantity, quality varies",
            "mirrors": {
                "danbooru.donmai.us": {
                    "url": "https://danbooru.donmai.us",
                    "api": "https://danbooru.donmai.us/posts.json",
                    "tagApi": "https://danbooru.donmai.us/tags.json",
                    "description": "Main site",
                    "sfwOnly": false
                },
                "safebooru.donmai.us": {
                    "url": "https://safebooru.donmai.us",
                    "api": "https://safebooru.donmai.us/posts.json",
                    "tagApi": "https://safebooru.donmai.us/tags.json",
                    "description": "SFW-only",
                    "sfwOnly": true
                }
            },
            "tagSearchTemplate": "https://danbooru.donmai.us/tags.json?limit=10&search[name_matches]={{query}}*"
        },
        "gelbooru": {
            "name": "Gelbooru",
            "url": "https://gelbooru.com",
            "api": "https://gelbooru.com/index.php?page=dapi&s=post&q=index&json=1",
            "apiType": "gelbooru",
            "description": "Great quantity, lots of NSFW, quality varies",
            "tagSearchTemplate": "https://gelbooru.com/index.php?page=dapi&s=tag&q=index&json=1&orderby=count&limit=10&name_pattern={{query}}%"
        },
        "waifu.im": {
            "name": "waifu.im",
            "url": "https://waifu.im",
            "api": "https://api.waifu.im/search",
            "apiType": "waifuIm",
            "description": "Waifus only | Excellent quality, limited quantity",
            "tagSearchTemplate": "https://api.waifu.im/tags"
        },
        "safebooru": {
            "name": "Safebooru",
            "url": "https://safebooru.org",
            "api": "https://safebooru.org/index.php?page=dapi&s=post&q=index&json=1",
            "apiType": "gelbooru",
            "description": "SFW only | Family-friendly anime images",
            "tagSearchTemplate": "https://safebooru.org/autocomplete.php?q={{query}}",
            // Autocomplete format: {label: "tag (count)", value: "tag"}
            "tagMapFunc": function(response) {
                if (!response || !Array.isArray(response)) return []
                var result = []
                for (var i = 0; i < response.length; i++) {
                    var item = response[i]
                    var count = 0
                    if (item && item.label) {
                        var match = item.label.match(/\((\d+)\)/)
                        if (match && match[1]) count = parseInt(match[1])
                    }
                    result.push({ name: (item && item.value) ? item.value : "", count: count })
                }
                return result
            }
        },
        "rule34": {
            "name": "Rule34",
            "url": "https://rule34.xxx",
            "api": "https://api.rule34.xxx/index.php?page=dapi&s=post&q=index&json=1",
            "apiType": "gelbooruNsfw",
            "description": "NSFW | Requires API key (rule34.xxx/account)",
            "tagSearchTemplate": "https://api.rule34.xxx/autocomplete.php?q={{query}}",
            // Autocomplete format: {label: "tag (count)", value: "tag"}
            "tagMapFunc": function(response) {
                if (!response || !Array.isArray(response)) return []
                var result = []
                for (var i = 0; i < response.length; i++) {
                    var item = response[i]
                    var count = 0
                    if (item && item.label) {
                        var match = item.label.match(/\((\d+)\)/)
                        if (match && match[1]) count = parseInt(match[1])
                    }
                    result.push({ name: item.value || "", count: count })
                }
                return result
            }
        },
        "e621": {
            "name": "e621",
            "url": "https://e621.net",
            "api": "https://e621.net/posts.json",
            "apiType": "e621",
            "description": "Furry artwork | NSFW, requires User-Agent",
            "mirrors": {
                "e621.net": {
                    "url": "https://e621.net",
                    "api": "https://e621.net/posts.json",
                    "tagApi": "https://e621.net/tags.json",
                    "description": "Main site (NSFW)",
                    "sfwOnly": false
                },
                "e926.net": {
                    "url": "https://e926.net",
                    "api": "https://e926.net/posts.json",
                    "tagApi": "https://e926.net/tags.json",
                    "description": "SFW-only mirror",
                    "sfwOnly": true
                }
            },
            "tagSearchTemplate": "https://e621.net/tags.json?limit=10&search[name_matches]={{query}}*&search[order]=count"
        },
        "wallhaven": {
            "name": "Wallhaven",
            "url": "https://wallhaven.cc",
            "api": "https://wallhaven.cc/api/v1/search",
            "apiType": "wallhaven",
            "description": "Desktop wallpapers | High quality, all resolutions",
            "tagSearchTemplate": "https://wallhaven.cc/api/v1/search?q={{query}}&sorting=relevance"
        },
        "nekos_best": {
            "name": "nekos.best",
            "url": "https://nekos.best",
            "api": "https://nekos.best/api/v2/neko",
            "apiType": "nekosBest",
            "description": "Anime characters | Random images, high quality"
        },
        "xbooru": {
            "name": "Xbooru",
            "url": "https://xbooru.com",
            "api": "https://xbooru.com/index.php?page=dapi&s=post&q=index&json=1",
            "apiType": "gelbooruNsfw",
            "description": "Hentai focused imageboard"
        },
        "tbib": {
            "name": "TBIB",
            "url": "https://tbib.org",
            "api": "https://tbib.org/index.php?page=dapi&s=post&q=index&json=1",
            "description": "The Big ImageBoard | 8M+ images aggregator",
            "mapFunc": (response) => {
                if (!response || !Array.isArray(response)) return []
                var result = []
                for (var i = 0; i < response.length; i++) {
                    var item = response[i]
                    if (!item || !item.directory || !item.image) continue
                    var fileUrl = "https://tbib.org/images/" + item.directory + "/" + item.image
                    var previewUrl = "https://tbib.org/thumbnails/" + item.directory + "/thumbnail_" + (item.hash || "") + ".jpg"
                    result.push({
                        "id": item.id,
                        "width": item.width || 0,
                        "height": item.height || 0,
                        "aspect_ratio": (item.width && item.height) ? item.width / item.height : 1,
                        "tags": item.tags || "",
                        "rating": item.rating ? item.rating.charAt(0) : "q",
                        "is_nsfw": (item.rating !== "safe"),
                        "md5": item.hash || "",
                        "preview_url": previewUrl,
                        "sample_url": fileUrl,
                        "file_url": fileUrl,
                        "file_ext": item.image.split('.').pop(),
                        "source": fileUrl
                    })
                }
                return result
            }
        },
        "paheal": {
            "name": "Paheal Rule34",
            "url": "https://rule34.paheal.net",
            "api": "https://rule34.paheal.net/api/danbooru/find_posts",
            "apiType": "shimmie",
            "description": "Rule34 (Shimmie) | 3.5M+ images",
            "isXml": true
        },
        "hypnohub": {
            "name": "Hypnohub",
            "url": "https://hypnohub.net",
            "api": "https://hypnohub.net/index.php?page=dapi&s=post&q=index&json=1",
            "apiType": "gelbooruNsfw",
            "description": "Hypnosis/mind control themed | ~92k images"
        },
        "aibooru": {
            "name": "AIBooru",
            "url": "https://aibooru.online",
            "api": "https://aibooru.online/posts.json",
            "apiType": "danbooru",
            "description": "AI-generated art | ~150k images",
            "tagSearchTemplate": "https://aibooru.online/tags.json?limit=10&search[name_matches]={{query}}*"
        },
        "zerochan": {
            "name": "Zerochan",
            "url": "https://www.zerochan.net",
            "api": "https://www.zerochan.net",
            "apiType": "zerochan",
            "description": "High-quality anime art | SFW-focused"
            // Note: Zerochan requires User-Agent header, see constructRequestUrl
        },
        "sankaku": {
            "name": "Sankaku Channel",
            "url": "https://chan.sankakucomplex.com",
            "api": "https://sankakuapi.com/v2/posts",
            "apiType": "sankaku",
            "description": "Large anime imageboard | Mixed content",
            "tagSearchTemplate": "https://sankakuapi.com/v2/tags?name={{query}}*&limit=10"
        },
        "idol_sankaku": {
            "name": "Idol Sankaku",
            "url": "https://idol.sankakucomplex.com",
            "api": "https://sankakuapi.com/v2/posts",
            "apiType": "sankaku",
            "description": "Japanese idols | Real photos",
            "tagSearchTemplate": "https://sankakuapi.com/v2/tags?name={{query}}*&limit=10"
        },
        "derpibooru": {
            "name": "Derpibooru",
            "url": "https://derpibooru.org",
            "api": "https://derpibooru.org/api/v1/json/search/images",
            "apiType": "philomena",
            "description": "MLP artwork | Philomena engine",
            "tagSearchTemplate": "https://derpibooru.org/api/v1/json/search/tags?q={{query}}*"
        },
        "3dbooru": {
            "name": "3Dbooru",
            "url": "https://behoimi.org",
            "api": "https://behoimi.org/post/index.json",
            "apiType": "moebooru",
            "description": "3D rendered art | Moebooru fork",
            "tagSearchTemplate": "https://behoimi.org/tag/index.json?order=count&limit=10&name={{query}}*"
        },
        "anime_pictures": {
            "name": "Anime-Pictures",
            "url": "https://anime-pictures.net",
            "description": "Curated anime wallpapers | Grabber-only",
            "useGrabberFallback": true
        },
        "e_shuushuu": {
            "name": "E-Shuushuu",
            "url": "https://e-shuushuu.net",
            "description": "Cute anime art | Grabber-only",
            "useGrabberFallback": true
        }
    }

    function getWorkingImageSource(url) {
        if (!url) return null;
        if (url.includes('pximg.net')) {
            var filename = url.substring(url.lastIndexOf('/') + 1)
            var artworkId = filename.replace(/_p\d+\.(png|jpg|jpeg|gif)$/, '')
            return "https://www.pixiv.net/en/artworks/" + artworkId
        }
        return url;
    }

    // Get the mapFunc for a provider, using API family mappers when available
    function getProviderMapFunc(providerKey) {
        var provider = providers[providerKey]
        if (!provider) return null
        // Use inline mapFunc if defined (provider override)
        if (provider.mapFunc) return provider.mapFunc
        // Otherwise use API family mapper
        if (provider.apiType && ApiTypes.BooruApiTypes[provider.apiType]) {
            return ApiTypes.BooruApiTypes[provider.apiType].mapFunc
        }
        return null
    }

    // Get the tagMapFunc for a provider
    function getProviderTagMapFunc(providerKey) {
        var provider = providers[providerKey]
        if (!provider) return null
        // Use inline tagMapFunc if defined
        if (provider.tagMapFunc) return provider.tagMapFunc
        // Otherwise use API family mapper
        if (provider.apiType && ApiTypes.BooruApiTypes[provider.apiType]) {
            return ApiTypes.BooruApiTypes[provider.apiType].tagMapFunc
        }
        return null
    }

    // Pre-populate cache index with filenames from API response
    // Runs a single batch check instead of per-image checks
    function preBatchCacheCheck(images) {
        if (!images || images.length === 0) return
        var filenames = []
        for (var i = 0; i < images.length; i++) {
            var img = images[i]
            if (img.file_url) {
                var url = img.file_url
                // Strip query parameters (e.g., Sankaku signed URLs)
                var queryIdx = url.indexOf('?')
                if (queryIdx > 0) url = url.substring(0, queryIdx)
                // Extract filename from URL
                var filename = url.substring(url.lastIndexOf('/') + 1)
                if (filename.length > 0) {
                    filenames.push(decodeURIComponent(filename))
                }
            }
        }
        if (filenames.length > 0) {
            CacheIndex.batchCheck(filenames)
        }
    }

    function setProvider(provider) {
        provider = provider.toLowerCase()
        if (providerList.indexOf(provider) !== -1) {
            // Save current provider settings before switching
            if (currentProvider && currentProvider.length > 0) {
                saveProviderSettings()
            }

            root.currentProvider = provider

            // Save active provider to config
            ConfigOptions.booru.activeProvider = provider

            // Load saved settings for new provider
            loadProviderSettings(provider)

            // Track provider usage for popularity sorting
            var usage = ConfigOptions.booru.providerUsage || {}
            // Create a new object to trigger property change
            var newUsage = JSON.parse(JSON.stringify(usage))
            newUsage[provider] = (newUsage[provider] || 0) + 1
            ConfigOptions.booru.providerUsage = newUsage
            root.providerUsageUpdated()

            // Persist all changes to config
            ConfigLoader.saveConfig()

            var msg = "Provider set to " + providers[provider].name
            if (provider === "gelbooru" && (!gelbooruApiKey || !gelbooruUserId)) {
                msg += "\n⚠️ Gelbooru requires API key. Get yours at:\ngelbooru.com/index.php?page=account&s=options"
            }
            if (provider === "rule34" && (!rule34ApiKey || !rule34UserId)) {
                msg += "\n⚠️ Rule34 requires API key. Get yours at:\nrule34.xxx/index.php?page=account&s=options"
            }
            if (provider === "wallhaven" && !wallhavenApiKey) {
                msg += "\n⚠️ Wallhaven requires API key for NSFW content.\nGet yours at: wallhaven.cc/settings/account"
            }
            root.addSystemMessage(msg)
        } else {
            root.addSystemMessage("Invalid API provider. Supported:\n- " + providerList.join("\n- "))
        }
    }

    function clearResponses() {
        // Stop all playing videos before clearing
        root.stopAllVideos()

        // Abort all pending XHR requests to prevent stale updates
        for (var i = 0; i < pendingXhrRequests.length; i++) {
            try {
                pendingXhrRequests[i].abort()
            } catch (e) {
                // Ignore abort errors
            }
        }
        pendingXhrRequests = []
        responses = []
    }

    function addSystemMessage(message) {
        responses = responses.concat([root.booruResponseDataComponent.createObject(null, {
            "provider": "system",
            "tags": [],
            "page": -1,
            "images": [],
            "message": message
        })])
    }

    // Save current provider settings (sorting, ageFilter, nsfw)
    function saveProviderSettings() {
        var settings = ConfigOptions.booru.providerSettings || {}
        // Create new object to trigger property change
        var newSettings = JSON.parse(JSON.stringify(settings))
        newSettings[currentProvider] = {
            sorting: currentSorting,
            ageFilter: ageFilter,
            nsfw: allowNsfw
        }
        ConfigOptions.booru.providerSettings = newSettings
        console.log("[Booru] Saved settings for", currentProvider, ":", JSON.stringify(newSettings[currentProvider]))
    }

    // Load saved provider settings
    function loadProviderSettings(provider) {
        loadingSettings = true  // Prevent save loops
        var settings = ConfigOptions.booru.providerSettings || {}
        if (settings[provider]) {
            var s = settings[provider]
            if (s.sorting !== undefined) currentSorting = s.sorting
            if (s.ageFilter !== undefined) ageFilter = s.ageFilter
            if (s.nsfw !== undefined) allowNsfw = s.nsfw
            console.log("[Booru] Loaded settings for", provider, ":", JSON.stringify(s))
        } else {
            // Reset to defaults for new provider
            currentSorting = ""
            ageFilter = "1month"
            // Keep allowNsfw as-is or reset based on provider type
            console.log("[Booru] No saved settings for", provider, ", using defaults")
        }
        loadingSettings = false
    }

    function constructRequestUrl(tags, nsfw=true, limit=20, page=1) {
        var provider = providers[currentProvider]
        var baseUrl = getEffectiveApiUrl(currentProvider)
        var url = baseUrl
        var tagString = tags.join(" ")

        // Inject sort metatag for providers that use tag-based sorting
        if (currentSorting && currentSorting.length > 0) {
            // Moebooru sites use order:X
            if (currentProvider === "yandere" || currentProvider === "konachan" ||
                currentProvider === "sakugabooru" ||
                currentProvider === "3dbooru") {
                tagString = "order:" + currentSorting + " " + tagString
            }
            // Danbooru uses order:X
            else if (currentProvider === "danbooru" || currentProvider === "aibooru") {
                tagString = "order:" + currentSorting + " " + tagString
            }
            // e621 uses order:X
            else if (currentProvider === "e621") {
                tagString = "order:" + currentSorting + " " + tagString
            }
            // Gelbooru-based sites use sort:X
            else if (currentProvider === "gelbooru" || currentProvider === "safebooru" ||
                     currentProvider === "rule34" || currentProvider === "xbooru" ||
                     currentProvider === "tbib" || currentProvider === "hypnohub") {
                tagString = "sort:" + currentSorting + " " + tagString
            }
            // Sankaku sites use order:X
            else if (currentProvider === "sankaku" || currentProvider === "idol_sankaku") {
                tagString = "order:" + currentSorting + " " + tagString
            }
            // Zerochan, Wallhaven, Derpibooru handled via URL params below
        }

        // Inject age filter for providers that support it (prevents timeout on heavy sorts)
        // ageFilterProviders: danbooru, aibooru, yandere, konachan (NOT sakugabooru/3dbooru)
        if (ageFilter !== "any" && ageFilterProviders.indexOf(currentProvider) !== -1) {
            tagString = tagString + " age:<" + ageFilter
        }

        // Handle NSFW filtering per provider
        // Skip for SFW-only providers, NSFW-only providers, and those with own params
        // waifu.im: uses is_nsfw param
        // derpibooru: uses filter_id param
        // zerochan: SFW-only
        // sankaku/idol_sankaku: uses rating:safe tag (handled by default case below)
        var skipNsfwFilter = (currentProvider === "waifu.im" ||
                              currentProvider === "derpibooru" ||
                              currentProvider === "zerochan" ||
                              sfwOnlyProviders.indexOf(currentProvider) !== -1 ||
                              nsfwOnlyProviders.indexOf(currentProvider) !== -1)
        if (!nsfw && !skipNsfwFilter) {
            if (currentProvider == "gelbooru" || currentProvider == "danbooru" || currentProvider == "rule34" || currentProvider == "aibooru")
                tagString += " rating:general";
            else if (currentProvider == "e621")
                tagString += " rating:s";
            else if (currentProvider == "wallhaven")
                {} // Handled via purity parameter
            else
                tagString += " rating:safe";
        }

        var params = []
        if (currentProvider === "waifu.im") {
            var tagsArray = tagString.split(" ");
            for (var i = 0; i < tagsArray.length; i++) {
                var tag = tagsArray[i]
                if (tag.length > 0) params.push("included_tags=" + encodeURIComponent(tag));
            }
            params.push("limit=" + Math.min(limit, 30))
            params.push("is_nsfw=" + (nsfw ? "null" : "false"))
        } else if (currentProvider === "zerochan") {
            // Zerochan URL format: https://www.zerochan.net/Tag+Name?p=page&l=limit&json&s=sort
            // Multi-word tags use + separator in URL path
            var zerochanTag = tagString.trim().replace(/ /g, "+")
            // If tag exists, add to path; otherwise root triggers bot check (avoid)
            if (zerochanTag && zerochanTag.length > 0) {
                url = baseUrl + "/" + zerochanTag
            } else {
                // Default to a popular series to avoid bot check on root path
                url = baseUrl + "/Vocaloid"
            }
            params.push("p=" + page)
            params.push("l=" + limit)
            params.push("json")
            if (currentSorting && currentSorting.length > 0) {
                params.push("s=" + currentSorting)
            }
        } else if (currentProvider === "sankaku" || currentProvider === "idol_sankaku") {
            // Sankaku API: keyset pagination
            params.push("tags=" + encodeURIComponent(tagString))
            params.push("limit=" + limit)
            params.push("page=" + page)
        } else if (currentProvider === "derpibooru") {
            // Derpibooru (Philomena) API
            params.push("q=" + encodeURIComponent(tagString || "*"))
            params.push("per_page=" + Math.min(limit, 50))
            params.push("page=" + page)
            if (currentSorting && currentSorting.length > 0) {
                params.push("sf=" + currentSorting)
            }
            // Filter by rating (safe = filter 100277)
            if (!nsfw) {
                params.push("filter_id=100277")  // Safe filter
            }
        } else if (currentProvider === "wallhaven") {
            // Wallhaven uses different parameter names
            params.push("q=" + encodeURIComponent(tagString))
            // purity: 100=sfw, 010=sketchy, 001=nsfw, combine for multiple
            params.push("purity=" + (nsfw ? "111" : "100"))
            // Use currentSorting if set, otherwise fall back to wallhavenSorting
            var sorting = (currentSorting && currentSorting.length > 0) ? currentSorting : wallhavenSorting
            params.push("sorting=" + sorting)
            params.push("order=" + wallhavenOrder)
            // Add topRange for toplist sorting
            if (sorting === "toplist") {
                params.push("topRange=" + wallhavenTopRange)
            }
            // Minimum resolution filter (skip if "any")
            if (wallhavenResolution !== "any") {
                params.push("atleast=" + wallhavenResolution)
            }
            params.push("page=" + page)
            // API key required for NSFW content
            if (wallhavenApiKey && wallhavenApiKey.length > 0) {
                params.push("apikey=" + wallhavenApiKey)
            }
        } else if (currentProvider === "nekos_best") {
            // nekos.best uses amount parameter, ignores tags
            params.push("amount=" + Math.min(limit, 20))
        } else {
            params.push("tags=" + encodeURIComponent(tagString))
            params.push("limit=" + limit)
            // Providers using pid (page id) instead of page number
            if (currentProvider == "gelbooru" || currentProvider == "safebooru" || currentProvider == "rule34" || currentProvider == "xbooru" || currentProvider == "tbib" || currentProvider == "hypnohub") {
                params.push("pid=" + page)
                // Gelbooru-style API key authentication
                if (currentProvider == "gelbooru" && gelbooruApiKey && gelbooruUserId) {
                    params.push("api_key=" + gelbooruApiKey)
                    params.push("user_id=" + gelbooruUserId)
                }
                if (currentProvider == "rule34" && rule34ApiKey && rule34UserId) {
                    params.push("api_key=" + rule34ApiKey)
                    params.push("user_id=" + rule34UserId)
                }
            } else {
                params.push("page=" + page)
                // Danbooru API key authentication (higher rate limits)
                if (currentProvider == "danbooru" && danbooruApiKey) {
                    if (danbooruLogin) {
                        params.push("login=" + danbooruLogin)
                    }
                    params.push("api_key=" + danbooruApiKey)
                }
            }
        }

        if (baseUrl.indexOf("?") === -1) {
            url += "?" + params.join("&")
        } else {
            url += "&" + params.join("&")
        }
        return url
    }

    function makeRequest(tags, nsfw=false, limit=20, page=1) {
        // Single page pagination - always clear and replace
        clearResponses()
        currentTags = tags
        currentPage = page

        var requestProvider = currentProvider  // Capture provider at request time

        // Use Grabber for preferred providers (bypasses Cloudflare)
        if (shouldUseGrabber(requestProvider)) {
            console.log("[Booru] Using Grabber for " + requestProvider)
            makeGrabberRequest(tags, nsfw, limit, page, requestProvider)
            return
        }

        // Use curl for providers that need User-Agent header
        if (curlProviders.indexOf(requestProvider) !== -1) {
            console.log("[Booru] Using curl for " + requestProvider)
            makeCurlRequest(tags, nsfw, limit, page, requestProvider)
            return
        }

        var url = constructRequestUrl(tags, nsfw, limit, page)
        console.log("[Booru] " + currentProvider + " request: " + url)
        if (currentProvider == "rule34") {
            // Only log whether credentials are set, not their values (security)
            console.log("[Booru] Rule34 credentials: " + (rule34ApiKey && rule34UserId ? "configured" : "NOT SET"))
        }

        var newResponse = root.booruResponseDataComponent.createObject(null, {
            "provider": currentProvider,
            "tags": tags,
            "page": page,
            "images": [],
            "message": ""
        })

        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        // Danbooru/e621/e926/Sankaku need User-Agent or API blocks them
        if (requestProvider == "danbooru" || requestProvider == "e621" || requestProvider == "e926" ||
            requestProvider == "sankaku" || requestProvider == "idol_sankaku") {
            try {
                xhr.setRequestHeader("User-Agent", "Mozilla/5.0 BooruSidebar/1.0")
            } catch (e) {
                console.log("[Booru] Could not set User-Agent for " + requestProvider)
            }
        }

        // Helper to remove XHR from pending list
        function removeFromPending() {
            var idx = root.pendingXhrRequests.indexOf(xhr)
            if (idx !== -1) {
                root.pendingXhrRequests.splice(idx, 1)
            }
        }

        // Helper to add response (single page, already cleared)
        function addResponse(resp) {
            root.responses = [resp]
        }

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("[Booru] " + requestProvider + " done - HTTP " + xhr.status)
                removeFromPending()
            }
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var provider = providers[requestProvider]
                    var response
                    // Handle XML responses (e.g., Paheal)
                    if (provider.isXml) {
                        response = xhr.responseXML
                        console.log("[Booru] " + requestProvider + " got XML response")
                    } else {
                        response = JSON.parse(xhr.responseText)
                        console.log("[Booru] " + requestProvider + " got " + (response.length || "?") + " raw items")
                    }
                    // Use helper function to get mapFunc (supports apiType family mappers)
                    var mapFunc = getProviderMapFunc(requestProvider)
                    response = mapFunc(response, provider)
                    console.log("[Booru] " + requestProvider + " mapped to " + response.length + " items")
                    newResponse.images = response
                    newResponse.message = response.length > 0 ? "" : root.failMessage

                    // Pre-populate cache index for instant lookups
                    preBatchCacheCheck(response)
                } catch (e) {
                    console.log("[Booru] Failed to parse " + requestProvider + ": " + e)
                    newResponse.message = root.failMessage
                } finally {
                    root.runningRequests--
                    addResponse(newResponse)
                }
            } else if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("[Booru] " + requestProvider + " failed - HTTP " + xhr.status)
                if (xhr.responseText) console.log("[Booru] Response: " + xhr.responseText.substring(0, 200))
                newResponse.message = root.failMessage
                root.runningRequests--
                addResponse(newResponse)
            }
            root.responseFinished()
        }

        root.runningRequests++
        root.pendingXhrRequests.push(xhr)
        xhr.send()
    }

    // Make request using Grabber CLI (for providers that block direct API access)
    function makeGrabberRequest(tags, nsfw, limit, page, requestProvider) {
        var newResponse = root.booruResponseDataComponent.createObject(null, {
            "provider": requestProvider,
            "tags": tags,
            "page": page,
            "images": [],
            "message": ""
        })

        var source = grabberSources[requestProvider]
        var tagString = tags.join(" ")

        // Add sort metatag if sorting is set (for order: metatag providers)
        if (currentSorting && currentSorting.length > 0) {
            if (requestProvider === "danbooru" || requestProvider === "aibooru" ||
                requestProvider === "yandere" || requestProvider === "konachan") {
                tagString = "order:" + currentSorting + " " + tagString
            }
        }

        // Inject age filter for providers that support it
        if (ageFilter !== "any" && ageFilterProviders.indexOf(requestProvider) !== -1) {
            tagString = tagString + " age:<" + ageFilter
        }

        console.log("[Booru] Grabber request: source=" + source + " tags=" + tagString + " page=" + page)

        // Build properties for GrabberRequest
        var grabberProps = {
            "source": source,
            "tags": tagString,
            "limit": limit,
            "page": page,
            "isNsfw": nsfw,
            "loadDetails": false  // --load-details is slow (20s+ per request)
        }

        // Add authentication for providers that support it
        if (requestProvider === "danbooru" && danbooruApiKey) {
            grabberProps.user = danbooruLogin
            grabberProps.password = danbooruApiKey
            console.log("[Booru] Using Danbooru auth: " + danbooruLogin)
        }

        var grabberReq = grabberRequestComponent.createObject(root, grabberProps)

        root.runningRequests++

        grabberReq.finished.connect(function(images) {
            console.log("[Booru] Grabber returned " + images.length + " images")
            newResponse.images = images
            newResponse.message = images.length > 0 ? "" : root.failMessage
            // Pre-populate cache index for instant lookups
            preBatchCacheCheck(images)
            root.runningRequests--
            root.responses = root.responses.concat([newResponse])
            root.responseFinished()
            grabberReq.destroy()
        })

        grabberReq.failed.connect(function(error) {
            console.log("[Booru] Grabber failed: " + error)
            newResponse.message = root.failMessage + "\n(Grabber: " + error + ")"
            root.runningRequests--
            root.responses = root.responses.concat([newResponse])
            root.responseFinished()
            grabberReq.destroy()
        })

        grabberReq.startRequest()
    }

    // Make request using curl (for providers that need User-Agent header)
    function makeCurlRequest(tags, nsfw, limit, page, requestProvider) {
        var newResponse = root.booruResponseDataComponent.createObject(null, {
            "provider": requestProvider,
            "tags": tags,
            "page": page,
            "images": [],
            "message": ""
        })

        var url = constructRequestUrl(tags, nsfw, limit, page)
        console.log("[Booru] curl request: " + url)

        root.runningRequests++

        // Create and start curl process
        var curlProcess = curlFetcherComponent.createObject(root, {
            "curlUrl": url,
            "requestProvider": requestProvider,
            "responseObj": newResponse
        })
        curlProcess.running = true
    }

    // Component for curl-based fetching (providers that need User-Agent)
    property Component curlFetcherComponent: Component {
        Process {
            id: curlProc
            property string curlUrl: ""
            property string requestProvider: ""
            property var responseObj: null
            property string outputText: ""

            // Use simple app UA for zerochan (blocks browser-like UAs), default for others
            property string userAgent: requestProvider === "zerochan" ? "QuickshellBooruSidebar/1.0" : root.defaultUserAgent
            command: ["curl", "-s", "-A", userAgent, curlUrl]

            stdout: SplitParser {
                onRead: data => { curlProc.outputText += data }
            }

            onExited: function(code, status) {
                console.log("[Booru] curl " + requestProvider + " exited with code " + code)
                if (code === 0 && curlProc.outputText.length > 0) {
                    try {
                        var response = JSON.parse(curlProc.outputText)
                        var mapFunc = root.getProviderMapFunc(requestProvider)
                        var images = mapFunc(response, root.providers[requestProvider])
                        console.log("[Booru] curl " + requestProvider + " mapped " + images.length + " images")
                        responseObj.images = images
                        responseObj.message = images.length > 0 ? "" : root.failMessage
                        root.preBatchCacheCheck(images)
                    } catch (e) {
                        console.log("[Booru] curl parse error: " + e)
                        responseObj.message = root.failMessage
                    }
                } else {
                    console.log("[Booru] curl failed or empty response")
                    responseObj.message = root.failMessage
                }
                root.runningRequests--
                root.responses = [responseObj]
                root.responseFinished()
                curlProc.destroy()
            }
        }
    }

    property var currentTagRequest: null
    function triggerTagSearch(query) {
        if (currentTagRequest) {
            currentTagRequest.abort();
        }

        var provider = providers[currentProvider]
        if (!provider.tagSearchTemplate) return

        var url = provider.tagSearchTemplate.replace("{{query}}", encodeURIComponent(query))

        // For providers with mirrors, replace the base URL with the mirror's tagApi
        if (provider.mirrors) {
            var mirror = getCurrentMirror(currentProvider)
            var mirrorData = provider.mirrors[mirror]
            if (mirrorData.tagApi) {
                // Extract the query params from the template and append to mirror's tagApi
                var queryPart = provider.tagSearchTemplate.split("?")[1]
                if (queryPart) {
                    queryPart = queryPart.replace("{{query}}", encodeURIComponent(query))
                    url = mirrorData.tagApi + "?" + queryPart
                }
            }
        }

        // Add API credentials for tag search
        if (currentProvider === "gelbooru" && gelbooruApiKey && gelbooruUserId) {
            url += "&api_key=" + gelbooruApiKey + "&user_id=" + gelbooruUserId
        }
        if (currentProvider === "rule34" && rule34ApiKey && rule34UserId) {
            url += "&api_key=" + rule34ApiKey + "&user_id=" + rule34UserId
        }
        if (currentProvider === "danbooru" && danbooruApiKey) {
            url += (danbooruLogin ? "&login=" + danbooruLogin : "") + "&api_key=" + danbooruApiKey
        }

        var xhr = new XMLHttpRequest()
        currentTagRequest = xhr
        xhr.open("GET", url)
        // Danbooru/e621/e926/Sankaku need User-Agent or API blocks them
        if (currentProvider == "danbooru" || currentProvider == "e621" || currentProvider == "e926" ||
            currentProvider == "sankaku" || currentProvider == "idol_sankaku") {
            try {
                xhr.setRequestHeader("User-Agent", "Mozilla/5.0 BooruSidebar/1.0")
            } catch (e) {
                console.log("[Booru] Could not set User-Agent for tag search: " + e)
            }
        }
        var requestProvider = currentProvider  // Capture for closure
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                currentTagRequest = null
                try {
                    var response = JSON.parse(xhr.responseText)
                    // Use helper function to get tagMapFunc (supports apiType family mappers)
                    var tagMapFunc = getProviderTagMapFunc(requestProvider)
                    if (tagMapFunc) {
                        response = tagMapFunc(response)
                    }
                    root.tagSuggestion(query, response)
                } catch (e) {
                    console.log("[Booru] Failed to parse tag response: " + e)
                }
            } else if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("[Booru] Tag search failed - HTTP " + xhr.status)
                currentTagRequest = null
            }
        }
        xhr.send()
    }
}
