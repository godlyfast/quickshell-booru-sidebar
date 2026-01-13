import QtQuick
import Quickshell
import Quickshell.Io
import "../functions/shell_utils.js" as ShellUtils

/**
 * Downloads an image via curl and emits done signal with path and dimensions.
 * Adapted from end-4/dots-hyprland
 * Supports multiple fallback URLs for providers like zerochan where extension may vary.
 */
Item {
    id: root
    property bool enabled: false
    property string filePath
    property string sourceUrl
    property var fallbackUrls: []  // Array of fallback URLs to try if sourceUrl fails (e.g., zerochan extensions)
    property int imageWidth: 0
    property int imageHeight: 0
    property int timeoutMs: 30000  // Kill process after 30s if hanging
    property bool timedOut: false

    // Expose running state from the internal process
    readonly property bool running: downloaderProcess.running

    signal done(string path, int imgWidth, int imgHeight)

    // Timeout timer to kill hanging processes
    Timer {
        id: processTimeout
        interval: root.timeoutMs
        running: downloaderProcess.running
        onTriggered: {
            if (downloaderProcess.running) {
                root.timedOut = true
                downloaderProcess.kill()
            }
        }
    }

    // Shell escape helper - use shared utility
    function shellEscape(str) { return ShellUtils.shellEscape(str) }

    // Build fallback chain: || curl url1 || curl url2 || ...
    property string fallbackChain: {
        if (!fallbackUrls || fallbackUrls.length === 0) return ""
        var chain = ""
        for (var i = 0; i < fallbackUrls.length; i++) {
            if (fallbackUrls[i] && fallbackUrls[i].length > 0) {
                chain += " || curl -fsSL -A 'Mozilla/5.0 BooruSidebar/1.0' '" + shellEscape(fallbackUrls[i]) + "' -o '" + shellEscape(filePath) + "'"
            }
        }
        return chain
    }

    Process {
        id: downloaderProcess
        running: root.enabled && root.sourceUrl.length > 0

        onRunningChanged: {
            if (running) {
                root.timedOut = false
            }
        }

        command: ["bash", "-c",
            "mkdir -p \"$(dirname '" + root.shellEscape(root.filePath) + "')\" && " +
            // Re-download if: file missing, empty, or HTML error page
            "if [ ! -s '" + root.shellEscape(root.filePath) + "' ] || file '" + root.shellEscape(root.filePath) + "' | grep -q 'HTML'; then " +
            "  rm -f '" + root.shellEscape(root.filePath) + "'; " +
            "  (curl -fsSL -A 'Mozilla/5.0 BooruSidebar/1.0' '" + root.shellEscape(root.sourceUrl) + "' -o '" + root.shellEscape(root.filePath) + "'" + root.fallbackChain + "); " +
            "fi && " +
            "if [ -s '" + root.shellEscape(root.filePath) + "' ] && file -b '" + root.shellEscape(root.filePath) + "' | grep -qiE 'image|JPEG|PNG|WebP|GIF|bitmap'; then " +
            // Fix extension mismatch (e.g., PNG saved as .jpg from fallback chain)
            "  FTYPE=$(file -b '" + root.shellEscape(root.filePath) + "'); " +
            "  FPATH='" + root.shellEscape(root.filePath) + "'; " +
            "  FBASE=\"${FPATH%.*}\"; " +
            "  case \"$FTYPE\" in " +
            "    PNG*) NEWEXT='.png' ;; " +
            "    JPEG*) NEWEXT='.jpg' ;; " +
            "    GIF*) NEWEXT='.gif' ;; " +
            "    WebP*) NEWEXT='.webp' ;; " +
            "    *) NEWEXT='' ;; " +
            "  esac; " +
            "  if [ -n \"$NEWEXT\" ] && [ \"${FPATH##*.}\" != \"${NEWEXT#.}\" ]; then " +
            "    mv \"$FPATH\" \"$FBASE$NEWEXT\" 2>/dev/null && FPATH=\"$FBASE$NEWEXT\"; " +
            "  fi; " +
            "  echo \"$FPATH\"; " +
            "  file \"$FPATH\" | grep -oP '\\d+\\s*x\\s*\\d+' | tail -1; " +
            "fi"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                var output = text.trim()
                // Empty output = download failed or got HTML (Cloudflare block)
                if (output.length === 0) {
                    root.done("", 0, 0)
                    return
                }
                // Parse output: line 1 = actual file path (may differ from filePath if renamed)
                //               line 2 = dimensions (WxH)
                var lines = output.split("\n")
                var actualPath = lines[0] ? lines[0].trim() : root.filePath
                var w = 300
                var h = 300
                if (lines.length >= 2) {
                    var dims = lines[1].split(/\s*x\s*/)
                    if (dims.length >= 2) {
                        w = parseInt(dims[0]) || 300
                        h = parseInt(dims[1]) || 300
                    }
                }
                root.imageWidth = w
                root.imageHeight = h
                root.done(actualPath, w, h)
            }
        }
    }
}
