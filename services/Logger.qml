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
    property int logLevel: Logger.Level.INFO
    property bool writeToFile: true
    property bool showTimestamp: true
    property string logFilePath: `${Directories.cacheDir}/booru/debug.log`

    // Rotating log buffer (keep last 1000 entries in memory for debug UI)
    property var logBuffer: []
    readonly property int maxBufferSize: 1000

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
        // Trigger reactive update
        logBuffer = logBuffer.slice()

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

    // Append line to log file
    function appendToFile(line) {
        // Escape single quotes for shell
        const escaped = line.replace(/'/g, "'\\''")
        const proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { running: true }', root)
        proc.command = ["bash", "-c",
            `mkdir -p "$(dirname '${logFilePath}')" && echo '${escaped}' >> '${logFilePath}'`]
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

    // Clear log file
    function clearFile() {
        const proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { running: true }', root)
        proc.command = ["bash", "-c", `> '${logFilePath}'`]
        info("Logger", "Log file cleared")
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

    // Initialize - ensure log directory exists
    Component.onCompleted: {
        const initProc = Qt.createQmlObject(
            'import Quickshell.Io; Process { running: true }', root)
        initProc.command = ["bash", "-c", `mkdir -p "$(dirname '${logFilePath}')"`]

        info("Logger", `Logger initialized (level: ${levelName(logLevel)}, file: ${writeToFile})`)
    }
}
