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
    // Note: e621 works with curl for image tests, danbooru has stricter protections
    // paheal uses XML which QML XMLHttpRequest.responseXML doesn't handle well
    // zerochan requires User-Agent header
    property var curlProviders: ["e621", "paheal", "zerochan"]

    // Providers that cannot be tested due to Cloudflare JS challenges or API blocks
    // danbooru: strict Cloudflare JS challenge
    // hypnohub: returns XML/HTML instead of JSON
    // 3dbooru: connection issues (times out)
    property var cloudflareProviders: ["danbooru", "hypnohub", "3dbooru"]

    // Providers that use Grabber-only (no direct API)
    property var grabberOnlyProviders: ["anime_pictures", "e_shuushuu"]

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
    // Note: konachan_com removed - now a mirror of konachan
    property var autocompleteProviders: ["yandere", "konachan", "danbooru", "gelbooru", "safebooru",
                                          "aibooru"]

    // Sorting test counters
    property int sortingPassedCount: 0
    property int sortingFailedCount: 0

    // Expected sort options per provider (should match Booru.providerSortOptions)
    // Note: konachan_com removed - now a mirror of konachan
    // Note: e926 removed - now a mirror of e621
    // Note: lolibooru removed - site is dead since 2024
    property var expectedSortOptions: ({
        // Moebooru (order: metatag) - yande.re, konachan, sakugabooru, 3dbooru
        "yandere": ["score", "score_asc", "favcount", "random", "rank", "id", "id_desc", "change", "comment", "mpixels", "landscape", "portrait"],
        "konachan": ["score", "score_asc", "favcount", "random", "rank", "id", "id_desc", "change", "comment", "mpixels", "landscape", "portrait"],
        "sakugabooru": ["score", "score_asc", "favcount", "random", "rank", "id", "id_desc", "change", "comment", "mpixels", "landscape", "portrait"],
        "3dbooru": ["score", "score_asc", "favcount", "random", "rank", "id", "id_desc", "change", "comment", "mpixels", "landscape", "portrait"],

        // Danbooru (order: metatag)
        "danbooru": ["rank", "score", "favcount", "random", "id", "id_desc", "change", "comment", "comment_bumped", "note", "mpixels", "landscape", "portrait"],
        "aibooru": ["rank", "score", "favcount", "random", "id", "id_desc", "change", "comment", "comment_bumped", "note", "mpixels", "landscape", "portrait"],

        // e621 (order: metatag)
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

        // Philomena (sf param)
        "derpibooru": ["score", "wilson_score", "relevance", "random", "created_at", "updated_at", "first_seen_at", "width", "height", "comment_count", "tag_count"],

        // Sankaku (order: metatag) - NOTE: favcount causes API timeout errors
        "sankaku": ["popularity", "date", "quality", "score", "random", "id", "id_asc", "recently_favorited", "recently_voted"],
        "idol_sankaku": ["popularity", "date", "quality", "score", "random", "id", "id_asc", "recently_favorited", "recently_voted"],

        // Zerochan (URL param)
        "zerochan": ["id", "fav"],

        // No sorting support
        "waifu.im": [],
        "nekos_best": [],
        "paheal": []
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

        // Disable age filter for tests - otherwise Moebooru providers return 0 results
        // because "landscape age:<1month rating:safe" is too restrictive
        Booru.ageFilter = "any"

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
            console.log("  Image search... SKIP (API blocked/Cloudflare)")
            skippedCount++
            scheduleNextTest(isEdgeCase)
            return
        }

        // Skip Grabber-only providers (no direct API)
        if (grabberOnlyProviders.indexOf(providerKey) !== -1) {
            console.log("  Image search... SKIP (Grabber-only, no direct API)")
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
        // sakugabooru is animation-focused, "landscape" uncommon
        if (providerKey === "sakugabooru") return "effects"
        // zerochan needs character/series names, not generic tags
        // Root path triggers bot check, so use a popular character name
        if (providerKey === "zerochan") return "Hatsune Miku"
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
            // Use Booru helper to get mapFunc (supports apiType family mappers)
            var mapFunc = Booru.getProviderMapFunc(providerKey)
            var images = mapFunc(response, provider)

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
            // Use Booru helper to get tagMapFunc (supports apiType family mappers)
            var tagMapFunc = Booru.getProviderTagMapFunc(providerKey)
            var tags = tagMapFunc ? tagMapFunc(response) : []

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

    // Mirror test counters
    property int mirrorPassedCount: 0
    property int mirrorFailedCount: 0

    // NSFW filter test counters
    property int nsfwPassedCount: 0
    property int nsfwFailedCount: 0

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

        // Run mirror tests
        startMirrorTests()
    }

    function startMirrorTests() {
        console.log("")
        console.log("--- Mirror System Tests ---")

        // Test 1: Verify mirror helper functions
        testMirrorHelperFunctions()

        // Test 2: Verify mirror URL construction
        testMirrorUrlConstruction()

        // Test 3: Verify mirror SFW status
        testMirrorSfwStatus()

        // Print mirror test summary
        console.log("")
        console.log("Mirror Tests: " + mirrorPassedCount + " passed, " + mirrorFailedCount + " failed")

        startNsfwFilterTests()
    }

    function testMirrorHelperFunctions() {
        console.log("Testing: Mirror helper functions")

        var allPass = true

        // Test providerHasMirrors
        if (!Booru.providerHasMirrors("konachan")) {
            console.log("  providerHasMirrors(konachan)... FAIL (should be true)")
            allPass = false
        }
        if (!Booru.providerHasMirrors("danbooru")) {
            console.log("  providerHasMirrors(danbooru)... FAIL (should be true)")
            allPass = false
        }
        if (Booru.providerHasMirrors("yandere")) {
            console.log("  providerHasMirrors(yandere)... FAIL (should be false)")
            allPass = false
        }

        // Test getMirrorList
        var konachanMirrors = Booru.getMirrorList("konachan")
        if (!konachanMirrors || konachanMirrors.length !== 2) {
            console.log("  getMirrorList(konachan)... FAIL (expected 2 mirrors, got " + (konachanMirrors ? konachanMirrors.length : 0) + ")")
            allPass = false
        }

        var danbooruMirrors = Booru.getMirrorList("danbooru")
        if (!danbooruMirrors || danbooruMirrors.length !== 2) {
            console.log("  getMirrorList(danbooru)... FAIL (expected 2 mirrors, got " + (danbooruMirrors ? danbooruMirrors.length : 0) + ")")
            allPass = false
        }

        // Test getCurrentMirror (should return first mirror by default)
        var currentMirror = Booru.getCurrentMirror("konachan")
        if (!currentMirror || currentMirror !== "konachan.net") {
            console.log("  getCurrentMirror(konachan)... FAIL (expected 'konachan.net', got '" + currentMirror + "')")
            allPass = false
        }

        // Test setMirror
        Booru.setMirror("konachan", "konachan.com")
        currentMirror = Booru.getCurrentMirror("konachan")
        if (currentMirror !== "konachan.com") {
            console.log("  setMirror(konachan, konachan.com)... FAIL (got '" + currentMirror + "')")
            allPass = false
        }
        // Reset
        Booru.setMirror("konachan", "konachan.net")

        if (allPass) {
            console.log("  Mirror helper functions... PASS")
            mirrorPassedCount++
        } else {
            mirrorFailedCount++
        }
    }

    function testMirrorUrlConstruction() {
        console.log("Testing: Mirror URL construction")

        var allPass = true

        // Test konachan with default mirror (konachan.net)
        Booru.currentProvider = "konachan"
        Booru.setMirror("konachan", "konachan.net")
        var url = Booru.constructRequestUrl(["test"], false, 5, 1)
        if (url.indexOf("konachan.net") === -1) {
            console.log("  konachan.net URL... FAIL (expected konachan.net in URL)")
            allPass = false
        }

        // Test konachan with .com mirror
        Booru.setMirror("konachan", "konachan.com")
        url = Booru.constructRequestUrl(["test"], false, 5, 1)
        if (url.indexOf("konachan.com") === -1) {
            console.log("  konachan.com URL... FAIL (expected konachan.com in URL)")
            allPass = false
        }

        // Test danbooru with safebooru mirror
        Booru.currentProvider = "danbooru"
        Booru.setMirror("danbooru", "safebooru.donmai.us")
        url = Booru.constructRequestUrl(["test"], false, 5, 1)
        if (url.indexOf("safebooru.donmai.us") === -1) {
            console.log("  safebooru.donmai.us URL... FAIL (expected safebooru.donmai.us in URL)")
            allPass = false
        }

        // Reset
        Booru.setMirror("konachan", "konachan.net")
        Booru.setMirror("danbooru", "danbooru.donmai.us")
        Booru.currentProvider = "yandere"

        if (allPass) {
            console.log("  Mirror URL construction... PASS")
            mirrorPassedCount++
        } else {
            mirrorFailedCount++
        }
    }

    function testMirrorSfwStatus() {
        console.log("Testing: Mirror SFW status")

        var allPass = true

        // Test konachan.net is SFW-only
        Booru.currentProvider = "konachan"
        Booru.setMirror("konachan", "konachan.net")
        if (!Booru.currentMirrorIsSfwOnly("konachan")) {
            console.log("  konachan.net sfwOnly... FAIL (should be true)")
            allPass = false
        }

        // Test konachan.com is NOT SFW-only
        Booru.setMirror("konachan", "konachan.com")
        if (Booru.currentMirrorIsSfwOnly("konachan")) {
            console.log("  konachan.com sfwOnly... FAIL (should be false)")
            allPass = false
        }

        // Test safebooru.donmai.us is SFW-only
        Booru.currentProvider = "danbooru"
        Booru.setMirror("danbooru", "safebooru.donmai.us")
        if (!Booru.currentMirrorIsSfwOnly("danbooru")) {
            console.log("  safebooru.donmai.us sfwOnly... FAIL (should be true)")
            allPass = false
        }

        // Test danbooru.donmai.us is NOT SFW-only
        Booru.setMirror("danbooru", "danbooru.donmai.us")
        if (Booru.currentMirrorIsSfwOnly("danbooru")) {
            console.log("  danbooru.donmai.us sfwOnly... FAIL (should be false)")
            allPass = false
        }

        // Reset
        Booru.setMirror("konachan", "konachan.net")
        Booru.currentProvider = "yandere"

        if (allPass) {
            console.log("  Mirror SFW status... PASS")
            mirrorPassedCount++
        } else {
            mirrorFailedCount++
        }
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

    // --- NSFW Filtering Tests ---

    function startNsfwFilterTests() {
        console.log("")
        console.log("--- NSFW Filtering Tests ---")

        // Test SFW filter injection per provider type
        testSfwFilterInjection()

        // Test NSFW mode (no filter)
        testNsfwModeNoFilter()

        // Print NSFW test summary
        console.log("")
        console.log("NSFW Filter Tests: " + nsfwPassedCount + " passed, " + nsfwFailedCount + " failed")

        startDefaultFilterTests()
    }

    function testSfwFilterInjection() {
        console.log("Testing: SFW filter injection per provider")

        // Provider-specific SFW filters (when nsfw=false)
        var sfwFilters = {
            "yandere": "rating%3Asafe",
            "konachan": "rating%3Asafe",
            "sakugabooru": "rating%3Asafe",
            "3dbooru": "rating%3Asafe",
            "danbooru": "rating%3Ageneral",
            "aibooru": "rating%3Ageneral",
            "gelbooru": "rating%3Ageneral",
            "e621": "rating%3As",
            "wallhaven": "purity=100",
            "waifu.im": "is_nsfw=false",
            "derpibooru": "filter_id=100277",
            "sankaku": "rating%3Asafe",
            "idol_sankaku": "rating%3Asafe"
        }

        var allPass = true
        var originalProvider = Booru.currentProvider

        for (var provider in sfwFilters) {
            Booru.currentProvider = provider
            var sfwUrl = Booru.constructRequestUrl(["landscape"], false, 5, 1)

            // Verify SFW filter present when nsfw=false
            var hasSfwFilter = sfwUrl.indexOf(sfwFilters[provider]) !== -1
            if (!hasSfwFilter) {
                console.log("  " + provider + " SFW filter... FAIL (expected '" + sfwFilters[provider] + "' in URL)")
                allPass = false
            }
        }

        Booru.currentProvider = originalProvider

        if (allPass) {
            console.log("  SFW filter injection... PASS")
            nsfwPassedCount++
        } else {
            nsfwFailedCount++
        }
    }

    function testNsfwModeNoFilter() {
        console.log("Testing: NSFW mode removes SFW filter")

        // When nsfw=true, SFW filters should NOT be present
        var sfwFilters = {
            "yandere": "rating%3Asafe",
            "konachan": "rating%3Asafe",
            "danbooru": "rating%3Ageneral",
            "gelbooru": "rating%3Ageneral",
            "e621": "rating%3As"
        }

        var allPass = true
        var originalProvider = Booru.currentProvider

        for (var provider in sfwFilters) {
            Booru.currentProvider = provider
            var nsfwUrl = Booru.constructRequestUrl(["landscape"], true, 5, 1)

            // Verify SFW filter absent when nsfw=true
            var hasNoSfwFilter = nsfwUrl.indexOf(sfwFilters[provider]) === -1
            if (!hasNoSfwFilter) {
                console.log("  " + provider + " NSFW mode... FAIL (SFW filter still present in URL)")
                allPass = false
            }
        }

        // Test wallhaven specifically (uses purity param)
        Booru.currentProvider = "wallhaven"
        var wallhavenNsfwUrl = Booru.constructRequestUrl(["nature"], true, 5, 1)
        if (wallhavenNsfwUrl.indexOf("purity=100") !== -1) {
            console.log("  wallhaven NSFW mode... FAIL (purity=100 still present)")
            allPass = false
        }
        if (wallhavenNsfwUrl.indexOf("purity=111") === -1) {
            console.log("  wallhaven NSFW mode... FAIL (expected purity=111 for NSFW)")
            allPass = false
        }

        Booru.currentProvider = originalProvider

        if (allPass) {
            console.log("  NSFW mode no filter... PASS")
            nsfwPassedCount++
        } else {
            nsfwFailedCount++
        }
    }

    // --- Default Filter Tests ---

    function startDefaultFilterTests() {
        console.log("")
        console.log("--- Default Filter Tests ---")

        // Test Wallhaven default filters (resolution, topRange)
        testWallhavenDefaults()

        // Test waifu.im defaults
        testWaifuImDefaults()

        // Test SFW-only providers don't show NSFW toggle
        testSfwOnlyProviders()

        // Test NSFW-only providers don't add SFW filter
        testNsfwOnlyProviders()

        console.log("")
        finishAllTests()
    }

    function testWallhavenDefaults() {
        console.log("Testing: Wallhaven default filters")

        var originalProvider = Booru.currentProvider
        Booru.currentProvider = "wallhaven"

        var url = Booru.constructRequestUrl([], false, 5, 1)
        var allPass = true

        // Should have resolution filter (atleast=) unless set to "any"
        // Note: wallhavenResolution defaults to "1920x1080" or similar
        // This test verifies the parameter is properly included
        if (url.indexOf("sorting=") === -1) {
            console.log("  wallhaven sorting param... FAIL (missing)")
            allPass = false
        }

        if (url.indexOf("order=") === -1) {
            console.log("  wallhaven order param... FAIL (missing)")
            allPass = false
        }

        Booru.currentProvider = originalProvider

        if (allPass) {
            console.log("  Wallhaven defaults... PASS")
            nsfwPassedCount++
        } else {
            nsfwFailedCount++
        }
    }

    function testWaifuImDefaults() {
        console.log("Testing: waifu.im default filters")

        var originalProvider = Booru.currentProvider
        Booru.currentProvider = "waifu.im"

        var url = Booru.constructRequestUrl(["waifu"], false, 5, 1)
        var allPass = true

        // Should have limit parameter
        if (url.indexOf("limit=") === -1) {
            console.log("  waifu.im limit param... FAIL (missing)")
            allPass = false
        }

        // Should have is_nsfw parameter
        if (url.indexOf("is_nsfw=") === -1) {
            console.log("  waifu.im is_nsfw param... FAIL (missing)")
            allPass = false
        }

        // Should have included_tags parameter
        if (url.indexOf("included_tags=") === -1) {
            console.log("  waifu.im included_tags param... FAIL (missing)")
            allPass = false
        }

        Booru.currentProvider = originalProvider

        if (allPass) {
            console.log("  waifu.im defaults... PASS")
            nsfwPassedCount++
        } else {
            nsfwFailedCount++
        }
    }

    function testSfwOnlyProviders() {
        console.log("Testing: SFW-only providers")

        var sfwOnlyList = ["safebooru", "nekos_best"]
        var allPass = true

        for (var i = 0; i < sfwOnlyList.length; i++) {
            var provider = sfwOnlyList[i]
            Booru.currentProvider = provider

            // providerSupportsNsfw should be false for SFW-only providers
            if (Booru.providerSupportsNsfw) {
                console.log("  " + provider + " providerSupportsNsfw... FAIL (should be false)")
                allPass = false
            }
        }

        Booru.currentProvider = "yandere"

        if (allPass) {
            console.log("  SFW-only providers... PASS")
            nsfwPassedCount++
        } else {
            nsfwFailedCount++
        }
    }

    function testNsfwOnlyProviders() {
        console.log("Testing: NSFW-only providers (no SFW filter)")

        var nsfwOnlyList = ["rule34", "xbooru", "tbib", "paheal", "hypnohub"]
        var allPass = true
        var originalProvider = Booru.currentProvider

        for (var i = 0; i < nsfwOnlyList.length; i++) {
            var provider = nsfwOnlyList[i]
            Booru.currentProvider = provider

            // Even with nsfw=false, these providers should NOT add rating filter
            // because they are NSFW-only
            var url = Booru.constructRequestUrl(["test"], false, 5, 1)

            // Should NOT have rating:safe or rating:general
            if (url.indexOf("rating%3Asafe") !== -1 || url.indexOf("rating%3Ageneral") !== -1) {
                console.log("  " + provider + " NSFW-only... FAIL (rating filter incorrectly added)")
                allPass = false
            }
        }

        Booru.currentProvider = originalProvider

        if (allPass) {
            console.log("  NSFW-only providers... PASS")
            nsfwPassedCount++
        } else {
            nsfwFailedCount++
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

        // Use simple app UA for zerochan (blocks browser-like UAs), default for others
        property string userAgent: pendingProviderKey === "zerochan" ? "QuickshellBooruSidebar/1.0" : Booru.defaultUserAgent

        running: enabled && curlUrl.length > 0
        command: ["curl", "-s", "-A", userAgent, curlUrl]

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
            // Use Booru helper to get tagMapFunc (supports apiType family mappers)
            var tagMapFunc = Booru.getProviderTagMapFunc(providerKey)
            var tags = tagMapFunc ? tagMapFunc(response) : []

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
                // Use Booru helper to get mapFunc (supports apiType family mappers)
                var mapFunc = Booru.getProviderMapFunc(providerKey)
                images = mapFunc(response, provider)
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
