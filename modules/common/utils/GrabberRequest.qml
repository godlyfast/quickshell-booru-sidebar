import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Makes a search request using imgbrd-grabber CLI with JSON output.
 *
 * Use this as a fallback when direct API requests fail (e.g., Cloudflare blocks).
 * Returns rich metadata including separated tag categories.
 *
 * The response maps Grabber's JSON format to our normalized image schema.
 */
Process {
    id: root

    // Required properties
    property string source: ""      // Grabber source name (e.g., "yande.re", "danbooru.donmai.us")
    property string tags: ""        // Search tags (space-separated)

    // Optional properties
    property int limit: 20          // Max results
    property bool loadDetails: true // Fetch additional metadata (tag categories, sources)
    property bool isNsfw: false     // Include NSFW content
    property string user: ""        // Authentication username (Grabber -u flag)
    property string password: ""    // Authentication password/API key (Grabber -w flag)

    // Status
    property bool loading: false
    property string lastError: ""

    signal finished(var images)
    signal failed(string error)

    running: false

    function startRequest() {
        if (source.length === 0) {
            lastError = "Source is required"
            failed(lastError)
            return
        }

        var searchTags = tags
        // Add rating filter if needed
        if (!isNsfw) {
            searchTags = "rating:safe " + searchTags
        }

        var args = [
            "/usr/bin/Grabber",
            "-c",                       // CLI mode (no GUI)
            "-s", source,               // Source website
            "-t", searchTags.trim(),    // Search tags
            "-m", String(limit),        // Max results
            "-j",                       // JSON output
            "--ri"                      // Return images
        ]

        if (loadDetails) {
            args.push("--load-details")
        }

        // Add authentication if provided
        if (user && user.length > 0) {
            args.push("-u", user)
        }
        if (password && password.length > 0) {
            args.push("-w", password)
        }

        command = args
        loading = true
        lastError = ""
        running = true
    }

    // Map Grabber response to our normalized image schema
    function mapGrabberResponse(items) {
        var result = []
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            // Build tags string from categories if available
            var tagString = ""
            if (item.general && Array.isArray(item.general)) {
                tagString = item.general.join(" ")
                if (item.artist) tagString = item.artist.join(" ") + " " + tagString
                if (item.character) tagString = item.character.join(" ") + " " + tagString
                if (item.copyright) tagString = item.copyright.join(" ") + " " + tagString
            } else if (item.tags) {
                tagString = item.tags
            }

            // Determine rating
            var rating = item.rating ? item.rating.charAt(0).toLowerCase() : "q"
            if (rating === "g") rating = "s"  // Danbooru 'general' -> 's' (safe)

            result.push({
                "id": item.id ? parseInt(item.id) : 0,
                "width": item.width ? parseInt(item.width) : 0,
                "height": item.height ? parseInt(item.height) : 0,
                "aspect_ratio": (item.width && item.height) ? parseInt(item.width) / parseInt(item.height) : 1,
                "tags": tagString.trim(),
                "rating": rating,
                "is_nsfw": (rating === "q" || rating === "e"),
                "md5": item.md5 ? item.md5 : "",
                "preview_url": item.url_thumbnail ? item.url_thumbnail : "",
                "sample_url": item.url_sample ? item.url_sample : (item.url_file ? item.url_file : ""),
                "file_url": item.url_file ? item.url_file : (item.url_original ? item.url_original : ""),
                "file_ext": item.ext ? item.ext : "jpg",
                "source": item.source ? item.source : (item.url_file ? item.url_file : ""),
                // Extra Grabber data
                "grabber_artist": item.artist ? item.artist : [],
                "grabber_character": item.character ? item.character : [],
                "grabber_copyright": item.copyright ? item.copyright : []
            })
        }
        return result
    }

    stdout: StdioCollector {
        onStreamFinished: {
            var output = text.trim()
            if (output.length === 0) {
                root.lastError = "Empty response from Grabber"
                root.failed(root.lastError)
                return
            }

            try {
                var items = JSON.parse(output)
                if (!Array.isArray(items)) {
                    items = [items]
                }
                var mappedImages = root.mapGrabberResponse(items)
                root.finished(mappedImages)
            } catch (e) {
                root.lastError = "Failed to parse Grabber response: " + e
                root.failed(root.lastError)
            }
        }
    }

    stderr: StdioCollector {
        onStreamFinished: {
            var errText = text.trim()
            if (errText.length > 0 && errText.indexOf("Error") >= 0) {
                root.lastError = errText
            }
        }
    }

    onExited: (code, status) => {
        loading = false
        if (code !== 0 && lastError.length === 0) {
            lastError = "Grabber exited with code " + code
            failed(lastError)
        }
    }
}
