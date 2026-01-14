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

    // ═══════════════════════════════════════════════════════════════════════
    // FILE NAMING PREFIXES - Single Source of Truth
    // ═══════════════════════════════════════════════════════════════════════
    // These prefixes categorize cached files by type. Use these constants
    // instead of hardcoding strings in other components.
    // Access via: CacheIndex.hiresPrefix, CacheIndex.gifPrefix, etc.
    // ═══════════════════════════════════════════════════════════════════════
    readonly property string hiresPrefix: "hires_"
    readonly property string gifPrefix: "gif_"
    readonly property string videoPrefix: "video_"
    readonly property string ugoiraPrefix: "ugoira_"
    readonly property var prefixes: [hiresPrefix, gifPrefix, videoPrefix, ugoiraPrefix]

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
        if (filename.indexOf(hiresPrefix) === 0) return "hires"
        if (filename.indexOf(gifPrefix) === 0) return "gif"
        if (filename.indexOf(videoPrefix) === 0) return "video"
        if (filename.indexOf(ugoiraPrefix) === 0) return "ugoira"
        return "preview"
    }

    // Memoization cache for lookup results with LRU eviction
    // IMPORTANT: These are plain JS variables, NOT QML properties!
    // Using QML properties would create binding dependencies that cause loops.
    // Key: baseName, Value: { generation: int, result: string }
    readonly property int cacheMaxSize: 500  // Limit cache entries

    // Private JS state (not reactive - avoids binding loops)
    property var _private: ({
        lookupCache: {},
        cacheAccessOrder: []
    })

    /**
     * Instant lookup - returns file:// path or empty string.
     * Single hash lookup + priority selection. O(1) complexity.
     * Memoized with LRU eviction to bound memory usage.
     *
     * IMPORTANT: This function is pure during binding evaluation.
     * Memoization uses a private JS object to avoid binding loops.
     */
    function lookup(filename) {
        if (!filename || !root.initialized) return ""

        var base = extractBaseName(filename)
        if (!base) return ""

        // Check memoization cache - if generation matches, return cached result
        // Access through _private to avoid creating binding dependencies
        var cached = root._private.lookupCache[base]
        if (cached && cached.generation === root.generation) {
            // Update LRU access order synchronously (no binding dependency)
            var idx = root._private.cacheAccessOrder.indexOf(base)
            if (idx >= 0) {
                root._private.cacheAccessOrder.splice(idx, 1)
                root._private.cacheAccessOrder.push(base)
            }
            return cached.result
        }

        var entry = root.index[base]
        var result = ""
        var slot = "none"

        if (entry) {
            // Priority: hires > ugoira > gif > video > preview
            var path = entry.hires || entry.ugoira || entry.gif || entry.video || entry.preview
            result = path ? "file://" + path : ""
            slot = entry.hires ? "hires" : (entry.ugoira ? "ugoira" : (entry.gif ? "gif" : (entry.video ? "video" : (entry.preview ? "preview" : "none"))))
        }

        // Update memoization cache synchronously (no binding dependency)
        // LRU eviction: remove oldest entries if at capacity
        while (root._private.cacheAccessOrder.length >= root.cacheMaxSize) {
            var oldest = root._private.cacheAccessOrder.shift()
            delete root._private.lookupCache[oldest]
        }
        root._private.lookupCache[base] = { generation: root.generation, result: result }
        root._private.cacheAccessOrder.push(base)

        // NOTE: No logging inside lookup() to keep it pure for bindings.
        // Logging creates side effects that can cause binding loops.

        return result
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
     * Batch register multiple files at once.
     * More efficient than calling register() in a loop (single clone).
     * @param entries - Array of {filename, fullPath} objects
     */
    function batchRegister(entries) {
        if (!entries || entries.length === 0) return

        // Mutex: queue if currently mutating
        if (root.mutating) {
            Qt.callLater(() => batchRegister(entries))
            return
        }
        root.mutating = true

        // Single deep clone for all entries
        var newIndex = JSON.parse(JSON.stringify(root.index))
        var newFiles = []

        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i]
            if (!entry.filename || !entry.fullPath) continue

            var base = extractBaseName(entry.filename)
            if (!base) continue

            var slot = getSlot(entry.filename)

            if (!newIndex[base]) {
                newIndex[base] = {}
            }
            var isNew = !newIndex[base][slot]
            newIndex[base][slot] = entry.fullPath

            if (isNew) {
                newFiles.push({ filename: entry.filename, fullPath: entry.fullPath })
            }
        }

        root.index = newIndex
        root.generation++
        root.mutating = false

        // Emit signals for new files
        for (var j = 0; j < newFiles.length; j++) {
            root.fileRegistered(newFiles[j].filename, newFiles[j].fullPath)
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
        root._private.lookupCache = {}  // Clear memoization cache
        root._private.cacheAccessOrder = []  // Clear LRU tracking
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
    // Also cleans up stale .tmp files (incomplete downloads older than 5 minutes)
    Process {
        id: initialScanner
        running: false
        command: ["bash", "-c",
            // Step 1: Clean up stale .tmp files (interrupted downloads older than 5 min)
            "CLEANED=$(find '" + root.previewDir + "' -maxdepth 1 -name '*.tmp' -mmin +5 -print -delete 2>/dev/null | wc -l); " +
            "[ \"$CLEANED\" -gt 0 ] && echo \"CLEANUP:$CLEANED\" >&2; " +
            // Step 2: Scan all cache directories
            "for dir in '" + root.previewDir + "' '" + root.downloadDir + "' '" +
            root.nsfwDir + "' '" + root.wallpaperDir + "'; do " +
            "  [ -d \"$dir\" ] && find \"$dir\" -maxdepth 1 -type f -printf '%f\\t%p\\n' 2>/dev/null; " +
            "done"
        ]

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.indexOf("CLEANUP:") >= 0) {
                    var count = text.split("CLEANUP:")[1].trim()
                    Logger.info("CacheIndex", `Cleaned up ${count} stale .tmp file(s) from incomplete downloads`)
                }
            }
        }

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
    // Uses exponential backoff when no new files found (30s → 60s → 120s, max 5min)
    property int refreshBackoff: 1  // Multiplier for backoff
    readonly property int refreshBaseInterval: 30000  // 30 seconds base
    readonly property int refreshMaxInterval: 300000  // 5 minutes max

    Timer {
        id: refreshTimer
        interval: Math.min(root.refreshBaseInterval * root.refreshBackoff, root.refreshMaxInterval)
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

                // Exponential backoff: double interval when idle, reset when active
                if (added > 0) {
                    root.refreshBackoff = 1  // Reset backoff on activity
                    Logger.debug("CacheIndex", `Quick refresh added ${added} files, backoff reset`)
                } else {
                    root.refreshBackoff = Math.min(root.refreshBackoff * 2, 10)  // Max 10x = 5min
                }
            }
        }
    }

    Component.onCompleted: {
        initialize()
    }
}
