pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell
import "../modules/common"

/**
 * Manages a pool of MediaPlayer instances with a hard limit.
 * Prevents memory leaks from unbounded MediaPlayer creation in the sidebar grid.
 *
 * Usage:
 * - BooruImage requests a player via requestPlayer(imageId)
 * - Pool returns existing or creates new (up to maxPlayers)
 * - When limit reached, LRU player is evicted and reused
 * - BooruImage releases via releasePlayer(imageId) on destruction
 */
Singleton {
    id: root

    Component.onCompleted: {
        console.log("[VideoPlayerPool] Initialized with max players:", maxPlayers)
    }

    // Configuration - linked to ConfigOptions
    property int maxPlayers: ConfigOptions.booru.maxSidebarPlayers
    property bool autoplay: ConfigOptions.booru.videoAutoplay

    // Pool state
    property var playerPool: []  // Array of pool entries
    property int activeCount: 0  // Count of currently assigned players

    // Component template for creating new player entries
    property Component playerComponent: Component {
        QtObject {
            id: entry
            property var player: MediaPlayer {
                loops: MediaPlayer.Infinite
                audioOutput: entry.audioOutput
            }
            property var audioOutput: AudioOutput {
                muted: true  // Default muted, unmuted when hovered
            }
            property var assignedTo: null      // Image ID currently using this player
            property real lastUsed: 0          // Timestamp for LRU eviction
            property var videoOutput: null     // VideoOutput to render to
        }
    }

    /**
     * Request a player for an image.
     * Returns a pool entry object with {player, audioOutput, ...} or null if unavailable.
     */
    function requestPlayer(imageId) {
        // Check if already assigned to this image
        for (var i = 0; i < playerPool.length; i++) {
            if (playerPool[i].assignedTo === imageId) {
                playerPool[i].lastUsed = Date.now()
                console.log("[VideoPlayerPool] Returning existing player for image:", imageId)
                return playerPool[i]
            }
        }

        // Find an unassigned player in the pool
        for (var j = 0; j < playerPool.length; j++) {
            if (playerPool[j].assignedTo === null) {
                playerPool[j].assignedTo = imageId
                playerPool[j].lastUsed = Date.now()
                activeCount++
                console.log("[VideoPlayerPool] Reusing idle player for image:", imageId, "Active:", activeCount)
                return playerPool[j]
            }
        }

        // Create new if under limit
        if (playerPool.length < maxPlayers) {
            var newEntry = playerComponent.createObject(root)
            if (newEntry) {
                newEntry.assignedTo = imageId
                newEntry.lastUsed = Date.now()
                playerPool.push(newEntry)
                activeCount++
                console.log("[VideoPlayerPool] Created new player for image:", imageId, "Pool size:", playerPool.length, "Active:", activeCount)
                return newEntry
            } else {
                console.error("[VideoPlayerPool] Failed to create player component")
                return null
            }
        }

        // Pool is full and all assigned - evict LRU
        return evictAndReuse(imageId)
    }

    /**
     * Release a player back to the pool.
     * The player is stopped and its source cleared, but the object is kept for reuse.
     */
    function releasePlayer(imageId) {
        for (var i = 0; i < playerPool.length; i++) {
            if (playerPool[i].assignedTo === imageId) {
                var entry = playerPool[i]
                entry.player.stop()
                entry.player.source = ""
                entry.player.videoOutput = null
                entry.audioOutput.muted = true
                entry.assignedTo = null
                entry.videoOutput = null
                activeCount = Math.max(0, activeCount - 1)
                console.log("[VideoPlayerPool] Released player from image:", imageId, "Active:", activeCount)
                return
            }
        }
    }

    /**
     * Stop all players in the pool.
     * Called when sidebar closes or page changes.
     */
    function stopAll() {
        console.log("[VideoPlayerPool] Stopping all players")
        for (var i = 0; i < playerPool.length; i++) {
            playerPool[i].player.stop()
        }
    }

    /**
     * Clear the entire pool.
     * Called on major state changes or cleanup.
     */
    function clearPool() {
        console.log("[VideoPlayerPool] Clearing entire pool of", playerPool.length, "players")
        for (var i = 0; i < playerPool.length; i++) {
            var entry = playerPool[i]
            entry.player.stop()
            entry.player.source = ""
            entry.player.videoOutput = null
            entry.destroy()
        }
        playerPool = []
        activeCount = 0
    }

    /**
     * Get current pool statistics.
     */
    function getStats() {
        return {
            poolSize: playerPool.length,
            activeCount: activeCount,
            maxPlayers: maxPlayers,
            autoplay: autoplay
        }
    }

    // Internal: evict LRU player and reuse for new image
    function evictAndReuse(imageId) {
        if (playerPool.length === 0) return null

        // Find LRU (oldest lastUsed timestamp)
        var lruIndex = 0
        var lruTime = playerPool[0].lastUsed

        for (var i = 1; i < playerPool.length; i++) {
            if (playerPool[i].lastUsed < lruTime) {
                lruTime = playerPool[i].lastUsed
                lruIndex = i
            }
        }

        var entry = playerPool[lruIndex]
        var evictedFrom = entry.assignedTo

        // Stop and clear the old player
        entry.player.stop()
        entry.player.source = ""
        entry.player.videoOutput = null
        entry.audioOutput.muted = true
        entry.videoOutput = null

        // Reassign to new image
        entry.assignedTo = imageId
        entry.lastUsed = Date.now()

        console.log("[VideoPlayerPool] Evicted LRU player from image:", evictedFrom, "for image:", imageId)
        return entry
    }

    // React to config changes - resize pool if needed
    onMaxPlayersChanged: {
        if (playerPool.length > maxPlayers) {
            console.log("[VideoPlayerPool] Shrinking pool from", playerPool.length, "to", maxPlayers)
            // Evict excess players (LRU first)
            while (playerPool.length > maxPlayers) {
                var lruIndex = 0
                var lruTime = playerPool[0].lastUsed
                for (var i = 1; i < playerPool.length; i++) {
                    if (playerPool[i].lastUsed < lruTime) {
                        lruTime = playerPool[i].lastUsed
                        lruIndex = i
                    }
                }
                var entry = playerPool[lruIndex]
                entry.player.stop()
                entry.player.source = ""
                entry.destroy()
                playerPool.splice(lruIndex, 1)
                activeCount = Math.max(0, activeCount - 1)
            }
        }
    }

    // Connect to Booru's stopAllVideos signal
    Connections {
        target: typeof Booru !== "undefined" ? Booru : null
        function onStopAllVideos() {
            root.stopAll()
        }
    }
}
