import QtQuick
import "./services"
import "./modules/common"

/**
 * Integration tests for all booru providers.
 * Validates that APIs return correct data and all required fields are present.
 * Also tests edge cases like null URL fallbacks and tag autocomplete.
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

    // Providers known to use Cloudflare JS challenges that QML can't handle
    property var cloudflareProviders: ["danbooru"]

    // Edge case tags - providers where default "landscape" may not catch null URL issues
    // "solo" on e621/e926 often has posts with null sample_url
    property var edgeCaseTags: {
        "e621": "solo",
        "e926": "solo"
    }

    // Providers that support tag autocomplete
    property var autocompleteProviders: ["yandere", "konachan", "gelbooru", "safebooru",
                                          "e621", "e926", "konachan_com"]

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

    // Test phases: 0 = standard tests, 1 = edge case tests, 2 = autocomplete tests
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

    function testProvider(providerKey, isEdgeCase) {
        var provider = Booru.providers[providerKey]
        var testTag = isEdgeCase ? edgeCaseTags[providerKey] : getDefaultTag(providerKey)
        var label = isEdgeCase ? " [edge:" + testTag + "]" : ""

        console.log("Testing: " + provider.name + " (" + providerKey + ")" + label)

        // Set current provider and build test URL
        Booru.currentProvider = providerKey
        var testTags = [testTag]
        var url = Booru.constructRequestUrl(testTags, false, 5, 1)
        console.log("  URL: " + url)

        // Make request
        var xhr = new XMLHttpRequest()
        xhr.open("GET", url, true)

        // Set User-Agent for Cloudflare-protected providers
        if (providerKey === "danbooru" || providerKey === "e621" || providerKey === "e926") {
            try {
                xhr.setRequestHeader("User-Agent", Booru.defaultUserAgent)
            } catch (e) {
                console.log("  Warning: Could not set User-Agent")
            }
        }

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

    function handleResponse(providerKey, provider, xhr, isEdgeCase) {
        if (xhr.status !== 200) {
            // Mark Cloudflare-protected providers as SKIP (403 = Cloudflare challenge)
            if (xhr.status === 403 && cloudflareProviders.indexOf(providerKey) !== -1) {
                console.log("  Image search... SKIP (Cloudflare protected)")
                skippedCount++
            } else {
                console.log("  Image search... FAIL (HTTP " + xhr.status + ")")
                failedCount++
            }
            scheduleNextTest(isEdgeCase)
            return
        }

        try {
            var response = JSON.parse(xhr.responseText)
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
            finishAllTests()
            return
        }

        var providerKey = autocompleteProviders[autocompleteIndex]
        // Skip Cloudflare-protected providers
        if (cloudflareProviders.indexOf(providerKey) !== -1) {
            console.log("Testing autocomplete: " + providerKey + "... SKIP (Cloudflare)")
            autocompleteIndex++
            autocompleteDelayTimer.start()
            return
        }

        testAutocomplete(providerKey)
    }

    function testAutocomplete(providerKey) {
        var provider = Booru.providers[providerKey]
        if (!provider.tagSearchTemplate) {
            console.log("Testing autocomplete: " + providerKey + "... SKIP (no template)")
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

        var xhr = new XMLHttpRequest()
        xhr.open("GET", url, true)

        if (providerKey === "e621" || providerKey === "e926") {
            try {
                xhr.setRequestHeader("User-Agent", Booru.defaultUserAgent)
            } catch (e) {}
        }

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
}
