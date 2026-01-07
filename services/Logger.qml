pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/common"

/**
 * Centralized logging service with levels, file persistence, and debug UI support.
 *
 * Usage:
 *   Logger.debug("Category", "Debug message")
 *   Logger.info("Category", `Processed ${count} items`)
 *   Logger.warn("Category", "Something looks wrong")
 *   Logger.error("Category", "Operation failed")
 */
Singleton {
    id: root

    // Log levels
    enum Level { DEBUG, INFO, WARN, ERROR }

    // Configuration
    property int logLevel: Logger.Level.DEBUG
    property bool writeToFile: true
    property bool showTimestamp: true
    property string logFilePath: `${Directories.cacheDir}/booru/debug.log`

    // Rotating log buffer (keep last 1000 entries in memory for debug UI)
    property var logBuffer: []
    readonly property int maxBufferSize: 1000
    property int logGeneration: 0  // Increment on changes for efficient reactivity

    // Signals for debug UI
    signal logAdded(var entry)

    // Performance metrics
    property var requestTimings: ({})  // { requestId: startTime }
    property var metrics: ({
        totalRequests: 0,
        failedRequests: 0,
        avgResponseTime: 0,
        cacheHits: 0,
        cacheMisses: 0
    })

    // Convenience logging functions
    function debug(category, message) { log(Logger.Level.DEBUG, category, message) }
    function info(category, message)  { log(Logger.Level.INFO, category, message) }
    function warn(category, message)  { log(Logger.Level.WARN, category, message) }
    function error(category, message) { log(Logger.Level.ERROR, category, message) }

    // Main logging function
    function log(level, category, message) {
        if (level < logLevel) return

        const entry = {
            timestamp: new Date().toISOString(),
            level: levelName(level),
            levelNum: level,
            category: category,
            message: String(message)
        }

        // Add to memory buffer (for debug UI)
        logBuffer.push(entry)
        if (logBuffer.length > maxBufferSize) {
            logBuffer.shift()
        }
        // Trigger reactive update via generation counter (avoids O(n) array copy)
        logGeneration++

        // Console output (maintains existing behavior)
        const formatted = formatEntry(entry)
        if (level === Logger.Level.ERROR) {
            console.error(formatted)
        } else {
            console.log(formatted)
        }

        // File output
        if (writeToFile) {
            appendToFile(formatted)
        }

        logAdded(entry)
    }

    // Format log entry for console/file output
    function formatEntry(entry) {
        const ts = showTimestamp ? `${entry.timestamp} ` : ""
        return `${ts}[${entry.level}][${entry.category}] ${entry.message}`
    }

    // Get level name from enum value
    function levelName(level) {
        switch(level) {
            case Logger.Level.DEBUG: return "DEBUG"
            case Logger.Level.INFO:  return "INFO"
            case Logger.Level.WARN:  return "WARN"
            case Logger.Level.ERROR: return "ERROR"
            default: return "UNKNOWN"
        }
    }

    // Persistent log writer - single Process for all writes
    // Uses 'tee -a' to append to file with stdin
    Process {
        id: logWriter
        running: root.writeToFile && root.logWriterReady
        stdinEnabled: true
        command: ["tee", "-a", root.logFilePath]

        onExited: (code, status) => {
            // Track failures
            if (code !== 0) {
                root.writeFailures++
                console.error(`Logger: Log writer exited with code ${code} (failure ${root.writeFailures}/${root.maxWriteFailures})`)

                // Disable file logging after too many failures
                if (root.writeFailures >= root.maxWriteFailures) {
                    root.writeDisabledByError = true
                    console.error("Logger: File logging disabled due to repeated failures")
                    writeRecoveryTimer.start()
                    return
                }
            } else {
                root.writeFailures = 0  // Reset on successful exit
            }

            // Restart if unexpectedly stopped
            if (root.writeToFile && root.logWriterReady && !root.writeDisabledByError) {
                Qt.callLater(() => { logWriter.running = true })
            }
        }
    }

    // Track if log directory is ready
    property bool logWriterReady: false

    // Buffer for writes before writer is ready
    property var pendingWrites: []

    // Error tracking for write failures
    property int writeFailures: 0
    readonly property int maxWriteFailures: 5  // Disable after this many consecutive failures
    property bool writeDisabledByError: false

    // Recovery timer - try to re-enable file logging after 5 minutes
    Timer {
        id: writeRecoveryTimer
        interval: 300000  // 5 minutes
        repeat: false
        onTriggered: {
            console.log("Logger: Attempting to recover file logging...")
            root.writeFailures = 0
            root.writeDisabledByError = false
            if (root.writeToFile && root.logWriterReady) {
                logWriter.running = true
            }
        }
    }

    // Append line to log file
    function appendToFile(line) {
        // Skip if writing disabled due to errors
        if (writeDisabledByError) return

        if (logWriter.running) {
            logWriter.write(line + "\n")
        } else {
            // Buffer writes until writer is ready (limit buffer size)
            if (pendingWrites.length < 100) {
                pendingWrites.push(line)
            }
        }
    }

    // Flush pending writes when writer becomes ready
    function flushPendingWrites() {
        if (!logWriter.running || pendingWrites.length === 0) return
        for (const line of pendingWrites) {
            logWriter.write(line + "\n")
        }
        pendingWrites = []
    }

    // Performance tracking: Start timing a request
    function startTiming(requestId) {
        requestTimings[requestId] = Date.now()
        metrics.totalRequests++
    }

    // Performance tracking: End timing and log
    function endTiming(requestId, success = true, category = "Request") {
        const startTime = requestTimings[requestId]
        if (!startTime) return 0

        const duration = Date.now() - startTime
        delete requestTimings[requestId]

        if (!success) metrics.failedRequests++

        // Update average response time
        const count = metrics.totalRequests - metrics.failedRequests
        if (count > 0) {
            metrics.avgResponseTime = Math.round(
                (metrics.avgResponseTime * (count - 1) + duration) / count
            )
        }

        info(category, `Completed in ${duration}ms`)
        return duration
    }

    // Track cache hit/miss
    function cacheHit() { metrics.cacheHits++ }
    function cacheMiss() { metrics.cacheMisses++ }

    // Dump current application state for debugging
    function dumpState() {
        return {
            timestamp: new Date().toISOString(),
            booru: {
                provider: typeof Booru !== "undefined" ? Booru.currentProvider : "N/A",
                nsfw: typeof Booru !== "undefined" ? Booru.allowNsfw : false,
                sorting: typeof Booru !== "undefined" ? Booru.currentSorting : "",
                ageFilter: typeof Booru !== "undefined" ? Booru.ageFilter : "",
                responses: typeof Booru !== "undefined" ? Booru.responses.length : 0,
                runningRequests: typeof Booru !== "undefined" ? Booru.runningRequests : 0
            },
            cache: {
                files: typeof CacheIndex !== "undefined" ? Object.keys(CacheIndex.index).length : 0,
                initialized: typeof CacheIndex !== "undefined" ? CacheIndex.initialized : false
            },
            videoPool: {
                slots: typeof VideoPlayerPool !== "undefined" ? VideoPlayerPool.activeSlots.length : 0,
                maxSlots: typeof VideoPlayerPool !== "undefined" ? VideoPlayerPool.maxSlots : 0
            },
            metrics: metrics,
            logBuffer: {
                size: logBuffer.length,
                oldest: logBuffer.length > 0 ? logBuffer[0].timestamp : null,
                newest: logBuffer.length > 0 ? logBuffer[logBuffer.length - 1].timestamp : null
            }
        }
    }

    // Clear log buffer
    function clearBuffer() {
        logBuffer = []
        info("Logger", "Log buffer cleared")
    }

    // Clear log file - stop writer, truncate, restart
    Process {
        id: fileClearer
        running: false
        command: ["bash", "-c", `> '${root.logFilePath}'`]
        onExited: {
            root.info("Logger", "Log file cleared")
            // Restart writer after clearing
            if (root.writeToFile && root.logWriterReady) {
                logWriter.running = true
            }
        }
    }

    function clearFile() {
        // Stop writer before truncating to avoid race
        logWriter.running = false
        fileClearer.running = true
    }

    // Filter logs by level (for debug UI)
    function getLogsByLevel(minLevel) {
        return logBuffer.filter(entry => entry.levelNum >= minLevel)
    }

    // Filter logs by category (for debug UI)
    function getLogsByCategory(category) {
        return logBuffer.filter(entry => entry.category === category)
    }

    // Get unique categories from buffer (for debug UI filtering)
    function getCategories() {
        const cats = {}
        logBuffer.forEach(entry => { cats[entry.category] = true })
        return Object.keys(cats).sort()
    }

    // Initialize log directory
    Process {
        id: dirInitializer
        running: true
        command: ["bash", "-c", `mkdir -p "$(dirname '${root.logFilePath}')"`]
        onExited: (code, status) => {
            if (code === 0) {
                root.logWriterReady = true
                // Flush any logs buffered during startup
                Qt.callLater(root.flushPendingWrites)
            } else {
                console.error("Logger: Failed to create log directory")
            }
        }
    }

    // Initialize
    Component.onCompleted: {
        info("Logger", `Logger initialized (level: ${levelName(logLevel)}, file: ${writeToFile})`)
    }
}
