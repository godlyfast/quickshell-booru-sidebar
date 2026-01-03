import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Downloads an image using imgbrd-grabber CLI with customizable filename templates.
 *
 * Uses Grabber's download mode which supports:
 * - Artist-aware filenames: %artist%, %copyright%, %character%
 * - Metadata tokens: %website%, %id%, %md5%, %rating%
 * - Automatic deduplication with -n flag
 *
 * Example templates:
 * - "%website% %id% - %artist%.%ext%"     → "yande.re 1249799 - kantoku.jpg"
 * - "%id%_%md5%.%ext%"                     → "1249799_abc123.jpg"
 * - "%copyright% - %character%.%ext%"      → "original - hatsune_miku.jpg"
 */
Process {
    id: root

    // Required properties
    property string source: ""          // Grabber source name (e.g., "yande.re", "danbooru.donmai.us")
    property string imageId: ""         // Post ID to download
    property string outputPath: ""      // Directory to save to

    // Optional properties
    property string filenameTemplate: "%website% %id%.%ext%"  // Grabber filename tokens
    property bool noDuplicates: true    // Skip if file exists
    property string user: ""            // Authentication username
    property string password: ""        // Authentication password/API key

    // Status
    property bool downloading: false
    property string lastError: ""

    signal done(bool success, string message)

    running: false

    // Build command when started
    onRunningChanged: {
        if (running) {
            downloading = true
            lastError = ""
        }
    }

    function startDownload() {
        if (source.length === 0 || imageId.length === 0 || outputPath.length === 0) {
            lastError = "Missing required properties"
            done(false, lastError)
            return
        }

        var args = [
            "/usr/bin/Grabber",
            "-c",                       // CLI mode (no GUI)
            "-s", source,               // Source website
            "-t", "id:" + imageId,      // Search by ID
            "-m", "1",                  // Max 1 result
            "--download",               // Download mode
            "-l", outputPath,           // Output directory
            "-f", filenameTemplate      // Filename template
        ]

        if (noDuplicates) {
            args.push("-n")             // Skip duplicates
        }

        // Add authentication if provided
        if (user && user.length > 0) {
            args.push("-u", user)
        }
        if (password && password.length > 0) {
            args.push("-w", password)
        }

        command = args
        running = true
    }

    property string lastOutput: ""

    stdout: StdioCollector {
        onStreamFinished: {
            // Store output but don't report success here - wait for onExited
            root.lastOutput = text.trim()
        }
    }

    stderr: StdioCollector {
        onStreamFinished: {
            var errText = text.trim()
            if (errText.length > 0) {
                root.lastError = errText
            }
        }
    }

    onExited: function(code, status) {
        downloading = false
        // Success: exit code 0 AND stdout contains "successfully" OR has download path
        var isSuccess = (code === 0) && (
            root.lastOutput.indexOf("successfully") >= 0 ||
            root.lastOutput.indexOf("Downloaded") >= 0 ||
            (root.lastOutput.length > 0 && root.lastError.length === 0)
        )
        if (isSuccess) {
            done(true, root.lastOutput)
        } else {
            if (lastError.length === 0) {
                lastError = "Grabber exited with code " + code
            }
            done(false, lastError)
        }
    }
}
