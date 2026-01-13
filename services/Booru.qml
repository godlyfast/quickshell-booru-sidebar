pragma Singleton
pragma ComponentBehavior: Bound

import "../modules/common"
import "../modules/common/utils"
import "./providers"
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
        Logger.info("Booru", "=== BOORU SERVICE LOADED ===")
        Logger.info("Booru", `Provider count: ${ProviderRegistry.providerList.length}`)
        Logger.debug("Booru", `Providers: ${ProviderRegistry.providerList.join(", ")}`)
    }

    // =========================================================================
    // Provider Registry Delegates (backwards compatibility)
    // Static data is now centralized in ProviderRegistry.qml
    // =========================================================================
    readonly property var providerList: ProviderRegistry.providerList
    readonly property var providers: ProviderRegistry.providers
    readonly property var providerSortOptions: ProviderRegistry.providerSortOptions
    readonly property var grabberSources: ProviderRegistry.grabberSources

    // Delegate helper functions to ProviderRegistry
    function providerHasMirrors(provider) { return ProviderRegistry.providerHasMirrors(provider) }
    function getMirrorList(provider) { return ProviderRegistry.getMirrorList(provider) }
    function getGrabberSource(provider) { return ProviderRegistry.getGrabberSource(provider) }
    function getProviderMapFunc(providerKey) { return ProviderRegistry.getProviderMapFunc(providerKey) }
    function getProviderTagMapFunc(providerKey) { return ProviderRegistry.getProviderTagMapFunc(providerKey) }
    function getPostUrl(provider, imageId) { return ProviderRegistry.getPostUrl(provider, imageId) }
    function getWorkingImageSource(url) { return ProviderRegistry.getWorkingImageSource(url) }

    // Restore provider settings after config is loaded
    Connections {
        target: ConfigLoader
        function onConfigLoaded() {
            const savedProvider = ConfigOptions.booru.activeProvider
            if (savedProvider && savedProvider.length > 0 && providerList.indexOf(savedProvider) !== -1) {
                loadingSettings = true
                currentProvider = savedProvider
                loadProviderSettings(savedProvider)
                loadingSettings = false
                Logger.info("Booru", `Restored active provider: ${savedProvider}`)
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

    // Hover tracking moved to HoverTracker.qml singleton (reduces god-object size)

    property string failMessage: "That didn't work. Tips:\n- Check your tags and NSFW settings\n- If you don't have a tag in mind, type a page number"
    property var responses: []
    property int runningRequests: 0
    property var pendingXhrRequests: []  // Track XHR for abort on clear
    property var pendingTimers: []  // Track timeout timers for cleanup
    property int requestIdCounter: 0  // Monotonic counter for stale request detection

    // Pagination state (single page at a time)
    property int currentPage: 1
    property var currentTags: []
    property string defaultUserAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"

    // Persistent state
    property string currentProvider: "wallhaven"
    property bool allowNsfw: false
    property int limit: 20
    property int cacheBust: 0  // Increment to force Qt network cache bypass

    // Wallhaven sorting options (legacy, kept for backwards compatibility)
    property string wallhavenSorting: "toplist"  // date_added, relevance, random, views, favorites, toplist
    property string wallhavenOrder: "desc"       // desc, asc
    property var wallhavenSortOptions: ["toplist", "random", "date_added", "relevance", "views", "favorites"]

    // Wallhaven toplist time range (only applies when sorting=toplist)
    property string wallhavenTopRange: "1M"  // 1d, 3d, 1w, 1M, 3M, 6M, 1y
    readonly property var topRangeOptions: ["1d", "3d", "1w", "1M", "3M", "6M", "1y"]

    // Wallhaven minimum resolution filter (persisted to config.json)
    property string wallhavenResolution: ConfigOptions.booru.wallhavenResolution
    onWallhavenResolutionChanged: ConfigOptions.booru.wallhavenResolution = wallhavenResolution
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
    // Computed property: uses ProviderRegistry.ageFilterProviders
    property bool providerSupportsAgeFilter: ProviderRegistry.ageFilterProviders.indexOf(currentProvider) !== -1

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

    onCurrentPageChanged: {
        if (configReady && !loadingSettings && currentProvider.length > 0) {
            settingsSaveTimer.restart()
        }
    }

    // Get sort options for current provider (data from ProviderRegistry)
    function getSortOptions() {
        return ProviderRegistry.getSortOptionsForProvider(currentProvider)
    }

    // Check if current provider supports sorting
    property bool providerSupportsSorting: getSortOptions().length > 0

    // Provider supports NSFW if: not SFW-only AND current mirror isn't SFW-only
    property bool providerSupportsNsfw: ProviderRegistry.sfwOnlyProviders.indexOf(currentProvider) === -1 && !currentMirrorIsSfwOnly(currentProvider)

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

    // Danbooru API credentials (higher rate limits, access to restricted content)
    // Get your key at: https://danbooru.donmai.us/profile → API Key
    property string danbooruLogin: (ConfigOptions.booru && ConfigOptions.booru.danbooruLogin) ? ConfigOptions.booru.danbooruLogin : ""
    property string danbooruApiKey: (ConfigOptions.booru && ConfigOptions.booru.danbooruApiKey) ? ConfigOptions.booru.danbooruApiKey : ""

    // Grabber filename template for downloads
    // Tokens: %website%, %id%, %md5%, %artist%, %copyright%, %character%, %ext%
    property string filenameTemplate: (ConfigOptions.booru && ConfigOptions.booru.filenameTemplate) ? ConfigOptions.booru.filenameTemplate : "%website% %id%.%ext%"

    // Grabber API fallback toggle (via /grabber command)
    property bool useGrabberFallback: true

    // Check if provider should use Grabber for requests (runtime decision)
    function shouldUseGrabber(provider) {
        if (!useGrabberFallback) return false
        // Grabber-only providers always use Grabber
        if (providers[provider] && providers[provider].useGrabberFallback) return true
        // Check if this provider is in the preferred list and has a Grabber source
        return ProviderRegistry.grabberPreferredProviders.indexOf(provider) !== -1 && grabberSources[provider]
    }

    // Component for creating GrabberRequest instances
    property Component grabberRequestComponent: Component {
        GrabberRequest {}
    }

    // Mirror system - tracks current mirror selection per provider
    property var currentMirrors: ({})

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
        const newMirrors = JSON.parse(JSON.stringify(currentMirrors))
        newMirrors[provider] = mirrorKey
        currentMirrors = newMirrors
        Logger.info("Booru", `Mirror set: ${provider} -> ${mirrorKey}`)
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

    // =========================================================================
    // Removed: providers object - now in ProviderRegistry.qml
    // Removed: providerSortOptions - now in ProviderRegistry.qml
    // Removed: grabberSources - now in ProviderRegistry.qml
    // Removed: ageFilterProviders, sfwOnlyProviders, nsfwOnlyProviders - now in ProviderRegistry.qml
    // =========================================================================

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

        // Increment request ID to invalidate any in-flight requests
        root.requestIdCounter++

        // Destroy all pending timeout timers first (before aborting XHR)
        for (var t = 0; t < pendingTimers.length; t++) {
            try {
                if (pendingTimers[t]) {
                    pendingTimers[t].stop()
                    pendingTimers[t].destroy()
                }
            } catch (e) {
                // Ignore destroy errors
            }
        }
        pendingTimers = []

        // Abort all pending XHR requests to prevent stale updates
        for (var i = 0; i < pendingXhrRequests.length; i++) {
            try {
                pendingXhrRequests[i].abort()
            } catch (e) {
                // Ignore abort errors
            }
        }
        pendingXhrRequests = []

        // Destroy response objects to release references
        for (var j = 0; j < responses.length; j++) {
            if (responses[j] && responses[j].destroy) {
                responses[j].destroy()
            }
        }
        responses = []

        // Force JavaScript garbage collection to free memory
        gc()
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

    /**
     * Format an error message for display to user.
     * Provides consistent format across XHR, curl, and Grabber errors.
     * @param method - Request method (http, curl, grabber)
     * @param detail - Technical detail (e.g., "404", "timeout", error message)
     */
    function formatErrorMessage(method, detail) {
        return `${root.failMessage}\n(${method}: ${detail})`
    }

    /**
     * Log details for first N images in a response.
     * Helps trace URL selection and debug image loading issues.
     * @param images - Array of normalized image objects
     * @param count - Number of images to log (default 3)
     */
    function logImageDetails(images, count = 3) {
        for (let i = 0; i < Math.min(count, images.length); i++) {
            const img = images[i]
            Logger.info("Booru", `  [${i}] id=${img.id} ext=${img.file_ext} ${img.width}x${img.height}`)
            Logger.info("Booru", `  [${i}] preview: ${img.preview_url?.substring(0, 100) || "(none)"}`)
            Logger.info("Booru", `  [${i}] sample:  ${img.sample_url?.substring(0, 100) || "(none)"}`)
            Logger.info("Booru", `  [${i}] file:    ${img.file_url?.substring(0, 100) || "(none)"}`)
            if (img.source) Logger.info("Booru", `  [${i}] source:  ${img.source?.substring(0, 100)}`)
        }
    }

    // Save current provider settings (sorting, ageFilter, nsfw, page)
    function saveProviderSettings() {
        const settings = ConfigOptions.booru.providerSettings || {}
        // Create new object to trigger property change
        const newSettings = JSON.parse(JSON.stringify(settings))
        newSettings[currentProvider] = {
            sorting: currentSorting,
            ageFilter: ageFilter,
            nsfw: allowNsfw,
            page: currentPage
        }
        ConfigOptions.booru.providerSettings = newSettings
        Logger.debug("Booru", `Saved settings for ${currentProvider}: ${JSON.stringify(newSettings[currentProvider])}`)
    }

    // Load saved provider settings
    function loadProviderSettings(provider) {
        loadingSettings = true  // Prevent save loops
        const settings = ConfigOptions.booru.providerSettings || {}
        if (settings[provider]) {
            const s = settings[provider]
            if (s.sorting !== undefined) currentSorting = s.sorting
            if (s.ageFilter !== undefined) ageFilter = s.ageFilter
            if (s.nsfw !== undefined) allowNsfw = s.nsfw
            if (s.page !== undefined && s.page >= 1) currentPage = s.page
            Logger.debug("Booru", `Loaded settings for ${provider}: ${JSON.stringify(s)}`)
        } else {
            // Reset to defaults for new provider
            currentSorting = ""
            ageFilter = "1month"
            currentPage = 1
            // Keep allowNsfw as-is or reset based on provider type
            Logger.debug("Booru", `No saved settings for ${provider}, using defaults`)
        }
        loadingSettings = false
    }

    function constructRequestUrl(tags, nsfw=true, limit=20, page=1) {
        var provider = providers[currentProvider]
        var baseUrl = getEffectiveApiUrl(currentProvider)
        var url = baseUrl
        var tagString = tags.join(" ")

        // Inject sort metatag for providers that use tag-based sorting
        // (Zerochan, Wallhaven, Derpibooru handled via URL params below)
        tagString = ProviderRegistry.injectSortMetatag(currentProvider, tagString, currentSorting)

        // Inject age filter for providers that support it (prevents timeout on heavy sorts)
        // ageFilterProviders: danbooru, aibooru, yandere, konachan (NOT sakugabooru/3dbooru)
        if (ageFilter !== "any" && ProviderRegistry.ageFilterProviders.indexOf(currentProvider) !== -1) {
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
                              ProviderRegistry.sfwOnlyProviders.indexOf(currentProvider) !== -1 ||
                              ProviderRegistry.nsfwOnlyProviders.indexOf(currentProvider) !== -1)
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

        const requestProvider = currentProvider  // Capture provider at request time
        const requestId = root.requestIdCounter  // Capture ID to detect stale responses

        // Use Grabber for preferred providers (bypasses Cloudflare)
        if (shouldUseGrabber(requestProvider)) {
            Logger.info("Booru", `Using Grabber for ${requestProvider}`)
            makeGrabberRequest(tags, nsfw, limit, page, requestProvider, requestId)
            return
        }

        // Use curl for providers that need User-Agent header
        if (ProviderRegistry.curlProviders.indexOf(requestProvider) !== -1) {
            Logger.info("Booru", `Using curl for ${requestProvider}`)
            makeCurlRequest(tags, nsfw, limit, page, requestProvider, requestId)
            return
        }

        const url = constructRequestUrl(tags, nsfw, limit, page)
        Logger.info("Booru", `${currentProvider} request: ${url}`)
        if (currentProvider == "rule34") {
            // Only log whether credentials are set, not their values (security)
            Logger.debug("Booru", `Rule34 credentials: ${rule34ApiKey && rule34UserId ? "configured" : "NOT SET"}`)
        }

        var newResponse = root.booruResponseDataComponent.createObject(null, {
            "provider": currentProvider,
            "tags": tags,
            "page": page,
            "images": [],
            "message": ""
        })

        const xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        // Danbooru/e621/e926/Sankaku need User-Agent or API blocks them
        if (requestProvider == "danbooru" || requestProvider == "e621" || requestProvider == "e926" ||
            requestProvider == "sankaku" || requestProvider == "idol_sankaku") {
            try {
                xhr.setRequestHeader("User-Agent", "Mozilla/5.0 BooruSidebar/1.0")
            } catch (e) {
                Logger.warn("Booru", `Could not set User-Agent for ${requestProvider}`)
            }
        }

        // Bug 1.2: Timeout handling - create timer to abort stale requests
        let requestAborted = false
        const timeoutTimer = Qt.createQmlObject('import QtQuick; Timer { interval: 30000; running: true }', root)
        root.pendingTimers.push(timeoutTimer)

        // Helper to remove timer from tracking array
        const removeTimerFromPending = () => {
            const tidx = root.pendingTimers.indexOf(timeoutTimer)
            if (tidx !== -1) {
                root.pendingTimers.splice(tidx, 1)
            }
        }

        timeoutTimer.triggered.connect(() => {
            if (xhr.readyState !== XMLHttpRequest.DONE && !requestAborted) {
                requestAborted = true
                Logger.warn("Booru", `Request timeout for ${requestProvider} after 30s`)
                try { xhr.abort() } catch (e) { /* ignore abort errors */ }
                removeFromPending()
                newResponse.message = root.formatErrorMessage("http", "timeout")
                root.runningRequests--
                addResponse(newResponse)
                root.responseFinished()
            }
            removeTimerFromPending()
            timeoutTimer.destroy()
        })

        // Helper to remove XHR from pending list
        const removeFromPending = () => {
            const idx = root.pendingXhrRequests.indexOf(xhr)
            if (idx !== -1) {
                root.pendingXhrRequests.splice(idx, 1)
            }
        }

        // Helper to add response (single page, already cleared)
        const addResponse = (resp) => {
            root.responses = [resp]
        }

        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                // Stop and cleanup timeout timer
                if (timeoutTimer) {
                    removeTimerFromPending()
                    timeoutTimer.stop()
                    timeoutTimer.destroy()
                }

                // Bug 1.2: Skip if already handled by timeout
                if (requestAborted) return

                Logger.info("Booru", `${requestProvider} done - HTTP ${xhr.status}`)
                removeFromPending()

                // Check if request is stale (newer request was started)
                if (requestId !== root.requestIdCounter) {
                    Logger.warn("Booru", `Stale request detected (id ${requestId} vs ${root.requestIdCounter}), discarding`)
                    root.runningRequests--
                    return
                }

                // Bug 1.3: Verify provider hasn't changed during request
                if (root.currentProvider !== requestProvider) {
                    Logger.warn("Booru", `Provider changed during request, discarding stale response from ${requestProvider}`)
                    root.runningRequests--
                    return
                }
            }
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    const provider = providers[requestProvider]
                    let response
                    // Handle XML responses (e.g., Paheal)
                    if (provider.isXml) {
                        response = xhr.responseXML
                        Logger.debug("Booru", `${requestProvider} got XML response`)
                    } else {
                        response = JSON.parse(xhr.responseText)
                        Logger.debug("Booru", `${requestProvider} got ${response.length ?? "?"} raw items`)
                    }
                    // Bug 1.4: Validate mapFunc before calling
                    const mapFunc = getProviderMapFunc(requestProvider)
                    if (!mapFunc) {
                        Logger.error("Booru", `No mapFunc for provider: ${requestProvider}`)
                        newResponse.message = `${root.failMessage}\n(Provider not configured)`
                        root.runningRequests--
                        addResponse(newResponse)
                        return
                    }
                    response = mapFunc(response, provider)
                    Logger.info("Booru", `${requestProvider} mapped to ${response.length} images`)
                    logImageDetails(response)

                    newResponse.images = response
                    newResponse.message = response.length > 0 ? "" : root.failMessage

                    // Pre-populate cache index for instant lookups
                    preBatchCacheCheck(response)
                } catch (e) {
                    Logger.error("Booru", `Failed to parse ${requestProvider}: ${e}`)
                    newResponse.message = root.formatErrorMessage("http", "parse error")
                } finally {
                    root.runningRequests--
                    addResponse(newResponse)
                }
            } else if (xhr.readyState === XMLHttpRequest.DONE) {
                Logger.error("Booru", `${requestProvider} failed - HTTP ${xhr.status}`)
                if (xhr.responseText) Logger.debug("Booru", `Response: ${xhr.responseText.substring(0, 200)}`)
                newResponse.message = root.formatErrorMessage("http", xhr.status)
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
    function makeGrabberRequest(tags, nsfw, limit, page, requestProvider, requestId) {
        var newResponse = root.booruResponseDataComponent.createObject(null, {
            "provider": requestProvider,
            "tags": tags,
            "page": page,
            "images": [],
            "message": ""
        })

        var source = grabberSources[requestProvider]
        var tagString = tags.join(" ")

        // Inject sort metatag for providers that use tag-based sorting
        tagString = ProviderRegistry.injectSortMetatag(requestProvider, tagString, currentSorting)

        // Inject age filter for providers that support it
        if (ageFilter !== "any" && ProviderRegistry.ageFilterProviders.indexOf(requestProvider) !== -1) {
            tagString = tagString + " age:<" + ageFilter
        }

        Logger.info("Booru", `Grabber request: source=${source} tags=${tagString} page=${page}`)

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
            Logger.debug("Booru", `Using Danbooru auth: ${danbooruLogin}`)
        }

        var grabberReq = grabberRequestComponent.createObject(root, grabberProps)

        root.runningRequests++

        grabberReq.finished.connect(function(images) {
            Logger.info("Booru", `Grabber returned ${images.length} images`)

            // Check if request is stale (newer request was started)
            if (requestId !== root.requestIdCounter) {
                Logger.warn("Booru", `Stale Grabber request detected (id ${requestId} vs ${root.requestIdCounter}), discarding`)
                root.runningRequests--
                grabberReq.destroy()
                return
            }

            logImageDetails(images)

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
            Logger.error("Booru", `Grabber failed: ${error}`)
            // Check if request is stale
            if (requestId !== root.requestIdCounter) {
                Logger.warn("Booru", `Stale Grabber request (failed) detected, discarding`)
                root.runningRequests--
                grabberReq.destroy()
                return
            }
            newResponse.message = root.formatErrorMessage("grabber", error)
            root.runningRequests--
            root.responses = root.responses.concat([newResponse])
            root.responseFinished()
            grabberReq.destroy()
        })

        grabberReq.startRequest()
    }

    // Make request using curl (for providers that need User-Agent header)
    function makeCurlRequest(tags, nsfw, limit, page, requestProvider, requestId) {
        var newResponse = root.booruResponseDataComponent.createObject(null, {
            "provider": requestProvider,
            "tags": tags,
            "page": page,
            "images": [],
            "message": ""
        })

        var url = constructRequestUrl(tags, nsfw, limit, page)
        Logger.info("Booru", `curl request: ${url}`)

        root.runningRequests++

        // Create and start curl process
        var curlProcess = curlFetcherComponent.createObject(root, {
            "curlUrl": url,
            "requestProvider": requestProvider,
            "responseObj": newResponse,
            "requestId": requestId
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
            property int requestId: -1  // For stale request detection

            // Use simple app UA for zerochan (blocks browser-like UAs), default for others
            property string userAgent: requestProvider === "zerochan" ? "QuickshellBooruSidebar/1.0" : root.defaultUserAgent
            command: ["curl", "-s", "-A", userAgent, curlUrl]

            stdout: SplitParser {
                onRead: data => { curlProc.outputText += data }
            }

            onExited: (code, status) => {
                Logger.debug("Booru", `curl ${requestProvider} exited with code ${code}`)

                // Check if request is stale (newer request was started)
                if (requestId !== root.requestIdCounter) {
                    Logger.warn("Booru", `Stale curl request detected (id ${requestId} vs ${root.requestIdCounter}), discarding`)
                    root.runningRequests--
                    curlProc.destroy()
                    return
                }

                if (code === 0 && curlProc.outputText.length > 0) {
                    try {
                        const response = JSON.parse(curlProc.outputText)
                        // Bug 1.4: Validate mapFunc before calling
                        const mapFunc = root.getProviderMapFunc(requestProvider)
                        if (!mapFunc) {
                            Logger.error("Booru", `No mapFunc for curl provider: ${requestProvider}`)
                            responseObj.message = `${root.failMessage}\n(Provider not configured)`
                            root.runningRequests--
                            root.responses = [responseObj]
                            root.responseFinished()
                            curlProc.destroy()
                            return
                        }
                        const images = mapFunc(response, root.providers[requestProvider])
                        Logger.info("Booru", `curl ${requestProvider} mapped ${images.length} images`)
                        responseObj.images = images
                        responseObj.message = images.length > 0 ? "" : root.failMessage
                        root.preBatchCacheCheck(images)
                    } catch (e) {
                        Logger.error("Booru", `curl parse error: ${e}`)
                        responseObj.message = root.formatErrorMessage("curl", "parse error")
                    }
                } else {
                    Logger.error("Booru", "curl failed or empty response")
                    responseObj.message = root.formatErrorMessage("curl", "no response")
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
        // Bug 1.5: Wrap abort in try/catch to handle race conditions
        if (currentTagRequest) {
            try {
                currentTagRequest.abort()
            } catch (e) {
                // Ignore abort errors on race condition
            }
        }

        const provider = providers[currentProvider]
        if (!provider.tagSearchTemplate) return

        let url = provider.tagSearchTemplate.replace("{{query}}", encodeURIComponent(query))

        // For providers with mirrors, replace the base URL with the mirror's tagApi
        if (provider.mirrors) {
            const mirror = getCurrentMirror(currentProvider)
            const mirrorData = provider.mirrors[mirror]
            if (mirrorData?.tagApi) {
                // Extract the query params from the template and append to mirror's tagApi
                const queryPart = provider.tagSearchTemplate.split("?")[1]
                if (queryPart) {
                    url = `${mirrorData.tagApi}?${queryPart.replace("{{query}}", encodeURIComponent(query))}`
                }
            }
        }

        // Add API credentials for tag search
        if (currentProvider === "gelbooru" && gelbooruApiKey && gelbooruUserId) {
            url += `&api_key=${gelbooruApiKey}&user_id=${gelbooruUserId}`
        }
        if (currentProvider === "rule34" && rule34ApiKey && rule34UserId) {
            url += `&api_key=${rule34ApiKey}&user_id=${rule34UserId}`
        }
        if (currentProvider === "danbooru" && danbooruApiKey) {
            url += `${danbooruLogin ? "&login=" + danbooruLogin : ""}&api_key=${danbooruApiKey}`
        }

        const xhr = new XMLHttpRequest()
        currentTagRequest = xhr
        xhr.open("GET", url)
        // Danbooru/e621/e926/Sankaku need User-Agent or API blocks them
        if (currentProvider == "danbooru" || currentProvider == "e621" || currentProvider == "e926" ||
            currentProvider == "sankaku" || currentProvider == "idol_sankaku") {
            try {
                xhr.setRequestHeader("User-Agent", "Mozilla/5.0 BooruSidebar/1.0")
            } catch (e) {
                Logger.warn("Booru", `Could not set User-Agent for tag search: ${e}`)
            }
        }
        const requestProvider = currentProvider  // Capture for closure
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                currentTagRequest = null
                try {
                    let response = JSON.parse(xhr.responseText)
                    // Use helper function to get tagMapFunc (supports apiType family mappers)
                    const tagMapFunc = getProviderTagMapFunc(requestProvider)
                    if (tagMapFunc) {
                        response = tagMapFunc(response)
                    }
                    root.tagSuggestion(query, response)
                } catch (e) {
                    Logger.error("Booru", `Failed to parse tag response: ${e}`)
                }
            } else if (xhr.readyState === XMLHttpRequest.DONE) {
                Logger.warn("Booru", `Tag search failed - HTTP ${xhr.status}`)
                currentTagRequest = null
            }
        }
        xhr.send()
    }
}
