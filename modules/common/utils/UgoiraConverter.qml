import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Converts ugoira ZIP archives to WebM video for playback.
 *
 * Ugoira is Pixiv's animation format: a ZIP of numbered JPEG frames.
 * This component extracts the frames and uses ffmpeg to create a video.
 *
 * Usage:
 *   UgoiraConverter {
 *       zipPath: "/path/to/ugoira.zip"
 *       outputPath: "/path/to/output.webm"
 *       onDone: (success, path) => { if (success) playVideo(path) }
 *   }
 */
Process {
    id: root

    // Required properties
    property string zipPath: ""       // Path to ugoira ZIP file
    property string outputPath: ""    // Output WebM path

    // Optional properties
    property int framerate: 24        // Default framerate (no timing data available from API)
    property int crf: 30              // Quality (lower = better, 0-63)

    // Status
    property bool converting: false
    property string lastError: ""

    signal done(bool success, string videoPath)

    running: false

    onRunningChanged: {
        if (running) {
            converting = true
            lastError = ""
        }
    }

    function convert() {
        console.log("[UgoiraConverter] convert() called: zipPath=" + zipPath + " outputPath=" + outputPath)
        if (zipPath.length === 0 || outputPath.length === 0) {
            console.log("[UgoiraConverter] ERROR: Missing zipPath or outputPath")
            lastError = "Missing zipPath or outputPath"
            done(false, "")
            return
        }

        // Build bash script to:
        // 1. Create temp directory
        // 2. Extract ZIP
        // 3. Convert to WebM with ffmpeg
        // 4. Clean up temp directory
        var script = [
            "set -e",
            "TMPDIR=$(mktemp -d)",
            "trap 'rm -rf \"$TMPDIR\"' EXIT",
            "unzip -q '" + zipPath + "' -d \"$TMPDIR\"",
            "cd \"$TMPDIR\"",
            "ffmpeg -y -framerate " + framerate + " -i %06d.jpg -c:v libvpx-vp9 -pix_fmt yuv420p -crf " + crf + " -b:v 0 '" + outputPath + "' 2>/dev/null",
            "echo 'SUCCESS'"
        ].join(" && ")

        command = ["bash", "-c", script]
        running = true
    }

    stdout: StdioCollector {
        onStreamFinished: {
            var output = text.trim()
            if (output.indexOf("SUCCESS") >= 0) {
                root.done(true, root.outputPath)
            }
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

    onExited: (code, status) => {
        console.log("[UgoiraConverter] Process exited: code=" + code + " lastError=" + lastError)
        converting = false
        if (code !== 0) {
            if (lastError.length === 0) {
                lastError = "Conversion failed with code " + code
            }
            console.log("[UgoiraConverter] Conversion FAILED: " + lastError)
            done(false, "")
        }
    }
}
