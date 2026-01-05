pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/common"
import "../modules/common/functions/file_utils.js" as FileUtils

/**
 * In-memory cache index for instant filename lookups.
 * Eliminates per-image bash process spawns by scanning directories once
 * and providing O(1) lookups.
 */
Singleton {
    id: root

    // Internal index: { filename: fullPath }
    property var index: ({})
    property bool initialized: false
    property bool scanning: false

    // Cache directories to scan (without file:// prefix)
    readonly property string previewDir: Directories.cacheDir + "/booru/previews"
    readonly property string downloadDir: FileUtils.trimFileProtocol(Directories.homeDir) + "/Pictures/booru"
    readonly property string nsfwDir: root.downloadDir + "/nsfw"
    readonly property string wallpaperDir: FileUtils.trimFileProtocol(Directories.homeDir) + "/Pictures/wallpapers"

    // Signal emitted when batch check completes
    signal batchCheckComplete(var results)

    // Signal emitted when a file is registered (for reactive cache updates)
    signal fileRegistered(string filename, string filepath)

    // Common image extensions to check when original extension not found
    readonly property var imageExtensions: [".jpg", ".png", ".gif", ".jpeg", ".webp"]

    /**
     * Instant lookup - returns file:// path or empty string.
     * Checks multiple filename variants (hires_, gif_, video_ prefixes)
     * and extension variants for zerochan fallback downloads.
     */
    function lookup(filename) {
        if (!filename || !root.initialized) return ""

        // If filename already has a prefix, check it directly first
        if (filename.indexOf("video_") === 0 || filename.indexOf("gif_") === 0 || filename.indexOf("hires_") === 0) {
            if (root.index[filename]) return "file://" + root.index[filename]
        }

        // Check hires_ prefix FIRST - prioritize high-resolution images
        var hiresName = "hires_" + filename
        if (root.index[hiresName]) return "file://" + root.index[hiresName]

        // Fall back to exact filename (preview/sample)
        if (root.index[filename]) return "file://" + root.index[filename]

        // Check gif_ prefix variant
        var gifName = "gif_" + filename
        if (root.index[gifName]) return "file://" + root.index[gifName]

        // Check video_ prefix variant
        var videoName = "video_" + filename
        if (root.index[videoName]) return "file://" + root.index[videoName]

        // Check extension variants (for zerochan fallback downloads where extension may differ)
        var dotIdx = filename.lastIndexOf(".")
        if (dotIdx > 0) {
            var baseName = filename.substring(0, dotIdx)
            // First pass: check hires_ variants (prioritize high-res)
            for (var i = 0; i < imageExtensions.length; i++) {
                var ext = imageExtensions[i]
                var hiresAlt = "hires_" + baseName + ext
                if (root.index[hiresAlt]) {
                    return "file://" + root.index[hiresAlt]
                }
            }
            // Second pass: check exact matches (preview/sample)
            for (var j = 0; j < imageExtensions.length; j++) {
                var altName = baseName + imageExtensions[j]
                if (root.index[altName]) {
                    return "file://" + root.index[altName]
                }
            }
        }

        return ""
    }

    /**
     * Register a newly downloaded file in the index.
     * Called when downloads complete.
     */
    function register(filename, fullPath) {
        if (!filename || !fullPath) return
        var isNew = !root.index[filename]
        var newIndex = {}
        for (var key in root.index) {
            newIndex[key] = root.index[key]
        }
        newIndex[filename] = fullPath
        root.index = newIndex
        // Notify components of new cache entry
        if (isNew) {
            root.fileRegistered(filename, fullPath)
        }
    }

    /**
     * Remove a file from the cache index.
     * Called when cache files are deleted.
     */
    function unregister(filename) {
        if (!filename || !root.index[filename]) return
        var newIndex = {}
        for (var key in root.index) {
            if (key !== filename) {
                newIndex[key] = root.index[key]
            }
        }
        root.index = newIndex
    }

    /**
     * Batch unregister - removes multiple files from cache index.
     */
    function batchUnregister(filenames) {
        if (!filenames || filenames.length === 0) return
        var toRemove = {}
        for (var i = 0; i < filenames.length; i++) {
            // Extract just the filename from full path
            var path = filenames[i]
            var name = path.substring(path.lastIndexOf('/') + 1)
            toRemove[name] = true
        }
        var newIndex = {}
        for (var key in root.index) {
            if (!toRemove[key]) {
                newIndex[key] = root.index[key]
            }
        }
        root.index = newIndex
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
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split('\t')
                    if (parts.length >= 2 && parts[0].length > 0) {
                        // First occurrence wins (priority order: preview, download, nsfw, wallpaper)
                        if (!newIndex[parts[0]]) {
                            newIndex[parts[0]] = parts[1]
                        }
                    }
                }
                root.index = newIndex
                root.initialized = true
                root.scanning = false
                console.log("[CacheIndex] Initialized with " + Object.keys(newIndex).length + " files")
            }
        }

        onExited: function(code, status) {
            if (code !== 0 && !root.initialized) {
                // Scan failed, mark as initialized anyway to not block
                root.initialized = true
                root.scanning = false
                console.log("[CacheIndex] Scan failed, using empty index")
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
                var newIndex = {}
                for (var key in root.index) {
                    newIndex[key] = root.index[key]
                }
                var added = 0
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split('\t')
                    if (parts.length >= 2 && parts[0].length > 0) {
                        if (!newIndex[parts[0]]) {
                            newIndex[parts[0]] = parts[1]
                            added++
                        }
                    }
                }
                if (added > 0) {
                    root.index = newIndex
                    console.log("[CacheIndex] Quick refresh added " + added + " files")
                }
            }
        }
    }

    Component.onCompleted: {
        initialize()
    }
}
