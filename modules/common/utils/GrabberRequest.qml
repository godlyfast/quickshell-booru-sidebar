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
Item {
    id: root

    // Required properties
    property string source: ""      // Grabber source name (e.g., "yande.re", "danbooru.donmai.us")
    property string tags: ""        // Search tags (space-separated)

    // Optional properties
    property int limit: 20          // Max results
    property int page: 1            // Page number (Grabber -p flag)
    property bool loadDetails: true // Fetch additional metadata (tag categories, sources)
    property bool isNsfw: false     // Include NSFW content
    property string user: ""        // Authentication username (Grabber -u flag)
    property string password: ""    // Authentication password/API key (Grabber -w flag)

    // Status
    property bool loading: false
    property string lastError: ""
    property bool responseHandled: false  // Prevent double signal emission
    property int timeoutMs: 60000  // Kill process after 60s (Grabber with --load-details can be slow)

    signal finished(var images)
    signal failed(string error)

    // Timeout timer to kill hanging processes
    Timer {
        id: processTimeout
        interval: root.timeoutMs
        running: grabberProcess.running
        onTriggered: {
            if (grabberProcess.running) {
                root.lastError = "Request timed out"
                root.responseHandled = true
                grabberProcess.kill()
                root.failed(root.lastError)
            }
        }
    }

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
            "-p", String(page),         // Page number
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

        grabberProcess.command = args
        loading = true
        lastError = ""
        responseHandled = false
        grabberProcess.running = true
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

    Process {
        id: grabberProcess
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                var output = text.trim()
                if (output.length === 0) {
                    root.lastError = "Empty response from Grabber"
                    root.responseHandled = true
                    root.failed(root.lastError)
                    return
                }

                try {
                    var items = JSON.parse(output)
                    if (!Array.isArray(items)) {
                        items = [items]
                    }
                    var mappedImages = root.mapGrabberResponse(items)
                    root.responseHandled = true
                    root.finished(mappedImages)
                } catch (e) {
                    root.lastError = "Failed to parse Grabber response: " + e
                    root.responseHandled = true
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
            root.loading = false
            // Only emit failed if not already handled by stdout parser
            if (code !== 0 && !root.responseHandled) {
                if (root.lastError.length === 0) {
                    root.lastError = "Grabber exited with code " + code
                }
                root.responseHandled = true
                root.failed(root.lastError)
            }
        }
    }
}
