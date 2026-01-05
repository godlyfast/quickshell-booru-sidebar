pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../modules/common"

/**
 * Controls which videos have active MediaPlayers via activation slots.
 * Each BooruImage has its own local MediaPlayer, but only gets a source
 * assigned if it has an activation slot from this pool.
 *
 * This prevents memory issues by limiting how many MediaPlayers have
 * active sources at any time, while keeping VideoOutput properly bound.
 */
Singleton {
    id: root

    Component.onCompleted: {
        console.log("[VideoPlayerPool] Initialized with max slots:", maxPlayers)
    }

    // Configuration
    property int maxPlayers: ConfigOptions.booru.maxSidebarPlayers
    property bool autoplay: ConfigOptions.booru.videoAutoplay

    // Activation slots - just track image IDs and timestamps
    property var activeSlots: []  // Array of {imageId, lastUsed}

    /**
     * Request an activation slot for an image.
     * Returns an activation object or null.
     * The returned object is truthy, which triggers local MediaPlayer source binding.
     */
    function requestPlayer(imageId) {
        // Check if already has a slot
        for (var i = 0; i < activeSlots.length; i++) {
            if (activeSlots[i].imageId === imageId) {
                activeSlots[i].lastUsed = Date.now()
                return activeSlots[i]
            }
        }

        // Create new slot if under limit
        if (activeSlots.length < maxPlayers) {
            var slot = { imageId: imageId, lastUsed: Date.now() }
            activeSlots.push(slot)
            console.log("[VideoPlayerPool] Activated slot for:", imageId, "Total:", activeSlots.length)
            return slot
        }

        // Limit reached - evict LRU and reuse
        return evictAndActivate(imageId)
    }

    /**
     * Release an activation slot.
     */
    function releasePlayer(imageId) {
        for (var i = 0; i < activeSlots.length; i++) {
            if (activeSlots[i].imageId === imageId) {
                activeSlots.splice(i, 1)
                console.log("[VideoPlayerPool] Released slot for:", imageId, "Total:", activeSlots.length)
                return
            }
        }
    }

    /**
     * Stop all - called when sidebar closes.
     * Just clears the slots array, causing all local MediaPlayers to lose their source.
     */
    function stopAll() {
        console.log("[VideoPlayerPool] Clearing all", activeSlots.length, "slots")
        activeSlots = []
    }

    // Internal: evict LRU slot and activate new
    function evictAndActivate(imageId) {
        if (activeSlots.length === 0) return null

        // Find LRU
        var lruIndex = 0
        var lruTime = activeSlots[0].lastUsed
        for (var i = 1; i < activeSlots.length; i++) {
            if (activeSlots[i].lastUsed < lruTime) {
                lruTime = activeSlots[i].lastUsed
                lruIndex = i
            }
        }

        var evictedId = activeSlots[lruIndex].imageId
        activeSlots[lruIndex].imageId = imageId
        activeSlots[lruIndex].lastUsed = Date.now()

        console.log("[VideoPlayerPool] Evicted slot from:", evictedId, "for:", imageId)
        return activeSlots[lruIndex]
    }

    // Handle config changes
    onMaxPlayersChanged: {
        while (activeSlots.length > maxPlayers) {
            // Find and remove LRU
            var lruIndex = 0
            var lruTime = activeSlots[0].lastUsed
            for (var i = 1; i < activeSlots.length; i++) {
                if (activeSlots[i].lastUsed < lruTime) {
                    lruTime = activeSlots[i].lastUsed
                    lruIndex = i
                }
            }
            console.log("[VideoPlayerPool] Shrinking: removed slot for:", activeSlots[lruIndex].imageId)
            activeSlots.splice(lruIndex, 1)
        }
    }

    // Connect to stopAllVideos signal
    Connections {
        target: typeof Booru !== "undefined" ? Booru : null
        function onStopAllVideos() {
            root.stopAll()
        }
    }
}
