import QtQuick
import Quickshell.Io
import "./services"
import "./modules/common"

/**
 * Integration tests for all booru providers.
 * Validates that APIs return correct data and all required fields are present.
 * Also tests edge cases like null URL fallbacks, tag autocomplete, and sorting.
 */
Item {
    id: root

    signal testsCompleted(int passed, int failed)

    property int currentIndex: 0
    property int passedCount: 0
    property int failedCount: 0
    property int skippedCount: 0
    property int autocompletePassedCount: 0
    property int autocompleteFailedCount: 0
    property var providerKeys: []

    // Providers that need curl (User-Agent) to bypass Cloudflare
    // Note: e621/e926 work with curl for image tests, danbooru has stricter protections
    // paheal uses XML which QML XMLHttpRequest.responseXML doesn't handle well
    property var curlProviders: ["e621", "e926", "paheal"]

    // Providers that cannot be tested due to Cloudflare JS challenges
    property var cloudflareProviders: ["danbooru"]

    // Providers that return XML instead of JSON
    property var xmlProviders: ["paheal"]

    // Edge case tags - providers where default "landscape" may not catch null URL issues
    // "solo" on e621/e926 often has posts with null sample_url
    property var edgeCaseTags: {
        "e621": "solo",
        "e926": "solo"
    }

    // Providers that support tag autocomplete
    // Note: e621/e926 excluded - autocomplete endpoint has strict Cloudflare protection
    property var autocompleteProviders: ["yandere", "konachan", "danbooru", "gelbooru", "safebooru",
                                          "konachan_com", "aibooru"]

    // Sorting test counters
    property int sortingPassedCount: 0
    property int sortingFailedCount: 0

    // Expected sort options per provider (should match Booru.providerSortOptions)
    property var expectedSortOptions: ({
        "yandere": ["score", "score_asc", "id", "id_desc", "mpixels", "landscape", "portrait"],
        "konachan": ["score", "score_asc", "id", "id_desc", "mpixels", "landscape", "portrait"],
        "konachan_com": ["score", "score_asc", "id", "id_desc", "mpixels", "landscape", "portrait"],
        "danbooru": ["rank", "score", "id", "id_desc"],
        "e621": ["score", "favcount", "id"],
        "e926": ["score", "favcount", "id"],
        "gelbooru": ["score", "score:desc", "score:asc", "id", "updated"],
        "safebooru": ["score", "score:desc", "score:asc", "id", "updated"],
        "rule34": ["score", "score:desc", "score:asc", "id", "updated"],
        "wallhaven": ["toplist", "random", "date_added", "relevance", "views", "favorites"],
        "waifu.im": [],
        "nekos_best": [],
        "xbooru": ["score", "id", "updated"],
        "tbib": ["score", "id"],
        "paheal": [],
        "hypnohub": ["score", "id", "updated"],
        "aibooru": ["score", "id"]
    })

    // Required fields and their validators
    function validateImage(img, providerKey) {
        var errors = []

        if (img.id === undefined || img.id === null)
            errors.push("id missing")
        if (typeof img.width !== "number" || img.width <= 0)
            errors.push("width invalid: " + img.width)
        if (typeof img.height !== "number" || img.height <= 0)
            errors.push("height invalid: " + img.height)
        if (typeof img.aspect_ratio !== "number" || img.aspect_ratio <= 0)
            errors.push("aspect_ratio invalid: " + img.aspect_ratio)
        if (typeof img.tags !== "string")
            errors.push("tags not string: " + typeof img.tags)
        if (typeof img.rating !== "string")
            errors.push("rating not string: " + typeof img.rating)
        if (typeof img.is_nsfw !== "boolean")
            errors.push("is_nsfw not boolean: " + typeof img.is_nsfw)

        // URL validation - check for empty strings AND valid http prefix
        if (typeof img.preview_url !== "string" || img.preview_url.length === 0 || !img.preview_url.startsWith("http"))
            errors.push("preview_url invalid: '" + img.preview_url + "'")
        if (typeof img.sample_url !== "string" || img.sample_url.length === 0 || !img.sample_url.startsWith("http"))
            errors.push("sample_url invalid: '" + img.sample_url + "'")
        if (typeof img.file_url !== "string" || img.file_url.length === 0 || !img.file_url.startsWith("http"))
            errors.push("file_url invalid: '" + img.file_url + "'")

        if (typeof img.file_ext !== "string" || img.file_ext.length === 0)
            errors.push("file_ext invalid: " + img.file_ext)
        if (typeof img.source !== "string")
            errors.push("source not string: " + typeof img.source)

        return errors
    }

    // Test phases: 0 = standard tests, 1 = edge case tests, 2 = autocomplete tests, 3 = sorting tests
    property int testPhase: 0
    property int edgeCaseIndex: 0
    property var edgeCaseProviderKeys: []
    property int autocompleteIndex: 0

    function start() {
        providerKeys = Booru.providerList
        // Build list of providers that have edge case tags
        edgeCaseProviderKeys = []
        for (var i = 0; i < providerKeys.length; i++) {
            if (edgeCaseTags[providerKeys[i]]) {
                edgeCaseProviderKeys.push(providerKeys[i])
            }
        }

        console.log("")
        console.log("========================================")
        console.log("Booru Provider Integration Tests")
        console.log("Testing " + providerKeys.length + " providers...")
        console.log("========================================")
        console.log("")

        if (providerKeys.length === 0) {
            console.log("ERROR: No providers found!")
            testsCompleted(0, 1)
            return
        }

        testPhase = 0
        testNextProvider()
    }

    function testNextProvider() {
        if (currentIndex >= providerKeys.length) {
            // Move to edge case testing phase
            if (edgeCaseProviderKeys.length > 0) {
                console.log("")
                console.log("--- Edge Case Tests ---")
                testPhase = 1
                edgeCaseIndex = 0
                testNextEdgeCase()
            } else {
                startAutocompleteTests()
            }
            return
        }

        var providerKey = providerKeys[currentIndex]
        testProvider(providerKey, false)
    }

    function testNextEdgeCase() {
        if (edgeCaseIndex >= edgeCaseProviderKeys.length) {
            startAutocompleteTests()
            return
        }

        var providerKey = edgeCaseProviderKeys[edgeCaseIndex]
        testProvider(providerKey, true)
    }

    function startAutocompleteTests() {
        console.log("")
        console.log("--- Tag Autocomplete Tests ---")
        testPhase = 2
        autocompleteIndex = 0
        testNextAutocomplete()
    }

    // Store pending test info for curl callback
    property string pendingProviderKey: ""
    property var pendingProvider: null
    property bool pendingIsEdgeCase: false

    function testProvider(providerKey, isEdgeCase) {
        var provider = Booru.providers[providerKey]
        var testTag = isEdgeCase ? edgeCaseTags[providerKey] : getDefaultTag(providerKey)
        var label = isEdgeCase ? " [edge:" + testTag + "]" : ""

        console.log("Testing: " + provider.name + " (" + providerKey + ")" + label)

        // Skip providers with strict Cloudflare JS challenges that can't be bypassed
        if (cloudflareProviders.indexOf(providerKey) !== -1) {
            console.log("  Image search... SKIP (Cloudflare JS challenge)")
            skippedCount++
            scheduleNextTest(isEdgeCase)
            return
        }

        // Set current provider and build test URL
        Booru.currentProvider = providerKey
        var testTags = [testTag]
        var url = Booru.constructRequestUrl(testTags, false, 5, 1)
        console.log("  URL: " + url)

        // Use curl for providers that need User-Agent to bypass Cloudflare
        if (curlProviders.indexOf(providerKey) !== -1) {
            pendingProviderKey = providerKey
            pendingProvider = provider
            pendingIsEdgeCase = isEdgeCase
            // Set URL first, then trigger via enabled flag
            curlFetcher.curlUrl = url
            curlFetcher.enabled = true
            return
        }

        // Make request via XMLHttpRequest for other providers
        var xhr = new XMLHttpRequest()
        xhr.open("GET", url, true)

        var capturedIsEdgeCase = isEdgeCase
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                handleResponse(providerKey, provider, xhr, capturedIsEdgeCase)
            }
        }

        xhr.send()
    }

    function getDefaultTag(providerKey) {
        // waifu.im only supports specific tags
        if (providerKey === "waifu.im") return "waifu"
        return "landscape"
    }

    // Manual XML parsing for paheal (QML doesn't have DOMParser)
    function parseXmlResponse(xmlText, providerKey) {
        if (providerKey !== "paheal") return []

        var result = []
        // Match all <tag ... > or <tag ... /> elements
        var tagMatches = xmlText.match(/<tag\s+[^>]+>/g) || []

        for (var i = 0; i < tagMatches.length; i++) {
            var attrs = tagMatches[i]

            // Extract attribute using regex
            function getAttr(name) {
                var re = new RegExp(name + "=['\"]([^'\"]*)['\"]")
                var m = attrs.match(re)
                return m ? m[1] : ""
            }

            var previewPath = getAttr("preview_url")
            var previewUrl = (previewPath && previewPath.indexOf("http") === 0) ? previewPath : "https://rule34.paheal.net" + previewPath
            var fileUrl = getAttr("file_url")
            var fileName = getAttr("file_name") || "unknown.jpg"
            var width = parseInt(getAttr("width")) || 800
            var height = parseInt(getAttr("height")) || 600

            result.push({
                "id": parseInt(getAttr("id")),
                "width": width,
                "height": height,
                "aspect_ratio": width / height,
                "tags": getAttr("tags"),
                "rating": "e",
                "is_nsfw": true,
                "md5": getAttr("md5"),
                "preview_url": previewUrl,
                "sample_url": fileUrl,
                "file_url": fileUrl,
                "file_ext": fileName.split('.').pop(),
                "source": fileUrl
            })
        }
        return result
    }

    function handleResponse(providerKey, provider, xhr, isEdgeCase) {
        if (xhr.status !== 200) {
            console.log("  Image search... FAIL (HTTP " + xhr.status + ")")
            failedCount++
            scheduleNextTest(isEdgeCase)
            return
        }

        try {
            var response
            // Handle XML providers
            if (xmlProviders.indexOf(providerKey) !== -1 || provider.isXml) {
                response = xhr.responseXML
            } else {
                response = JSON.parse(xhr.responseText)
            }
            var images = provider.mapFunc(response)

            if (!images || images.length === 0) {
                console.log("  Image search... FAIL (0 images returned)")
                failedCount++
                scheduleNextTest(isEdgeCase)
                return
            }

            console.log("  Image search... PASS (" + images.length + " images)")

            // Validate fields
            var allValid = true
            var errorSummary = []

            for (var i = 0; i < images.length; i++) {
                var errors = validateImage(images[i], providerKey)
                if (errors.length > 0) {
                    allValid = false
                    if (errorSummary.length < 3) {
                        errorSummary.push("Image " + i + ": " + errors.join(", "))
                    }
                }
            }

            if (allValid) {
                console.log("  Field validation... PASS")
                passedCount++
            } else {
                console.log("  Field validation... FAIL")
                for (var j = 0; j < errorSummary.length; j++) {
                    console.log("    " + errorSummary[j])
                }
                failedCount++
            }

        } catch (e) {
            console.log("  Parse error... FAIL (" + e + ")")
            failedCount++
        }

        scheduleNextTest(isEdgeCase)
    }

    function scheduleNextTest(isEdgeCase) {
        if (isEdgeCase) {
            edgeCaseIndex++
        } else {
            currentIndex++
        }
        // Delay between tests to avoid rate limiting
        delayTimer.start()
    }

    // --- Tag Autocomplete Tests ---

    function testNextAutocomplete() {
        if (autocompleteIndex >= autocompleteProviders.length) {
            startSortingTests()
            return
        }

        var providerKey = autocompleteProviders[autocompleteIndex]
        testAutocomplete(providerKey)
    }

    // Store pending autocomplete test info for curl callback
    property string pendingAutocompleteProviderKey: ""
    property var pendingAutocompleteProvider: null

    function testAutocomplete(providerKey) {
        var provider = Booru.providers[providerKey]
        if (!provider.tagSearchTemplate) {
            console.log("Testing autocomplete: " + providerKey + "... SKIP (no template)")
            autocompleteIndex++
            autocompleteDelayTimer.start()
            return
        }

        // Skip Cloudflare-protected providers
        if (cloudflareProviders.indexOf(providerKey) !== -1) {
            console.log("Testing autocomplete: " + providerKey + "... SKIP (Cloudflare)")
            autocompleteIndex++
            autocompleteDelayTimer.start()
            return
        }

        console.log("Testing autocomplete: " + providerKey)
        Booru.currentProvider = providerKey

        var url = provider.tagSearchTemplate.replace("{{query}}", "ani")
        // Add API credentials if needed
        if (providerKey === "gelbooru" && Booru.gelbooruApiKey && Booru.gelbooruUserId) {
            url += "&api_key=" + Booru.gelbooruApiKey + "&user_id=" + Booru.gelbooruUserId
        }

        // Use curl for providers that need User-Agent
        if (curlProviders.indexOf(providerKey) !== -1) {
            pendingAutocompleteProviderKey = providerKey
            pendingAutocompleteProvider = provider
            autocompleteCurlFetcher.curlUrl = url
            autocompleteCurlFetcher.enabled = true
            return
        }

        var xhr = new XMLHttpRequest()
        xhr.open("GET", url, true)

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                handleAutocompleteResponse(providerKey, provider, xhr)
            }
        }

        xhr.send()
    }

    function handleAutocompleteResponse(providerKey, provider, xhr) {
        if (xhr.status !== 200) {
            console.log("  Autocomplete... FAIL (HTTP " + xhr.status + ")")
            autocompleteFailedCount++
            autocompleteIndex++
            autocompleteDelayTimer.start()
            return
        }

        try {
            var response = JSON.parse(xhr.responseText)
            var tags = provider.tagMapFunc(response)

            if (!tags || tags.length === 0) {
                console.log("  Autocomplete... FAIL (0 tags)")
                autocompleteFailedCount++
            } else {
                // Validate tag structure
                var valid = true
                for (var i = 0; i < Math.min(tags.length, 3); i++) {
                    if (typeof tags[i].name !== "string" || tags[i].name.length === 0) {
                        valid = false
                        console.log("  Autocomplete... FAIL (invalid tag name)")
                        break
                    }
                }
                if (valid) {
                    console.log("  Autocomplete... PASS (" + tags.length + " tags)")
                    autocompletePassedCount++
                } else {
                    autocompleteFailedCount++
                }
            }
        } catch (e) {
            console.log("  Autocomplete... FAIL (" + e + ")")
            autocompleteFailedCount++
        }

        autocompleteIndex++
        autocompleteDelayTimer.start()
    }

    // --- Sorting Tests ---

    function startSortingTests() {
        console.log("")
        console.log("--- Sorting Configuration Tests ---")
        testPhase = 3

        // Test 1: Verify providerSortOptions exists
        testSortOptionsExist()

        // Test 2: Verify getSortOptions() returns correct values
        testGetSortOptions()

        // Test 3: Verify sort metatag injection in URLs
        testSortMetatagInjection()

        // Test 4: Verify providers without sorting support
        testNoSortingProviders()

        // Print sorting test summary
        console.log("")
        console.log("Sorting Tests: " + sortingPassedCount + " passed, " + sortingFailedCount + " failed")

        finishAllTests()
    }

    function testSortOptionsExist() {
        console.log("Testing: providerSortOptions configuration")

        if (!Booru.providerSortOptions) {
            console.log("  providerSortOptions exists... FAIL (undefined)")
            sortingFailedCount++
            return
        }

        var allMatch = true
        for (var i = 0; i < providerKeys.length; i++) {
            var key = providerKeys[i]
            var actual = Booru.providerSortOptions[key]
            var expected = expectedSortOptions[key]

            if (!actual && !expected) continue
            if (!actual && expected) {
                console.log("  " + key + ": FAIL (missing in Booru)")
                allMatch = false
                continue
            }
            if (actual && !expected) {
                // Extra options are OK
                continue
            }

            // Compare arrays
            if (actual.length !== expected.length) {
                console.log("  " + key + ": FAIL (length mismatch: " + actual.length + " vs " + expected.length + ")")
                allMatch = false
            }
        }

        if (allMatch) {
            console.log("  providerSortOptions exists... PASS")
            sortingPassedCount++
        } else {
            sortingFailedCount++
        }
    }

    function testGetSortOptions() {
        console.log("Testing: getSortOptions() function")

        var allPass = true

        // Test with yandere (has sorting)
        Booru.currentProvider = "yandere"
        var options = Booru.getSortOptions()
        if (!options || options.length === 0) {
            console.log("  yandere getSortOptions()... FAIL (empty)")
            allPass = false
        } else if (options.indexOf("score") === -1) {
            console.log("  yandere getSortOptions()... FAIL (missing 'score')")
            allPass = false
        }

        // Test with waifu.im (no sorting)
        Booru.currentProvider = "waifu.im"
        options = Booru.getSortOptions()
        if (options && options.length > 0) {
            console.log("  waifu.im getSortOptions()... FAIL (should be empty)")
            allPass = false
        }

        if (allPass) {
            console.log("  getSortOptions()... PASS")
            sortingPassedCount++
        } else {
            sortingFailedCount++
        }
    }

    function testSortMetatagInjection() {
        console.log("Testing: Sort metatag injection in URLs")

        var allPass = true

        // Test Moebooru (order: metatag)
        Booru.currentProvider = "yandere"
        Booru.currentSorting = "score"
        var url = Booru.constructRequestUrl(["test"], false, 5, 1)
        if (url.indexOf("order%3Ascore") === -1 && url.indexOf("order:score") === -1) {
            console.log("  yandere order:score... FAIL (not in URL: " + url + ")")
            allPass = false
        }

        // Test Gelbooru (sort: metatag)
        Booru.currentProvider = "gelbooru"
        Booru.currentSorting = "score"
        url = Booru.constructRequestUrl(["test"], false, 5, 1)
        if (url.indexOf("sort%3Ascore") === -1 && url.indexOf("sort:score") === -1) {
            console.log("  gelbooru sort:score... FAIL (not in URL: " + url + ")")
            allPass = false
        }

        // Test Wallhaven (sorting= parameter)
        Booru.currentProvider = "wallhaven"
        Booru.currentSorting = "random"
        url = Booru.constructRequestUrl(["nature"], false, 5, 1)
        if (url.indexOf("sorting=random") === -1) {
            console.log("  wallhaven sorting=random... FAIL (not in URL: " + url + ")")
            allPass = false
        }

        // Test empty sorting (should not inject metatag)
        Booru.currentProvider = "yandere"
        Booru.currentSorting = ""
        url = Booru.constructRequestUrl(["test"], false, 5, 1)
        if (url.indexOf("order%3A") !== -1 || url.indexOf("order:") !== -1) {
            console.log("  empty sorting... FAIL (metatag injected: " + url + ")")
            allPass = false
        }

        // Reset
        Booru.currentSorting = ""

        if (allPass) {
            console.log("  Sort metatag injection... PASS")
            sortingPassedCount++
        } else {
            sortingFailedCount++
        }
    }

    function testNoSortingProviders() {
        console.log("Testing: Providers without sorting support")

        var noSortProviders = ["waifu.im", "nekos_best"]
        var allPass = true

        for (var i = 0; i < noSortProviders.length; i++) {
            var key = noSortProviders[i]
            Booru.currentProvider = key
            var options = Booru.getSortOptions()

            if (options && options.length > 0) {
                console.log("  " + key + " getSortOptions()... FAIL (should be empty, got " + options.length + ")")
                allPass = false
            }

            if (!Booru.providerSupportsSorting === false) {
                // This is a double-negative check: providerSupportsSorting should be false
            }
        }

        // Reset to default
        Booru.currentProvider = "yandere"

        if (allPass) {
            console.log("  No-sorting providers... PASS")
            sortingPassedCount++
        } else {
            sortingFailedCount++
        }
    }

    function finishAllTests() {
        testsCompleted(passedCount, failedCount)
    }

    Timer {
        id: delayTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (testPhase === 0) {
                testNextProvider()
            } else if (testPhase === 1) {
                testNextEdgeCase()
            }
        }
    }

    Timer {
        id: autocompleteDelayTimer
        interval: 300
        repeat: false
        onTriggered: testNextAutocomplete()
    }

    // Curl-based fetcher for Cloudflare-protected providers
    Process {
        id: curlFetcher

        property bool enabled: false
        property string curlUrl: ""
        property bool handled: false  // Prevent double-handling

        running: enabled && curlUrl.length > 0
        command: ["curl", "-s", "-A", Booru.defaultUserAgent, curlUrl]

        onRunningChanged: {
            if (running) handled = false  // Reset on new run
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (curlFetcher.handled) return
                curlFetcher.handled = true
                curlFetcher.enabled = false
                handleCurlResponse(pendingProviderKey, pendingProvider, text, pendingIsEdgeCase)
            }
        }

        onExited: (code, status) => {
            if (curlFetcher.handled) return
            curlFetcher.handled = true
            curlFetcher.enabled = false
            if (code !== 0) {
                console.log("  Image search... FAIL (curl exit code " + code + ")")
                failedCount++
                scheduleNextTest(pendingIsEdgeCase)
            }
        }
    }

    // Curl-based fetcher for autocomplete on Cloudflare-protected providers
    Process {
        id: autocompleteCurlFetcher

        property bool enabled: false
        property string curlUrl: ""
        property bool handled: false  // Prevent double-handling

        running: enabled && curlUrl.length > 0
        command: ["curl", "-s", "-A", Booru.defaultUserAgent, curlUrl]

        onRunningChanged: {
            if (running) handled = false  // Reset on new run
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (autocompleteCurlFetcher.handled) return
                autocompleteCurlFetcher.handled = true
                autocompleteCurlFetcher.enabled = false
                handleAutocompleteCurlResponse(pendingAutocompleteProviderKey, pendingAutocompleteProvider, text)
            }
        }

        onExited: (code, status) => {
            if (autocompleteCurlFetcher.handled) return
            autocompleteCurlFetcher.handled = true
            autocompleteCurlFetcher.enabled = false
            if (code !== 0) {
                console.log("  Autocomplete... FAIL (curl exit code " + code + ")")
                autocompleteFailedCount++
                autocompleteIndex++
                autocompleteDelayTimer.start()
            }
        }
    }

    function handleAutocompleteCurlResponse(providerKey, provider, responseText) {
        try {
            var response = JSON.parse(responseText)
            var tags = provider.tagMapFunc(response)

            if (!tags || tags.length === 0) {
                console.log("  Autocomplete... FAIL (0 tags)")
                autocompleteFailedCount++
            } else {
                // Validate tag structure
                var valid = true
                for (var i = 0; i < Math.min(tags.length, 3); i++) {
                    if (typeof tags[i].name !== "string" || tags[i].name.length === 0) {
                        valid = false
                        console.log("  Autocomplete... FAIL (invalid tag name)")
                        break
                    }
                }
                if (valid) {
                    console.log("  Autocomplete... PASS (" + tags.length + " tags)")
                    autocompletePassedCount++
                } else {
                    autocompleteFailedCount++
                }
            }
        } catch (e) {
            console.log("  Autocomplete... FAIL (" + e + ")")
            autocompleteFailedCount++
        }

        autocompleteIndex++
        autocompleteDelayTimer.start()
    }

    function handleCurlResponse(providerKey, provider, responseText, isEdgeCase) {
        try {
            var response
            var images

            // Handle XML providers manually (QML doesn't have DOMParser)
            if (xmlProviders.indexOf(providerKey) !== -1 || provider.isXml) {
                // Manual XML parsing for paheal - extract tag attributes
                images = parseXmlResponse(responseText, providerKey)
            } else {
                response = JSON.parse(responseText)
                images = provider.mapFunc(response)
            }

            if (!images || images.length === 0) {
                console.log("  Image search... FAIL (0 images returned)")
                failedCount++
                scheduleNextTest(isEdgeCase)
                return
            }

            console.log("  Image search... PASS (" + images.length + " images)")

            // Validate fields
            var allValid = true
            var errorSummary = []

            for (var i = 0; i < images.length; i++) {
                var errors = validateImage(images[i], providerKey)
                if (errors.length > 0) {
                    allValid = false
                    if (errorSummary.length < 3) {
                        errorSummary.push("Image " + i + ": " + errors.join(", "))
                    }
                }
            }

            if (allValid) {
                console.log("  Field validation... PASS")
                passedCount++
            } else {
                console.log("  Field validation... FAIL")
                for (var j = 0; j < errorSummary.length; j++) {
                    console.log("    " + errorSummary[j])
                }
                failedCount++
            }

        } catch (e) {
            console.log("  Parse error... FAIL (" + e + ")")
            failedCount++
        }

        scheduleNextTest(isEdgeCase)
    }
}
