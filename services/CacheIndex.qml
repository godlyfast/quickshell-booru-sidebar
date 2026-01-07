pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/common"
import "../modules/common/functions/file_utils.js" as FileUtils

/**
 * In-memory cache index for instant filename lookups.
 *
 * Index structure: { baseName: { hires, gif, video, ugoira, preview } }
 * - baseName is the md5/id without prefix or extension
 * - Each slot holds the full path to that variant (or undefined)
 *
 * Priority order: hires > ugoira > gif > video > preview
 */
Singleton {
    id: root

    // Internal index: { baseName: { hires?, gif?, video?, ugoira?, preview? } }
    property var index: ({})
    property bool initialized: false
    property bool scanning: false

    // Generation counter - incremented on any mutation for reactive bindings
    property int generation: 0

    // Mutex-like flag to prevent concurrent mutations
    property bool mutating: false

    // Cache directories to scan (without file:// prefix)
    readonly property string previewDir: Directories.cacheDir + "/booru/previews"
    readonly property string downloadDir: FileUtils.trimFileProtocol(Directories.homeDir) + "/Pictures/booru"
    readonly property string nsfwDir: root.downloadDir + "/nsfw"
    readonly property string wallpaperDir: FileUtils.trimFileProtocol(Directories.homeDir) + "/Pictures/wallpapers"

    // Signal emitted when batch check completes
    signal batchCheckComplete(var results)

    // Signal emitted when a file is registered (for reactive cache updates)
    signal fileRegistered(string filename, string filepath)

    // Signal emitted when cache is cleared (for components to reset state)
    signal cacheCleared()

    // Prefix patterns for categorizing files
    readonly property var prefixes: ["hires_", "gif_", "video_", "ugoira_"]

    /**
     * Extract baseName from filename (strip prefix and extension).
     * "hires_abc123.jpg" → "abc123"
     * "abc123.png" → "abc123"
     */
    function extractBaseName(filename) {
        if (!filename) return ""
        var name = filename
        // Strip prefix if present
        for (var i = 0; i < prefixes.length; i++) {
            if (name.indexOf(prefixes[i]) === 0) {
                name = name.substring(prefixes[i].length)
                break
            }
        }
        // Strip extension
        var dotIdx = name.lastIndexOf(".")
        return dotIdx > 0 ? name.substring(0, dotIdx) : name
    }

    /**
     * Determine which slot a filename belongs to based on prefix.
     * "hires_abc.jpg" → "hires"
     * "abc.jpg" → "preview"
     */
    function getSlot(filename) {
        if (filename.indexOf("hires_") === 0) return "hires"
        if (filename.indexOf("gif_") === 0) return "gif"
        if (filename.indexOf("video_") === 0) return "video"
        if (filename.indexOf("ugoira_") === 0) return "ugoira"
        return "preview"
    }

    /**
     * Instant lookup - returns file:// path or empty string.
     * Single hash lookup + priority selection. O(1) complexity.
     */
    function lookup(filename) {
        if (!filename || !root.initialized) return ""

        var base = extractBaseName(filename)
        if (!base) return ""

        var entry = root.index[base]
        if (!entry) return ""

        // Priority: hires > ugoira > gif > video > preview
        var path = entry.hires || entry.ugoira || entry.gif || entry.video || entry.preview

        // Debug: Log which slot was selected
        var slot = entry.hires ? "hires" : (entry.ugoira ? "ugoira" : (entry.gif ? "gif" : (entry.video ? "video" : (entry.preview ? "preview" : "none"))))
        Logger.debug("CacheIndex", `lookup(${base.substring(0, 12)}...) slot=${slot} hasHires=${!!entry.hires}`)

        return path ? "file://" + path : ""
    }

    /**
     * Register a newly downloaded file in the index.
     * Called when downloads complete.
     */
    function register(filename, fullPath) {
        if (!filename || !fullPath) return

        // Mutex: queue concurrent registrations for next tick
        if (root.mutating) {
            Qt.callLater(() => register(filename, fullPath))
            return
        }
        root.mutating = true

        var base = extractBaseName(filename)
        if (!base) {
            root.mutating = false
            return
        }

        var slot = getSlot(filename)

        // Deep clone index for reactivity
        var newIndex = JSON.parse(JSON.stringify(root.index))

        // Create or update entry
        if (!newIndex[base]) {
            newIndex[base] = {}
        }
        var isNew = !newIndex[base][slot]
        newIndex[base][slot] = fullPath
        root.index = newIndex
        root.generation++
        root.mutating = false

        if (isNew) {
            root.fileRegistered(filename, fullPath)
        }
    }

    /**
     * Remove a file from the cache index.
     * Called when cache files are deleted.
     */
    function unregister(filename) {
        if (!filename) return

        // Mutex: queue concurrent unregistrations for next tick
        if (root.mutating) {
            Qt.callLater(() => unregister(filename))
            return
        }

        var base = extractBaseName(filename)
        var slot = getSlot(filename)
        if (!root.index[base] || !root.index[base][slot]) return

        root.mutating = true

        // Deep clone index
        var newIndex = JSON.parse(JSON.stringify(root.index))

        // Remove slot
        delete newIndex[base][slot]

        // Remove entry if empty
        if (Object.keys(newIndex[base]).length === 0) {
            delete newIndex[base]
        }
        root.index = newIndex
        root.generation++
        root.mutating = false
    }

    /**
     * Batch unregister - removes multiple files from cache index.
     * Emits cacheCleared signal when complete so components can reset state.
     */
    function batchUnregister(filenames) {
        if (!filenames || filenames.length === 0) return

        // Mutex: queue if already mutating
        if (root.mutating) {
            Qt.callLater(() => batchUnregister(filenames))
            return
        }
        root.mutating = true

        // Deep clone ONCE at start
        var newIndex = JSON.parse(JSON.stringify(root.index))

        // Mutate in-place
        for (var i = 0; i < filenames.length; i++) {
            var path = filenames[i]
            var name = path.substring(path.lastIndexOf('/') + 1)
            var base = extractBaseName(name)
            var slot = getSlot(name)
            if (newIndex[base] && newIndex[base][slot]) {
                delete newIndex[base][slot]
                if (Object.keys(newIndex[base]).length === 0) {
                    delete newIndex[base]
                }
            }
        }

        // Assign ONCE at end
        root.index = newIndex
        root.generation++
        root.mutating = false

        // Notify components to reset their cache state
        Logger.info("CacheIndex", `Cache cleared: ${filenames.length} files unregistered, generation=${root.generation}`)
        root.cacheCleared()
    }

    /**
     * Batch check for array of filenames.
     * Single bash process checks all files, much faster than per-image checks.
     */
    function batchCheck(filenames) {
        if (!filenames || filenames.length === 0) return
        batchChecker.filenames = filenames
        batchChecker.running = true
    }

    /**
     * Initialize the cache index by scanning all cache directories.
     */
    function initialize() {
        if (root.initialized || root.scanning) return
        root.scanning = true
        initialScanner.running = true
    }

    // Process for initial directory scan
    Process {
        id: initialScanner
        running: false
        command: ["bash", "-c",
            "for dir in '" + root.previewDir + "' '" + root.downloadDir + "' '" +
            root.nsfwDir + "' '" + root.wallpaperDir + "'; do " +
            "  [ -d \"$dir\" ] && find \"$dir\" -maxdepth 1 -type f -printf '%f\\t%p\\n' 2>/dev/null; " +
            "done"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.split('\n')
                var newIndex = {}
                var fileCount = 0
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split('\t')
                    if (parts.length >= 2 && parts[0].length > 0) {
                        var filename = parts[0]
                        var fullPath = parts[1]
                        var base = root.extractBaseName(filename)
                        var slot = root.getSlot(filename)

                        if (!base) continue

                        if (!newIndex[base]) {
                            newIndex[base] = {}
                        }
                        // First occurrence wins per slot (priority: preview > download > nsfw > wallpaper)
                        if (!newIndex[base][slot]) {
                            newIndex[base][slot] = fullPath
                            fileCount++
                        }
                    }
                }
                root.index = newIndex
                root.initialized = true
                root.scanning = false
                Logger.info("CacheIndex", `Initialized with ${fileCount} files in ${Object.keys(newIndex).length} entries`)
            }
        }

        onExited: function(code, status) {
            if (code !== 0 && !root.initialized) {
                // Scan failed, mark as initialized anyway to not block
                root.initialized = true
                root.scanning = false
                Logger.warn("CacheIndex", "Scan failed, using empty index")
            }
        }
    }

    // Process for batch checking (used when API response arrives)
    Process {
        id: batchChecker
        property var filenames: []
        running: false

        command: {
            if (!batchChecker.filenames || batchChecker.filenames.length === 0) return ["true"]

            // Build a single bash command that checks all files
            var checks = []
            for (var i = 0; i < batchChecker.filenames.length; i++) {
                var f = batchChecker.filenames[i]
                if (!f) continue
                // Escape single quotes in filenames
                var escaped = f.replace(/'/g, "'\\''")
                // Check all cache locations for this file (with and without hires_ prefix)
                checks.push(
                    "for p in '" + root.previewDir + "/hires_" + escaped + "' " +
                    "'" + root.previewDir + "/" + escaped + "' " +
                    "'" + root.downloadDir + "/" + escaped + "' " +
                    "'" + root.nsfwDir + "/" + escaped + "' " +
                    "'" + root.wallpaperDir + "/" + escaped + "'; do " +
                    "[ -f \"$p\" ] && echo '" + escaped + "\\t'\"$p\" && break; done"
                )
            }
            return ["bash", "-c", checks.join("; ")]
        }

        stdout: StdioCollector {
            onStreamFinished: {
                var results = {}
                var lines = text.split('\n')
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split('\t')
                    if (parts.length >= 2 && parts[0].length > 0) {
                        results[parts[0]] = parts[1]
                        // Also update main index
                        root.register(parts[0], parts[1])
                    }
                }
                root.batchCheckComplete(results)
            }
        }
    }

    // Periodic refresh to catch external downloads (browser, other apps)
    Timer {
        id: refreshTimer
        interval: 30000  // 30 seconds
        running: root.initialized
        repeat: true
        onTriggered: {
            quickRefresh.running = true
        }
    }

    // Quick refresh - only scan for files modified in last minute
    Process {
        id: quickRefresh
        running: false
        command: ["bash", "-c",
            "find '" + root.previewDir + "' '" + root.downloadDir + "' '" +
            root.nsfwDir + "' '" + root.wallpaperDir +
            "' -maxdepth 1 -type f -mmin -1 -printf '%f\\t%p\\n' 2>/dev/null"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.split('\n')
                var added = 0

                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split('\t')
                    if (parts.length >= 2 && parts[0].length > 0) {
                        var filename = parts[0]
                        var fullPath = parts[1]
                        var base = root.extractBaseName(filename)
                        var slot = root.getSlot(filename)

                        if (!base) continue

                        // Check if this slot is new
                        if (!root.index[base] || !root.index[base][slot]) {
                            root.register(filename, fullPath)
                            added++
                        }
                    }
                }
                if (added > 0) {
                    Logger.debug("CacheIndex", `Quick refresh added ${added} files`)
                }
            }
        }
    }

    Component.onCompleted: {
        initialize()
    }
}
