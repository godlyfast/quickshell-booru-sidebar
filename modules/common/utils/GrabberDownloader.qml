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

    // Shell-escape for single-quoted bash strings
    function esc(s) { return s.replace(/'/g, "'\\''") }

    function startDownload() {
        if (source.length === 0 || imageId.length === 0 || outputPath.length === 0) {
            lastError = "Missing required properties"
            done(false, lastError)
            return
        }

        var grabberArgs = [
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
            grabberArgs.push("-n")      // Skip duplicates
        }

        // Add authentication if provided
        if (user && user.length > 0) {
            grabberArgs.push("-u", user)
        }
        if (password && password.length > 0) {
            grabberArgs.push("-w", password)
        }

        // Wrap in bash to verify file creation.
        // Grabber reports "Downloaded images successfully." with exit code 0 even when
        // 0 files are downloaded (e.g., provider doesn't support id: search).
        // The wrapper creates the output dir, counts files before/after, and exits 1
        // if no new file appeared - allowing callers to fall back to curl.
        var quoted = grabberArgs.map(function(a) { return "'" + esc(a) + "'" }).join(" ")
        var ep = esc(outputPath)
        var script =
            "mkdir -p '" + ep + "' && " +
            "BEFORE=$(find '" + ep + "' -maxdepth 1 -type f | wc -l) && " +
            quoted + "; GRC=$?; " +
            "AFTER=$(find '" + ep + "' -maxdepth 1 -type f | wc -l); " +
            "if [ $GRC -ne 0 ]; then exit $GRC; fi; " +
            "if [ \"$AFTER\" -gt \"$BEFORE\" ]; then " +
            "  NEWFILE=$(ls -1t '" + ep + "' | head -1); " +
            "  echo \"Downloaded to '${NEWFILE}'\"; " +
            "else " +
            "  echo 'No files downloaded (provider may not support id: search)' >&2; exit 1; " +
            "fi"

        command = ["bash", "-c", script]
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
