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

    command: ["bash", "-c", `
        mkdir -p "$(dirname '${root.filePath}')"
        # Download if missing OR if existing file is corrupted (HTML instead of image)
        if [ ! -f '${root.filePath}' ] || file '${root.filePath}' | grep -q 'HTML'; then
            rm -f '${root.filePath}'
            curl -sL -A 'Mozilla/5.0 BooruSidebar/1.0' '${root.sourceUrl}' -o '${root.filePath}' 2>/dev/null
        fi
        # Only output dimensions if it's a valid image
        if [ -f '${root.filePath}' ] && ! file '${root.filePath}' | grep -q 'HTML'; then
            file '${root.filePath}' | grep -oP '\\d+\\s*x\\s*\\d+' | head -1
        fi
    `]

    stdout: StdioCollector {
        onStreamFinished: {
            const output = text.trim()
            // Empty output = download failed or got HTML (Cloudflare block)
            if (output.length === 0) {
                root.done("", 0, 0)
                return
            }
            let w = 300, h = 300
            const dims = output.split(/\s*x\s*/)
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
