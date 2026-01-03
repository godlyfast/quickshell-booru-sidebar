import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Downloads an image via curl and emits done signal with path and dimensions.
 * Adapted from end-4/dots-hyprland
 */
Process {
    id: root
    property bool enabled: false
    property string filePath
    property string sourceUrl
    property int imageWidth: 0
    property int imageHeight: 0

    signal done(string path, int imgWidth, int imgHeight)

    running: enabled && sourceUrl.length > 0

    // Shell escape helper for safe embedding in shell commands
    function shellEscape(str) {
        if (!str) return ""
        return str.replace(/'/g, "'\\''")
    }

    command: ["bash", "-c",
        "mkdir -p \"$(dirname '" + shellEscape(root.filePath) + "')\" && " +
        // Re-download if: file missing, empty, or HTML error page
        "if [ ! -s '" + shellEscape(root.filePath) + "' ] || file '" + shellEscape(root.filePath) + "' | grep -q 'HTML'; then " +
        "  rm -f '" + shellEscape(root.filePath) + "'; " +
        "  curl -fsSL -A 'Mozilla/5.0 BooruSidebar/1.0' '" + shellEscape(root.sourceUrl) + "' -o '" + shellEscape(root.filePath) + "'; " +
        "fi && " +
        "if [ -s '" + shellEscape(root.filePath) + "' ] && file -b '" + shellEscape(root.filePath) + "' | grep -qiE 'image|JPEG|PNG|WebP|GIF|bitmap'; then " +
        "  file '" + shellEscape(root.filePath) + "' | grep -oP '\\d+\\s*x\\s*\\d+' | head -1; " +
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
            var w = 300
            var h = 300
            var dims = output.split(/\s*x\s*/)
            if (dims.length >= 2) {
                w = parseInt(dims[0]) || 300
                h = parseInt(dims[1]) || 300
            }
            root.imageWidth = w
            root.imageHeight = h
            root.done(root.filePath, w, h)
        }
    }
}
