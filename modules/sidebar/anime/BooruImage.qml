import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../common"
import "../../common/widgets"
import "../../common/utils"
import "../../common/functions/shell_utils.js" as ShellUtils
import "../../../services" as Services

/**
 * Individual booru image card with context menu.
 */
Button {
    id: root
    property var imageData
    property real rowHeight
    property bool manualDownload: false
    property string provider: ""
    property string previewDownloadPath
    property string downloadPath
    property string nsfwPath

    // Timing constants (milliseconds) - extracted for maintainability
    readonly property int triggerDelay: 100         // Allow property bindings to settle before triggering
    readonly property int videoPreviewDelay: 50     // Faster trigger for video preview thumbnails
    readonly property int progressCheckInterval: 500 // Balance responsiveness vs CPU for progress polling
    readonly property int retryDelay: 1000          // Give CDN time to recover before retry

    // Network constants - curl timeout values (seconds)
    readonly property int connectTimeout: 10        // TCP connection timeout
    readonly property int previewMaxTime: 30        // Max time for preview/thumbnail downloads
    readonly property int videoMaxTime: 300         // Max time for full video downloads (5 min for large files)
    readonly property int maxRetries: 2             // Retry count for failed downloads

    // Preview signals - emitted on hover for full-size preview
    signal showPreview(var imageData, string cachedSource, bool manualDownload, string provider)
    signal hidePreview()
    signal updatePreviewSource(string cachedSource)  // Emitted when download completes while preview is active

    // Pool activation entry (controls whether local MediaPlayer has source)
    property var poolEntry: null
    // Local player references (MediaPlayer is local, pool just controls activation)
    property var mediaPlayer: localMediaPlayer
    property var videoAudio: localAudioOutput

    // Stop video playback when sidebar closes
    Connections {
        target: Services.Booru
        function onStopAllVideos() {
            if (root.isVideo && root.mediaPlayer) {
                root.mediaPlayer.stop()
            }
        }
    }

    // Bug 1.6: Cleanup MediaPlayer resources to prevent memory leaks
    function cleanupMediaPlayer() {
        if (root.mediaPlayer) {
            root.mediaPlayer.stop()
            root.mediaPlayer.source = ""
        }
    }

    // Bug 1.6: Monitor pool entry changes to cleanup on eviction
    onPoolEntryChanged: {
        // If pool entry was taken away (eviction) or no longer matches this image, cleanup
        if (!poolEntry || (poolEntry && poolEntry.imageId !== root.imageData.id)) {
            cleanupMediaPlayer()
        }
    }

    // Listen for cache signals to update sources reactively
    Connections {
        target: Services.CacheIndex

        // Targeted file registration - only update this image if the file matches
        // This avoids the N^2 problem where ALL images re-evaluate on ANY registration
        function onFileRegistered(baseName, fullPath) {
            // Check if registered file matches any of our possible cache names
            if (baseName === root.fileName ||
                baseName === root.gifFileName ||
                baseName === root.videoBaseName ||
                baseName === root.highResFileName ||
                baseName === "hires_" + root.baseId + "." + root.fileExt ||
                baseName === "video_" + root.baseId + "." + root.fileExt ||
                baseName === "gif_" + root.baseId + "." + root.fileExt) {
                root.localCacheRefresh++
                Services.Logger.debug("BooruImage", `File registered for id=${root.imageData.id}: ${baseName}`)
            }
        }

        // Reset all cache state when cache is cleared
        // This fixes the "stuck low graphics" bug for Danbooru and other manual providers
        function onCacheCleared() {
            Services.Logger.info("BooruImage", `Cache cleared signal: id=${root.imageData.id}`)

            // Reset cache check flags - allows downloaders to re-run
            root.highResCacheChecked = false
            root.ugoiraCacheChecked = false
            root.videoPreviewCacheChecked = false
            root.videoDownloadFailed = false

            // Clear local source paths (these are plain properties, safe to assign)
            root.localHighResSource = ""
            root.localGifSource = ""
            root.localUgoiraSource = ""
            root.localVideoPreview = ""

            // INCREMENT LOCAL REFRESH COUNTER to force cached*Source bindings to re-evaluate
            // This fixes the race condition where CacheIndex.generation change notification
            // hasn't propagated yet and Image component tries to load deleted files
            root.localCacheRefresh++

            // Log state after reset for debugging
            Services.Logger.debug("BooruImage", `Post-reset state: id=${root.imageData.id} provider=${root.provider} manualDownload=${root.manualDownload} localRefresh=${root.localCacheRefresh}`)
        }
    }

    // Track hover via explicit MouseArea since Button.hovered doesn't work in layer shell
    property bool isHovered: hoverArea.containsMouse
    onIsHoveredChanged: {
        if (isHovered) {
            Services.Logger.debug("BooruImage", `Hover enter: id=${root.imageData.id} isVideo=${root.isVideo}`)
            // Track video player for keyboard controls
            if (root.isVideo) {
                Services.HoverTracker.hoveredVideoPlayer = root.mediaPlayer
                Services.HoverTracker.hoveredAudioOutput = root.videoAudio
            }
            // Track hovered image for TAB key preview toggle
            Services.HoverTracker.hoveredBooruImage = root
        } else {
            Services.Logger.debug("BooruImage", `Hover exit: id=${root.imageData.id}`)
            // Clear video player reference
            if (Services.HoverTracker.hoveredVideoPlayer === root.mediaPlayer) {
                Services.HoverTracker.hoveredVideoPlayer = null
                Services.HoverTracker.hoveredAudioOutput = null
            }
            // Clear hovered image reference
            if (Services.HoverTracker.hoveredBooruImage === root) {
                Services.HoverTracker.hoveredBooruImage = null
            }
        }
    }

    // TAB key toggle - called from parent when TAB pressed and this image is hovered
    function togglePreview() {
        if (root.isPreviewActive) {
            root.hidePreview()
        } else {
            var cachedSrc = ""
            if (root.isVideo || root.isArchive) {
                var videoSrc = videoContainer ? videoContainer.videoSource : ""
                if (videoSrc && videoSrc.indexOf("file://") === 0) {
                    cachedSrc = videoSrc
                } else if (root.cachedVideoSource) {
                    cachedSrc = root.cachedVideoSource
                }
            } else if (root.isGif) {
                var gifSrc = gifObject ? gifObject.source.toString() : ""
                if (gifSrc && gifSrc.indexOf("file://") === 0) {
                    cachedSrc = gifSrc
                } else if (root.cachedGifSource) {
                    cachedSrc = root.cachedGifSource
                } else if (root.cachedImageSource && root.cachedImageSource.toLowerCase().endsWith(".gif")) {
                    cachedSrc = root.cachedImageSource
                }
            } else if (root.cachedImageSource) {
                cachedSrc = root.cachedImageSource
            } else if (root.localHighResSource) {
                cachedSrc = root.localHighResSource
            }
            root.showPreview(root.imageData, cachedSrc, root.manualDownload, root.provider)
        }
    }

    // W key - save as wallpaper (called from parent when W pressed and this image is hovered)
    function saveAsWallpaper() {
        root.isSavedAsWallpaper = true
        var wallpaperPath = root.downloadPath.replace(/\/booru$/, '/wallpapers')
        if (root.useGrabber) {
            wallpaperDownloader.outputPath = wallpaperPath
            wallpaperDownloader.startDownload()
        } else {
            var escapedWpPath = shellEscape(wallpaperPath)
            var escapedUrl = shellEscape(root.imageData.file_url)
            var escapedFile = shellEscape(root.fileName)
            Quickshell.execDetached(["bash", "-c",
                "mkdir -p '" + escapedWpPath + "' && curl -sL -A 'Mozilla/5.0 BooruSidebar/1.0' '" + escapedUrl + "' -o '" + escapedWpPath + "/" + escapedFile + "' && notify-send 'Wallpaper saved' '" + escapedWpPath + "/" + escapedFile + "' -a 'Booru'"
            ])
        }
    }

    // Release pool player and cleanup MediaPlayer when component is destroyed
    Component.onDestruction: {
        // Bug 1.6: Cleanup MediaPlayer resources first
        cleanupMediaPlayer()
        if (root.poolEntry) {
            Services.VideoPlayerPool.releasePlayer(root.imageData.id)
        }
    }

    // Hover detection area (ZOrder.hoverDetector ensures it receives hover events on top)
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        z: ZOrder.hoverDetector
        hoverEnabled: true
        acceptedButtons: Qt.NoButton  // Don't intercept clicks, just track hover
        propagateComposedEvents: true
    }

    property string fileName: {
        var url = imageData.file_url ? imageData.file_url : ""
        var path = url.substring(url.lastIndexOf('/') + 1)
        // Strip query parameters (e.g., Sankaku signed URLs)
        var queryIdx = path.indexOf('?')
        if (queryIdx > 0) path = path.substring(0, queryIdx)
        return decodeURIComponent(path)
    }
    // Preview filename - based on preview_url for correct caching when different from file_url
    property string previewFileName: {
        var url = imageData.preview_url ? imageData.preview_url : (imageData.file_url || "")
        var path = url.substring(url.lastIndexOf('/') + 1)
        var queryIdx = path.indexOf('?')
        if (queryIdx > 0) path = path.substring(0, queryIdx)
        return decodeURIComponent(path)
    }
    property string filePath: root.previewDownloadPath + "/" + root.previewFileName
    property real imageRadius: Appearance.rounding.small

    property bool showActions: false

    // Shell escape helper - use shared utility
    function shellEscape(str) { return ShellUtils.shellEscape(str) }

    // Video detection - fallback to extracting from URL if file_ext not provided
    property string fileExt: {
        var ext = imageData.file_ext ? imageData.file_ext.toLowerCase() : ""
        if (!ext && imageData.file_url) {
            // Extract extension, stripping query parameters (for signed URLs like Sankaku)
            var url = imageData.file_url
            var queryIdx = url.indexOf('?')
            if (queryIdx > 0) url = url.substring(0, queryIdx)
            ext = url.split('.').pop().toLowerCase()
        }
        return ext
    }
    property bool isVideo: (fileExt === "mp4" || fileExt === "webm")

    // ═══════════════════════════════════════════════════════════════════════
    // ⚠️  CIRCULAR DEPENDENCY WARNING - READ BEFORE MODIFYING
    // ═══════════════════════════════════════════════════════════════════════
    //
    // These media type properties (isGif, isVideo, isArchive) must ONLY check
    // the API-provided `fileExt` - never `cachedImageSource` or other cache paths!
    //
    // DEPENDENCY CHAIN (if incorrectly checking cache):
    //   isGif → cachedImageSource → isGif  ← CIRCULAR!
    //
    // WHY: cachedImageSource (line ~295) excludes GIFs/videos from cache lookup:
    //   `if (root.isVideo || root.isGif) return ""`
    //
    // This is intentional - GIFs/videos have separate caching. But if isGif
    // were to check cachedImageSource, QML would detect the circular binding
    // and repeatedly re-evaluate both properties, causing severe UI lag.
    //
    // SAFE TO ADD: Properties that only depend on `fileExt` or `imageData`
    // UNSAFE: Any property that depends on cachedImageSource, cachedGifSource,
    //         cachedVideoSource, or other cache lookup results
    // ═══════════════════════════════════════════════════════════════════════

    property bool isGif: fileExt === "gif"
    property bool isArchive: (fileExt === "zip" || fileExt === "rar" || fileExt === "7z")  // Danbooru image packs

    // Computed helpers for visibility bindings (improves readability)
    property bool isUgoiraReady: root.isArchive && root.localUgoiraSource.length > 0
    property bool isStaticImage: !root.isVideo && !root.isGif && !root.isUgoiraReady
    property bool isAnimatedContent: root.isVideo || root.isGif || root.isUgoiraReady

    // Base identifier - md5 preferred (consistent across providers), fallback to id
    property string baseId: root.imageData.md5 ? root.imageData.md5 : root.imageData.id

    // File paths for download status checks
    property string savedFilePath: root.downloadPath + "/" + root.fileName
    property string savedNsfwFilePath: root.nsfwPath + "/" + root.fileName
    property string wallpaperFilePath: root.downloadPath.replace(/\/booru$/, '/wallpapers') + "/" + root.fileName

    // File existence state (checked async on load)
    property bool isSavedLocally: false
    property bool isSavedAsWallpaper: false

    // Local file paths for progressive loading (manual download providers)
    property string localHighResSource: ""

    // Local refresh counter - incremented in onCacheCleared to force binding re-evaluation
    // This fixes the race condition where CacheIndex.generation change notification
    // hasn't propagated before Image.Error fires on deleted files
    property int localCacheRefresh: 0

    // Universal cache - applies to ALL providers, not just manualDownload
    // CacheIndex provides instant O(1) lookup, no need for per-image Process
    property bool universalCacheChecked: Services.CacheIndex.initialized

    // Reactive cache lookup - re-evaluates when localCacheRefresh changes
    property string cachedImageSource: {
        // Only depend on LOCAL counter for reactive updates (not global CacheIndex.generation!)
        // Global generation caused ALL images to re-evaluate on ANY file registration = lag
        // localCacheRefresh is incremented by onFileRegistered ONLY when matching this image
        var _ = root.localCacheRefresh
        if (!Services.CacheIndex.initialized || root.isVideo || root.isGif) return ""
        return Services.CacheIndex.lookup(root.fileName)
    }

    // Resolution tracking - what resolution are we actually displaying?
    // 0=Unknown, 1=Preview (low-res), 2=Sample (mid-res), 3=HiRes (full-res)
    readonly property int resUnknown: 0
    readonly property int resPreview: 1
    readonly property int resSample: 2
    readonly property int resHiRes: 3
    property int currentResolution: resUnknown
    property string currentSourceType: ""  // "cache_hires", "cache_preview", "network_file", "local_hires", etc.
    property int displayedWidth: 0
    property int displayedHeight: 0

    // Check if currently cached source is hi-res (has hires_ prefix)
    property bool cachedIsHiRes: cachedImageSource.indexOf("/hires_") >= 0

    // Track previous source to detect degradation
    property string previousCachedSource: ""

    // Log when cachedImageSource changes and track resolution
    onCachedImageSourceChanged: {
        var wasHiRes = previousCachedSource.indexOf("/hires_") >= 0
        var nowHiRes = cachedIsHiRes

        if (cachedImageSource.length > 0) {
            if (wasHiRes && !nowHiRes) {
                // DEGRADATION DETECTED - switched from hires to preview!
                Services.Logger.error("BooruImage", `DEGRADED: id=${root.imageData.id} was=${previousCachedSource.substring(previousCachedSource.lastIndexOf('/') + 1)} now=${cachedImageSource.substring(cachedImageSource.lastIndexOf('/') + 1)}`)
            } else if (nowHiRes) {
                Services.Logger.info("BooruImage", `Cache HI-RES: id=${root.imageData.id} path=${cachedImageSource.substring(cachedImageSource.lastIndexOf('/') + 1)}`)
            } else {
                Services.Logger.warn("BooruImage", `Cache PREVIEW only: id=${root.imageData.id} (no hires_ file)`)
            }
        } else if (previousCachedSource.length > 0) {
            // Source cleared
            Services.Logger.warn("BooruImage", `Cache CLEARED: id=${root.imageData.id} was=${previousCachedSource.substring(previousCachedSource.lastIndexOf('/') + 1)}`)
        }

        previousCachedSource = cachedImageSource
    }

    // Local dimension overrides - don't mutate shared model data
    property int localWidth: 0
    property int localHeight: 0
    property real localAspectRatio: 0

    // Effective dimensions - prefer model data, fall back to locally computed
    property int effectiveWidth: root.imageData.width || root.localWidth || 300
    property int effectiveHeight: root.imageData.height || root.localHeight || 300
    property real effectiveAspectRatio: root.imageData.aspect_ratio || root.localAspectRatio || 1

    // Check if preview and file URLs are the same (e.g., Sankaku uses file_url for both)
    // Skip separate hi-res download when they match - saves bandwidth and time
    property bool previewIsFullRes: {
        var previewUrl = (root.imageData.preview_url || "").split("?")[0]
        var fileUrl = (root.imageData.file_url || "").split("?")[0]
        return previewUrl.length > 0 && previewUrl === fileUrl
    }

    // Manual download for preview images (providers that block direct requests)
    ImageDownloaderProcess {
        id: imageDownloader
        enabled: root.manualDownload && !root.isGif && !root.isVideo
        filePath: root.filePath
        sourceUrl: root.imageData.preview_url ? root.imageData.preview_url : ""
        property string downloadedPath: ""
        onDone: (path, width, height) => {
            downloadedPath = path
            // Store dimensions locally instead of mutating shared model
            if (!root.imageData.width || !root.imageData.height) {
                root.localWidth = width
                root.localHeight = height
                root.localAspectRatio = width / height
            }
            // If preview is already full-res (e.g., Sankaku), use it directly
            if (root.previewIsFullRes && path.length > 0) {
                root.localHighResSource = "file://" + path
            }
        }
    }

    // Manual download for high-res images (triggered after preview loads)
    property string highResFileName: {
        var url = imageData.file_url ? imageData.file_url : ""
        var path = url.substring(url.lastIndexOf('/') + 1)
        // Strip query parameters (e.g., Sankaku signed URLs)
        var queryIdx = path.indexOf('?')
        if (queryIdx > 0) path = path.substring(0, queryIdx)
        return "hires_" + decodeURIComponent(path)
    }
    property string highResFilePath: root.previewDownloadPath + "/" + root.highResFileName

    // Grabber uses md5-based filename for Danbooru
    property string grabberHighResPath: root.previewDownloadPath + "/hires_" + root.baseId + "." + root.fileExt

    // Unified cache check for all manual download providers
    property bool highResCacheChecked: false
    property string effectiveHighResPath: root.provider === "danbooru" ? root.grabberHighResPath : root.highResFilePath

    Process {
        id: highResCacheCheck
        running: root.manualDownload && !root.isGif && !root.isVideo && !root.isArchive && root.effectiveHighResPath.length > 0 && !root.highResCacheChecked
        command: ["test", "-f", root.effectiveHighResPath]
        onRunningChanged: {
            if (running) {
                Services.Logger.debug("BooruImage", `highResCacheCheck STARTING: id=${root.imageData.id}`)
            }
        }
        onExited: function(code, status) {
            root.highResCacheChecked = true
            if (code === 0) {
                // File exists - use it immediately
                Services.Logger.cacheHit("BooruImage")
                Services.Logger.debug("BooruImage", `Cache hit (hi-res): id=${root.imageData.id}`)
                root.localHighResSource = "file://" + root.effectiveHighResPath
            } else {
                Services.Logger.cacheMiss("BooruImage")
                Services.Logger.debug("BooruImage", `highResCacheCheck MISS: id=${root.imageData.id} - downloader should trigger`)
            }
            // If not cached, downloaders below will trigger
        }
    }

    // Download hi-res to cache for non-manual providers (after cache check)
    ImageDownloaderProcess {
        id: universalHighResDownloader
        enabled: !root.manualDownload && !root.isGif && !root.isVideo && !root.isArchive
                 && root.universalCacheChecked && root.cachedImageSource === ""
                 && root.imageData.file_url && root.imageData.file_url.length > 0
        filePath: root.highResFilePath
        sourceUrl: root.imageData.file_url ? root.imageData.file_url : ""
        // Zerochan provides extension fallbacks (.png, .jpeg, .webp) since API doesn't specify extension
        fallbackUrls: root.imageData.file_url_fallbacks ? root.imageData.file_url_fallbacks : []

        onDone: function(path, width, height) {
            if (path.length > 0) {
                Services.Logger.debug("BooruImage", `Hi-res downloaded: id=${root.imageData.id} ${width}x${height}`)
                var cachedPath = "file://" + path
                // Register in CacheIndex - this triggers generation++ which causes
                // cachedImageSource binding to re-evaluate. DO NOT directly assign!
                Services.CacheIndex.register(root.highResFileName, path)
                // Update preview if it's showing this image
                if (root.isPreviewActive) {
                    root.updatePreviewSource(cachedPath)
                }
            }
        }
    }

    ImageDownloaderProcess {
        id: highResDownloader
        // Use curl for non-Danbooru providers (only if not cached and preview isn't already full-res)
        enabled: root.manualDownload && root.provider !== "danbooru" && !root.previewIsFullRes && !root.isGif && !root.isVideo && !root.isArchive && imageDownloader.downloadedPath.length > 0 && root.highResCacheChecked && root.localHighResSource === ""
        filePath: root.highResFilePath
        sourceUrl: root.imageData.file_url ? root.imageData.file_url : ""
        fallbackUrls: root.imageData.file_url_fallbacks ? root.imageData.file_url_fallbacks : []
        onDone: (path, width, height) => {
            if (path.length > 0) {
                var cachedPath = "file://" + path
                root.localHighResSource = cachedPath
                // Update preview if it's showing this image
                if (root.isPreviewActive) {
                    root.updatePreviewSource(cachedPath)
                }
            } else {
                // High-res blocked - use preview as fallback
                root.localHighResSource = "file://" + imageDownloader.downloadedPath
            }
        }
    }

    GrabberDownloader {
        id: grabberHighResDownloader
        source: "danbooru.donmai.us"
        imageId: root.imageData.id ? String(root.imageData.id) : ""
        outputPath: root.previewDownloadPath
        filenameTemplate: "hires_%md5%.%ext%"
        user: Services.Booru.danbooruLogin
        password: Services.Booru.danbooruApiKey
        onDownloadingChanged: {
            if (downloading) {
                Services.Logger.info("BooruImage", `Grabber DOWNLOADING: id=${root.imageData.id}`)
            }
        }
        onDone: (success, message) => {
            if (success) {
                Services.Logger.info("BooruImage", `Grabber SUCCESS: id=${root.imageData.id}`)
                var fullPath = root.grabberHighResPath
                var cachedPath = "file://" + fullPath
                root.localHighResSource = cachedPath

                // CRITICAL: Register hi-res file in CacheIndex!
                // Without this, quickRefresh might register preview first,
                // and cachedImageSource binding would return preview instead of hires.
                var hiresFilename = fullPath.substring(fullPath.lastIndexOf('/') + 1)
                Services.CacheIndex.register(hiresFilename, fullPath)
                Services.Logger.debug("BooruImage", `Grabber registered: ${hiresFilename}`)

                // Update preview if it's showing this image
                if (root.isPreviewActive) {
                    root.updatePreviewSource(cachedPath)
                }
            } else {
                Services.Logger.error("BooruImage", `Grabber FAILED: id=${root.imageData.id} msg=${message}`)
                // Fallback to preview
                root.localHighResSource = "file://" + imageDownloader.downloadedPath
            }
        }
    }

    // Trigger Grabber download for Danbooru (only if not cached)
    Timer {
        id: grabberTrigger
        interval: root.triggerDelay
        running: root.manualDownload && root.provider === "danbooru" && !root.isGif && !root.isVideo && !root.isArchive && imageDownloader.downloadedPath.length > 0 && !grabberHighResDownloader.downloading && root.localHighResSource === "" && root.highResCacheChecked
        onRunningChanged: {
            if (running) {
                Services.Logger.debug("BooruImage", `grabberTrigger ARMED: id=${root.imageData.id} delay=${root.triggerDelay}ms`)
            }
        }
        onTriggered: {
            Services.Logger.info("BooruImage", `grabberTrigger FIRED: id=${root.imageData.id}`)
            grabberHighResDownloader.startDownload()
        }
    }

    // Manual download for GIFs (providers that block direct requests)
    property string gifFileName: {
        var url = modelData.file_url ? modelData.file_url : ""
        var path = url.substring(url.lastIndexOf('/') + 1)
        // Strip query parameters (e.g., Sankaku signed URLs)
        var queryIdx = path.indexOf('?')
        if (queryIdx > 0) path = path.substring(0, queryIdx)
        return decodeURIComponent(path)
    }
    property string gifFilePath: root.previewDownloadPath + "/gif_" + root.gifFileName
    property string localGifSource: ""

    // Universal GIF cache - uses CacheIndex for O(1) lookups
    // CacheIndex.lookup() internally checks gif_ prefix and extension variants
    property bool gifCacheChecked: Services.CacheIndex.initialized
    property string cachedGifSource: {
        // Only depend on LOCAL counter (not global CacheIndex.generation!)
        var _ = root.localCacheRefresh
        if (!Services.CacheIndex.initialized || !root.isGif) return ""
        return Services.CacheIndex.lookup(root.gifFileName)
    }

    ImageDownloaderProcess {
        id: gifDownloader
        // Skip Danbooru - CDN blocks curl, use Grabber instead
        enabled: root.manualDownload && root.isGif && root.provider !== "danbooru"
        filePath: root.gifFilePath
        sourceUrl: modelData.file_url ? modelData.file_url : ""
        onDone: function(path, width, height) {
            if (path.length > 0) {
                root.localGifSource = "file://" + path
            } else {
                // GIF blocked - use preview as static fallback
                root.localGifSource = modelData.preview_url ? modelData.preview_url : ""
            }
        }
    }

    // Grabber-based GIF downloader for Danbooru (bypasses Cloudflare)
    property string grabberGifPath: root.previewDownloadPath + "/gif_%md5%.gif".replace("%md5%", root.imageData.md5 || "")
    GrabberDownloader {
        id: grabberGifDownloader
        source: "danbooru.donmai.us"
        imageId: root.imageData.id ? String(root.imageData.id) : ""
        outputPath: root.previewDownloadPath
        filenameTemplate: "gif_%md5%.%ext%"
        user: Services.Booru.danbooruLogin
        password: Services.Booru.danbooruApiKey
        onDone: (success, message) => {
            if (success) {
                var cachedPath = "file://" + root.grabberGifPath
                root.localGifSource = cachedPath
                Services.Logger.info("BooruImage", `Grabber GIF downloaded: ${root.imageData.id}`)
                // Update preview if it's showing this GIF
                if (root.isPreviewActive) {
                    root.updatePreviewSource(cachedPath)
                }
            } else {
                Services.Logger.warn("BooruImage", `Grabber GIF failed: ${message}`)
                // Fallback to static preview
                root.localGifSource = modelData.preview_url ? modelData.preview_url : ""
            }
        }
    }

    // Trigger Grabber GIF download for Danbooru
    Timer {
        id: grabberGifTrigger
        interval: root.triggerDelay
        running: root.manualDownload && root.provider === "danbooru" && root.isGif
                 && root.localGifSource === "" && !grabberGifDownloader.downloading
        onTriggered: grabberGifDownloader.startDownload()
    }

    // Download GIF to cache for non-manual providers
    ImageDownloaderProcess {
        id: universalGifDownloader
        enabled: root.isGif && !root.manualDownload && root.gifCacheChecked
                 && root.cachedGifSource === "" && root.imageData.file_url
        filePath: root.gifFilePath
        sourceUrl: root.imageData.file_url ? root.imageData.file_url : ""
        onDone: function(path, width, height) {
            if (path.length > 0) {
                var cachedPath = "file://" + path
                // Register in CacheIndex - this triggers generation++ which causes
                // cachedGifSource binding to re-evaluate. DO NOT directly assign!
                Services.CacheIndex.register("gif_" + root.gifFileName, path)
                // Update preview if it's showing this GIF
                if (root.isPreviewActive) {
                    root.updatePreviewSource(cachedPath)
                }
            }
        }
    }

    // Ugoira (animated ZIP) support
    // Danbooru provides pre-converted WebM at sample_url (large_file_url)
    // We download this directly instead of downloading ZIP + converting
    property string ugoiraVideoPath: root.previewDownloadPath + "/ugoira_" + root.baseId + ".webm"
    property string ugoiraSampleUrl: root.imageData.sample_url ? root.imageData.sample_url : ""
    property string localUgoiraSource: ""
    property bool ugoiraCacheChecked: false
    property bool ugoiraDownloading: false

    // Check if WebM already exists in cache
    Process {
        id: ugoiraCacheCheck
        running: root.isArchive && root.ugoiraVideoPath.length > 0 && !root.ugoiraCacheChecked
        command: ["test", "-f", root.ugoiraVideoPath]
        onExited: (code, status) => {
            root.ugoiraCacheChecked = true
            if (code === 0) {
                root.localUgoiraSource = "file://" + root.ugoiraVideoPath
            }
        }
    }

    // Download pre-converted WebM from sample_url (works for Danbooru, AIBooru, etc.)
    // Uses bash to create cache directory, then curl with browser headers
    Process {
        id: ugoiraDownloader
        property bool downloading: false
        running: false

        // Build command dynamically with proper shell escaping
        function buildCommand() {
            var path = shellEscape(root.ugoiraVideoPath)
            var url = shellEscape(root.ugoiraSampleUrl)
            return ["bash", "-c",
                `mkdir -p "$(dirname '${path}')" && ` +
                `curl -sL '${url}' ` +
                `-H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36' ` +
                `-o '${path}'`
            ]
        }

        command: buildCommand()

        onRunningChanged: {
            if (running) downloading = true
        }

        onExited: (code, status) => {
            downloading = false
            root.ugoiraDownloading = false
            if (code === 0) {
                var cachedPath = "file://" + root.ugoiraVideoPath
                root.localUgoiraSource = cachedPath
                // Update preview if it's showing this ugoira
                if (root.isPreviewActive) {
                    root.updatePreviewSource(cachedPath)
                }
            }
        }
    }

    // Timer to trigger download after cache check
    // Uses repeat: false and internal guard to prevent race conditions
    Timer {
        id: ugoiraDownloadTrigger
        interval: root.triggerDelay
        repeat: false
        running: root.isArchive && root.ugoiraCacheChecked && root.localUgoiraSource === "" && root.ugoiraSampleUrl.length > 0
        onTriggered: {
            // Guard against race condition - check flags inside handler
            if (root.ugoiraDownloading || ugoiraDownloader.downloading) return
            root.ugoiraDownloading = true
            // Rebuild command with current URLs before starting
            ugoiraDownloader.command = ugoiraDownloader.buildCommand()
            ugoiraDownloader.running = true
        }
    }

    // Universal video cache - uses CacheIndex for O(1) lookups
    // CacheIndex.lookup() internally checks video_ prefix variant
    property bool videoCacheChecked: Services.CacheIndex.initialized
    // Base name for video cache (without video_ prefix - CacheIndex adds it)
    property string videoBaseName: root.baseId + "." + root.fileExt
    property string cachedVideoSource: {
        // Only depend on LOCAL counter (not global CacheIndex.generation!)
        var _ = root.localCacheRefresh
        if (!Services.CacheIndex.initialized || !root.isVideo) return ""
        return Services.CacheIndex.lookup(root.videoBaseName)
    }
    property bool videoDownloadFailed: false
    property string videoFilePath: root.previewDownloadPath + "/video_" + root.videoBaseName

    // Video preview for manualDownload providers (Sankaku CDN blocks direct image requests)
    property string videoPreviewPath: root.previewDownloadPath + "/vidpreview_" + root.baseId + ".jpg"
    property string localVideoPreview: ""
    property bool videoPreviewCacheChecked: false

    // Combined loading state for videos (cache check, download, preview download)
    property bool videoIsLoading: root.isVideo && (
        !root.videoCacheChecked ||                                    // Video cache check in progress
        universalVideoDownloader.downloading ||                       // Video downloading
        (root.manualDownload && !root.videoPreviewCacheChecked) ||    // Preview cache check
        (root.manualDownload && videoPreviewDownloader.downloading)   // Preview downloading
    )

    // Check if video preview is already cached
    Process {
        id: videoPreviewCacheCheck
        running: root.isVideo && root.manualDownload && !root.videoPreviewCacheChecked && root.videoPreviewPath.length > 0
        command: ["test", "-s", root.videoPreviewPath]
        onExited: function(code, status) {
            root.videoPreviewCacheChecked = true
            if (code === 0) {
                root.localVideoPreview = "file://" + root.videoPreviewPath
            }
        }
    }

    Process {
        id: videoPreviewDownloader
        property bool downloading: false
        running: false

        function buildCommand() {
            var previewUrl = root.imageData.preview_url || ""
            var url = shellEscape(previewUrl)
            var jpgPath = shellEscape(root.videoPreviewPath)
            var avifPath = shellEscape(root.videoPreviewPath.replace(".jpg", ".avif"))

            // Check if preview URL is AVIF (Sankaku videos use AVIF previews)
            // If so, download AVIF and convert to JPEG using avifdec
            var curlOpts = `--connect-timeout ${root.connectTimeout} --max-time ${root.previewMaxTime}`
            if (previewUrl.indexOf(".avif") >= 0) {
                return ["bash", "-c",
                    `mkdir -p "$(dirname '${jpgPath}')" && ` +
                    `curl -fsSL ${curlOpts} -A 'Mozilla/5.0 BooruSidebar/1.0' '${url}' -o '${avifPath}' && ` +
                    `[ -s '${avifPath}' ] && ` +
                    `avifdec '${avifPath}' '${jpgPath}' >/dev/null 2>&1 && ` +
                    `rm -f '${avifPath}' && ` +
                    `[ -s '${jpgPath}' ]`
                ]
            } else {
                // Non-AVIF preview, download directly
                return ["bash", "-c",
                    `mkdir -p "$(dirname '${jpgPath}')" && ` +
                    `curl -fsSL ${curlOpts} -A 'Mozilla/5.0 BooruSidebar/1.0' '${url}' -o '${jpgPath}' && ` +
                    `[ -s '${jpgPath}' ]`
                ]
            }
        }

        command: buildCommand()

        onRunningChanged: {
            if (running) downloading = true
        }

        onExited: function(code, status) {
            downloading = false
            if (code === 0) {
                root.localVideoPreview = "file://" + root.videoPreviewPath
            } else {
                Services.Logger.warn("BooruImage", `Video preview download/conversion failed: ${root.imageData.preview_url}`)
            }
        }
    }

    Timer {
        id: videoPreviewTrigger
        interval: root.videoPreviewDelay
        repeat: false
        // Download preview for manualDownload providers showing videos (after cache check)
        running: root.isVideo && root.manualDownload && root.videoPreviewCacheChecked
                 && root.localVideoPreview === ""
                 && (root.imageData.preview_url || root.imageData.sample_url)
                 && !videoPreviewDownloader.downloading
        onTriggered: {
            if (!videoPreviewDownloader.downloading) {
                videoPreviewDownloader.command = videoPreviewDownloader.buildCommand()
                videoPreviewDownloader.running = true
            }
        }
    }

    // Video download progress tracking
    property int videoDownloadProgress: 0  // 0-100 percentage
    property int videoFileSize: root.imageData.file_size || 0  // Expected size in bytes

    function formatFileSize(bytes) {
        if (bytes <= 0) return ""
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1024 * 1024) return Math.round(bytes / 1024) + " KB"
        return (bytes / (1024 * 1024)).toFixed(1) + " MB"
    }

    // Download video to cache (after cache check)
    Process {
        id: universalVideoDownloader
        property bool downloading: false
        property int retryCount: 0
        running: false

        // Build command dynamically when starting to ensure fresh URL
        function buildCommand() {
            var url = shellEscape(root.imageData.file_url || "")
            var path = shellEscape(root.videoFilePath)
            // Danbooru blocks custom User-Agent, Sankaku requires it
            var userAgent = root.provider === "danbooru" ? "" : "-A 'Mozilla/5.0 BooruSidebar/1.0' "
            var curlOpts = `--connect-timeout ${root.connectTimeout} --max-time ${root.videoMaxTime}`
            // Validate downloaded file is actually a video, not an HTML error page
            // Sankaku CDN returns 403 HTML with HTTP 200 status on expired tokens
            return ["bash", "-c",
                `mkdir -p "$(dirname '${path}')" && ` +
                `curl -fSL ${curlOpts} ${userAgent}'${url}' -o '${path}' && ` +
                `[ -s '${path}' ] && ` +  // File exists and non-empty
                `file -b '${path}' | grep -qiE 'video|MP4|WebM|ISO Media' || ` +  // Must be video
                `{ rm -f '${path}'; exit 1; }`  // Delete HTML error page, fail
            ]
        }

        command: buildCommand()

        onRunningChanged: {
            if (running) {
                downloading = true
                root.videoDownloadProgress = 0
                videoProgressTimer.start()
            }
        }

        onExited: function(code, status) {
            videoProgressTimer.stop()
            if (code === 0) {
                downloading = false
                retryCount = 0
                root.videoDownloadFailed = false
                root.videoDownloadProgress = 100
                var cachedPath = "file://" + root.videoFilePath
                // Register in CacheIndex - this triggers generation++ which causes
                // cachedVideoSource binding to re-evaluate. DO NOT directly assign!
                var videoName = "video_" + root.videoBaseName
                Services.CacheIndex.register(videoName, root.videoFilePath)
                // Re-request pool slot if evicted while downloading (ensures source binding updates)
                if (videoContainer.visible && (!root.poolEntry || root.poolEntry.imageId !== root.imageData.id)) {
                    root.poolEntry = Services.VideoPlayerPool.requestPlayer(root.imageData.id)
                }
                // Update preview if it's showing this video
                if (root.isPreviewActive) {
                    root.updatePreviewSource(cachedPath)
                }
            } else {
                // Retry on failure
                if (retryCount < root.maxRetries) {
                    retryCount++
                    Services.Logger.warn("BooruImage", `Video download failed, retry ${retryCount}/${root.maxRetries}: ${root.imageData.file_url}`)
                    videoRetryTimer.start()
                } else {
                    downloading = false
                    retryCount = 0
                    root.videoDownloadFailed = true
                    Services.Logger.error("BooruImage", `Video download failed after ${root.maxRetries} retries: ${root.imageData.file_url}`)
                }
            }
        }
    }

    // Check download progress periodically
    Timer {
        id: videoProgressTimer
        interval: root.progressCheckInterval
        repeat: true
        running: false
        onTriggered: videoProgressChecker.running = true
    }

    Process {
        id: videoProgressChecker
        running: false
        command: ["stat", "-c", "%s", root.videoFilePath]
        stdout: StdioCollector {
            onStreamFinished: {
                var currentSize = parseInt(text.trim()) || 0
                if (root.videoFileSize > 0 && currentSize > 0) {
                    root.videoDownloadProgress = Math.min(99, Math.round((currentSize / root.videoFileSize) * 100))
                }
            }
        }
    }

    Timer {
        id: videoRetryTimer
        interval: root.retryDelay
        repeat: false
        onTriggered: {
            universalVideoDownloader.command = universalVideoDownloader.buildCommand()
            universalVideoDownloader.running = true
        }
    }

    Timer {
        id: videoDownloadTrigger
        interval: root.triggerDelay
        repeat: false
        running: root.isVideo && root.videoCacheChecked && root.cachedVideoSource === ""
                 && root.imageData.file_url && root.imageData.file_url.length > 0
                 && !universalVideoDownloader.downloading
        onTriggered: {
            if (!universalVideoDownloader.downloading) {
                universalVideoDownloader.command = universalVideoDownloader.buildCommand()
                universalVideoDownloader.running = true
            }
        }
    }

    // Grabber-based downloader for high-quality downloads with metadata-aware filenames
    // Falls back to curl if provider not supported by Grabber
    property string grabberSource: Services.Booru.getGrabberSource(root.provider)
    property bool useGrabber: grabberSource && grabberSource.length > 0

    GrabberDownloader {
        id: grabberDownloader
        source: root.grabberSource
        imageId: root.imageData.id ? String(root.imageData.id) : ""
        filenameTemplate: Services.Booru.filenameTemplate

        onDone: (success, message) => {
            if (success) {
                Quickshell.execDetached(["notify-send", "Download complete", message, "-a", "Booru"])
            } else {
                // Fallback to curl on Grabber failure (User-Agent for Sankaku etc.)
                Services.Logger.warn("BooruImage", `Grabber failed, falling back to curl: ${message}`)
                var targetPath = root.imageData.is_nsfw ? root.nsfwPath : root.downloadPath
                var escapedPath = shellEscape(targetPath)
                var escapedUrl = shellEscape(root.imageData.file_url)
                var escapedFile = shellEscape(root.fileName)
                Quickshell.execDetached(["bash", "-c",
                    "mkdir -p '" + escapedPath + "' && curl -sL -A 'Mozilla/5.0 BooruSidebar/1.0' '" + escapedUrl + "' -o '" + escapedPath + "/" + escapedFile + "' && notify-send 'Download complete' '" + escapedPath + "/" + escapedFile + "' -a 'Booru'"
                ])
            }
        }
    }

    GrabberDownloader {
        id: wallpaperDownloader
        source: root.grabberSource
        imageId: root.imageData.id ? String(root.imageData.id) : ""
        filenameTemplate: Services.Booru.filenameTemplate

        onDone: (success, message) => {
            if (success) {
                Quickshell.execDetached(["notify-send", "Wallpaper saved", message, "-a", "Booru"])
            } else {
                // Fallback to curl on Grabber failure (User-Agent for Sankaku etc.)
                Services.Logger.warn("BooruImage", `Grabber wallpaper failed, falling back to curl: ${message}`)
                var wallpaperPath = root.downloadPath.replace(/\/booru$/, '/wallpapers')
                var escapedWpPath = shellEscape(wallpaperPath)
                var escapedUrl = shellEscape(root.imageData.file_url)
                var escapedFile = shellEscape(root.fileName)
                Quickshell.execDetached(["bash", "-c",
                    "mkdir -p '" + escapedWpPath + "' && curl -sL -A 'Mozilla/5.0 BooruSidebar/1.0' '" + escapedUrl + "' -o '" + escapedWpPath + "/" + escapedFile + "' && notify-send 'Wallpaper saved' '" + escapedWpPath + "/" + escapedFile + "' -a 'Booru'"
                ])
            }
        }
    }

    // Check if file exists locally (downloaded or as wallpaper)
    // Use Timer to ensure all properties are bound before checking
    Timer {
        id: fileCheckTimer
        interval: root.triggerDelay
        running: root.fileName.length > 0 && root.downloadPath.length > 0
        onTriggered: {
            // Build command dynamically when timer fires to ensure paths are set
            fileChecker.command = ["bash", "-c",
                "SAVED=0; WP=0; " +
                "[ -f '" + root.savedFilePath + "' ] && SAVED=1; " +
                "[ -f '" + root.savedNsfwFilePath + "' ] && SAVED=1; " +
                "[ -f '" + root.wallpaperFilePath + "' ] && WP=1; " +
                "echo $SAVED $WP"
            ]
            fileChecker.running = true
        }
    }

    Process {
        id: fileChecker
        property bool handled: false

        onRunningChanged: {
            if (running) handled = false
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (fileChecker.handled) return
                fileChecker.handled = true
                var parts = text.trim().split(" ")
                if (parts.length >= 2) {
                    root.isSavedLocally = (parts[0] === "1")
                    root.isSavedAsWallpaper = (parts[1] === "1")
                }
            }
        }

        onExited: (code, status) => {
            // Fallback if stdout didn't fire
            if (!fileChecker.handled) {
                fileChecker.handled = true
            }
        }
    }

    StyledToolTip {
        // Show first 5 tags, truncated to max 200 chars
        property var tagList: (root.imageData.tags ? root.imageData.tags : "").split(" ").filter(t => t.length > 0)
        property string rawContent: tagList.slice(0, 5).join(", ") + (tagList.length > 5 ? " ..." : "")
        content: rawContent.length > 200 ? rawContent.substring(0, 200) + "..." : rawContent
    }

    padding: 0
    implicitWidth: root.rowHeight * (root.effectiveAspectRatio)
    implicitHeight: root.rowHeight
    z: showActions ? 100 : 0

    background: Rectangle {
        implicitWidth: root.rowHeight * (root.effectiveAspectRatio)
        implicitHeight: root.rowHeight
        radius: imageRadius
        color: Appearance.colors.colLayer2
    }

    contentItem: Item {
        anchors.fill: parent

        // Static image display with progressive loading (non-GIF, non-video)
        // Structure: Container with OpacityMask > [HighRes + BlurredPreview overlay]
        Item {
            id: staticImageContainer
            anchors.fill: parent
            // Hide for animated content (video, GIF, or converted ugoira)
            visible: root.isStaticImage

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: root.rowHeight * (root.effectiveAspectRatio)
                    height: root.rowHeight
                    radius: imageRadius
                }
            }

            // High-res image (loads in background)
            Image {
                id: highResImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                // Pure source binding - no side effects
                source: {
                    if (root.isVideo || root.isGif) return ""

                    // 1. Universal cache takes priority (any provider)
                    if (root.cachedImageSource.length > 0) {
                        return root.cachedImageSource
                    }

                    // 2. Manual download providers use their own path
                    if (root.manualDownload) {
                        return root.localHighResSource || ""
                    }

                    // 3. Wait for cache check before loading from network
                    if (!root.universalCacheChecked) {
                        return ""
                    }

                    // 4. Network fallback - file_url is hi-res
                    return modelData.file_url || ""
                }
                // Use 1.5x for decent quality without excessive memory
                // (2x was doubling memory usage for marginal HiDPI benefit)
                sourceSize.width: parent.width * 1.5
                sourceSize.height: parent.height * 1.5
                asynchronous: true
                cache: true

                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }

                // Track dimensions and log when image finishes loading
                onStatusChanged: {
                    if (status === Image.Ready) {
                        root.displayedWidth = implicitWidth
                        root.displayedHeight = implicitHeight

                        // Determine source type and resolution from actual source URL
                        var src = highResImage.source.toString()
                        var sourceType = "unknown"
                        var resolution = root.resUnknown

                        if (src.indexOf("file://") === 0) {
                            // Local file
                            if (src.indexOf("/hires_") >= 0) {
                                sourceType = "cache_hires"
                                resolution = root.resHiRes
                            } else if (src.indexOf("/.cache/") >= 0) {
                                sourceType = "cache_preview"
                                resolution = root.resPreview
                            } else {
                                sourceType = "local_hires"
                                resolution = root.resHiRes
                            }
                        } else if (src.length > 0) {
                            // Network URL - file_url is hi-res
                            sourceType = "network_file"
                            resolution = root.resHiRes
                        }

                        root.currentSourceType = sourceType
                        root.currentResolution = resolution

                        var resName = resolution === root.resHiRes ? "HI-RES" :
                                      resolution === root.resPreview ? "PREVIEW" : "UNKNOWN"
                        Services.Logger.info("BooruImage", `Rendered: id=${root.imageData.id} ${implicitWidth}x${implicitHeight} source=${sourceType} resolution=${resName}`)
                    } else if (status === Image.Error) {
                        Services.Logger.error("BooruImage", `RENDER FAILED: id=${root.imageData.id} src=${highResImage.source}`)
                    }
                }
            }

            // Blurred preview overlay (fades out when high-res ready)
            Item {
                id: blurOverlay
                anchors.fill: parent
                visible: opacity > 0
                opacity: highResImage.status === Image.Ready ? 0 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutCubic
                    }
                }

                Image {
                    id: previewImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    property string previewSourceType: ""
                    source: {
                        if (!blurOverlay.visible) return ""
                        if (root.isVideo || root.isGif) return ""
                        // For manual download providers, use local preview file
                        if (root.manualDownload) {
                            if (imageDownloader.downloadedPath) {
                                previewSourceType = "local_preview"
                                return "file://" + imageDownloader.downloadedPath
                            }
                            previewSourceType = "waiting"
                            return ""
                        }
                        // Fallback chain: preview -> sample -> file_url
                        var url = ""
                        if (modelData.preview_url) {
                            url = modelData.preview_url
                            previewSourceType = "preview_url"
                        } else if (modelData.sample_url) {
                            url = modelData.sample_url
                            previewSourceType = "sample_url"
                        } else if (modelData.file_url) {
                            url = modelData.file_url
                            previewSourceType = "file_url"
                        }
                        if (!url) {
                            previewSourceType = "none"
                            return ""
                        }
                        // Append cacheBust param to bypass Qt network cache when refreshing
                        if (Services.Booru.cacheBust > 0) {
                            url += (url.indexOf("?") >= 0 ? "&_cb=" : "?_cb=") + Services.Booru.cacheBust
                        }
                        return url
                    }
                    sourceSize.width: root.rowHeight * (root.effectiveAspectRatio)
                    sourceSize.height: root.rowHeight
                    asynchronous: true
                    cache: true
                    visible: false  // Only used as blur source

                    onStatusChanged: {
                        if (status === Image.Ready) {
                            Services.Logger.debug("BooruImage", `Preview loaded: id=${root.imageData.id} ${implicitWidth}x${implicitHeight} source=${previewSourceType}`)
                        }
                    }
                }

                FastBlur {
                    anchors.fill: parent
                    source: previewImage
                    radius: 32
                    transparentBorder: false
                }
            }

            // Archive/Ugoira badge - shows status, hidden when video is playing
            Rectangle {
                visible: root.isArchive && root.localUgoiraSource === ""
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.margins: 6
                width: archiveBadgeRow.width + 10
                height: 18
                radius: 4
                color: root.ugoiraDownloading ? Qt.rgba(0.2, 0.5, 0.8, 0.9) : Qt.rgba(0.6, 0.3, 0, 0.8)

                Row {
                    id: archiveBadgeRow
                    anchors.centerIn: parent
                    spacing: 3

                    MaterialSymbol {
                        visible: !root.ugoiraDownloading
                        anchors.verticalCenter: parent.verticalCenter
                        iconSize: 12
                        color: "#ffffff"
                        text: "play_circle"
                    }

                    StyledText {
                        id: archiveLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.ugoiraDownloading ? "..." : "UGOIRA"  // Show dots while downloading
                        font.pixelSize: 10
                        font.bold: true
                        color: "#ffffff"
                    }
                }
            }
        }

        // GIF preview (shown while loading)
        Image {
            id: gifPreview
            anchors.fill: parent
            // Hide preview for manual download providers (they block direct image requests)
            visible: root.isGif && !root.manualDownload && gifObject.status !== AnimatedImage.Ready
            fillMode: Image.PreserveAspectCrop
            source: (root.isGif && !root.manualDownload) ? (modelData.preview_url ? modelData.preview_url : "") : ""
            asynchronous: true

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: gifPreview.width
                    height: gifPreview.height
                    radius: imageRadius
                }
            }

            // GIF badge
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.margins: 6
                width: gifLabel.width + 8
                height: 18
                radius: 4
                color: Qt.rgba(0, 0, 0, 0.6)

                StyledText {
                    id: gifLabel
                    anchors.centerIn: parent
                    text: "GIF"
                    font.pixelSize: 10
                    font.bold: true
                    color: "#ffffff"
                }
            }
        }

        // GIF display - cache: true required for looping from network sources
        AnimatedImage {
            id: gifObject
            anchors.fill: parent
            visible: root.isGif
            fillMode: Image.PreserveAspectCrop
            // Universal cache first, then manual download path, then network
            source: {
                if (!root.isGif) return ""
                // Universal cache first
                if (root.cachedGifSource.length > 0) return root.cachedGifSource
                // Also check image cache (zerochan GIFs found via extension variant lookup with hires_ prefix)
                if (root.cachedImageSource.length > 0 && root.cachedImageSource.toLowerCase().endsWith(".gif")) {
                    return root.cachedImageSource
                }
                // Manual download providers
                if (root.manualDownload) return root.localGifSource
                // Wait for cache check
                if (!root.gifCacheChecked) return ""
                return modelData.file_url ? modelData.file_url : ""
            }
            asynchronous: true
            cache: true  // Required for looping from network sources per Qt docs
            playing: true

            opacity: status === AnimatedImage.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: gifObject.width
                    height: gifObject.height
                    radius: imageRadius
                }
            }
        }

        // Video display (MediaPlayer + VideoOutput) - handles both regular videos and ugoira WebM
        Item {
            id: videoContainer
            anchors.fill: parent
            // Show for regular videos OR ugoira with downloaded WebM
            visible: root.isVideo || root.isUgoiraReady

            // Compute video source: ugoira → cached → network (if allowed)
            property string videoSource: {
                if (root.isUgoiraReady) {
                    return root.localUgoiraSource
                } else if (root.isVideo) {
                    // Universal cache first
                    if (root.cachedVideoSource.length > 0) return root.cachedVideoSource
                    // Wait for cache check
                    if (!root.videoCacheChecked) return ""
                    // Manual download providers (Sankaku, e621, etc.) can't stream directly
                    // Qt MediaPlayer doesn't send User-Agent headers, so CDN blocks the request
                    // Wait for curl download to complete instead
                    if (root.manualDownload) return ""
                    return root.imageData.file_url ? root.imageData.file_url : ""
                }
                return ""
            }

            // Helper for playback state check
            property bool isPlaying: localMediaPlayer.playbackState === MediaPlayer.PlayingState

            // Debug: Log when video container conditions change
            Component.onCompleted: {
                if (root.isVideo) {
                    Services.Logger.debug("BooruImage", `Video item created: ${root.imageData.id} visible: ${visible} videoSource: ${videoSource.substring(0, 50)} videoCacheChecked: ${root.videoCacheChecked}`)
                }
            }

            // Request/release pool slot based on visibility
            // Pool entry controls whether local MediaPlayer has source (via binding)
            onVisibleChanged: {
                if (visible && root.isVideo && videoContainer.videoSource.length > 0) {
                    root.poolEntry = Services.VideoPlayerPool.requestPlayer(root.imageData.id)
                    if (root.poolEntry && Services.VideoPlayerPool.autoplay) {
                        localMediaPlayer.play()
                    }
                } else if (!visible && root.poolEntry) {
                    Services.VideoPlayerPool.releasePlayer(root.imageData.id)
                    root.poolEntry = null
                }
            }

            // Also request pool slot when video source becomes available
            onVideoSourceChanged: {
                if (visible && root.isVideo && videoSource.length > 0 && !root.poolEntry) {
                    root.poolEntry = Services.VideoPlayerPool.requestPlayer(root.imageData.id)
                    if (root.poolEntry && Services.VideoPlayerPool.autoplay) {
                        localMediaPlayer.play()
                    }
                }
            }

            // Preview thumbnail while video is loading/downloading
            Image {
                id: videoPreviewImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                // Show preview while video not playing (downloading or buffering)
                visible: !videoContainer.isPlaying
                // For manualDownload providers, use downloaded preview if available
                // Fallback to direct URL (may fail for some CDNs but worth trying)
                source: {
                    if (root.manualDownload) {
                        if (root.localVideoPreview.length > 0) return root.localVideoPreview
                        // Fallback to direct URL while downloading
                        return modelData.preview_url ? modelData.preview_url : ""
                    }
                    return modelData.preview_url ? modelData.preview_url : ""
                }
                asynchronous: true

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: videoPreviewImage.width
                        height: videoPreviewImage.height
                        radius: imageRadius
                    }
                }
            }

            // Solid background shown if preview doesn't load (CDN blocked, etc.)
            Rectangle {
                anchors.fill: parent
                radius: imageRadius
                color: Appearance.colors.colLayer2
                visible: videoPreviewImage.status !== Image.Ready
                         && !videoContainer.isPlaying
                z: -1
            }

            // Local MediaPlayer - source controlled by pool activation
            // Check poolEntry.imageId matches to handle eviction (slot object is mutated, not replaced)
            MediaPlayer {
                id: localMediaPlayer
                source: (root.poolEntry && root.poolEntry.imageId === root.imageData.id) ? videoContainer.videoSource : ""
                loops: MediaPlayer.Infinite
                audioOutput: AudioOutput {
                    id: localAudioOutput
                    muted: !root.isHovered
                }
                videoOutput: videoOutput
            }

            VideoOutput {
                id: videoOutput
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: videoOutput.width
                        height: videoOutput.height
                        radius: imageRadius
                    }
                }
            }

            // Play icon overlay (shown when ready, not while loading)
            Rectangle {
                anchors.centerIn: parent
                width: 40
                height: 40
                radius: 20
                color: Qt.rgba(0, 0, 0, 0.6)
                // Hide during all loading states - show loading indicator instead
                visible: !videoContainer.isPlaying
                         && !root.videoIsLoading
                         && videoContainer.videoSource.length > 0

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 24
                    color: "#ffffff"
                    text: "play_arrow"
                }
            }

            // Sound indicator (bottom-right corner, shown on hover when video is playing)
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 6
                width: 28
                height: 28
                radius: 14
                color: Qt.rgba(0, 0, 0, 0.6)
                visible: root.isHovered && videoContainer.isPlaying

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 18
                    color: "#ffffff"
                    text: "volume_up"
                }
            }

            // Video loading indicator (cache check, download, preview download)
            Rectangle {
                id: videoDownloadIndicator
                anchors.centerIn: parent
                width: root.videoFileSize > 0 && universalVideoDownloader.downloading ? 70 : 40
                height: 40
                radius: 20
                color: Qt.rgba(0, 0, 0, 0.7)
                visible: root.videoIsLoading && root.cachedVideoSource === ""

                Row {
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        iconSize: 20
                        color: "#ffffff"
                        text: universalVideoDownloader.downloading ? "downloading" : "hourglass_empty"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        visible: root.videoFileSize > 0 && universalVideoDownloader.downloading
                        text: root.videoDownloadProgress + "%"
                        color: "#ffffff"
                        font.pixelSize: 12
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Progress bar at bottom
                Rectangle {
                    visible: root.videoFileSize > 0
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.margins: 3
                    width: (parent.width - 6) * (root.videoDownloadProgress / 100)
                    height: 3
                    radius: 1.5
                    color: "#4CAF50"
                }
            }

            // Video download error indicator
            Rectangle {
                anchors.centerIn: parent
                width: 40
                height: 40
                radius: 20
                color: Qt.rgba(200, 50, 50, 0.8)
                visible: root.isVideo && root.videoDownloadFailed

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 24
                    color: "#ffffff"
                    text: "error"
                }

                // Tap to retry
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.videoDownloadFailed = false
                        universalVideoDownloader.retryCount = 0
                        universalVideoDownloader.command = universalVideoDownloader.buildCommand()
                        universalVideoDownloader.running = true
                    }
                }
            }
        }

        // Ugoira download indicator (shown while downloading pre-converted WebM)
        Rectangle {
            anchors.fill: parent
            radius: imageRadius
            color: Appearance.colors.colLayer2
            visible: root.isArchive && root.localUgoiraSource === "" && root.ugoiraDownloading

            Column {
                anchors.centerIn: parent
                spacing: 8

                // Spinner animation
                MaterialSymbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    iconSize: 24
                    color: Appearance.m3colors.m3surfaceText
                    text: "sync"

                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                        running: root.ugoiraDownloading
                    }
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Downloading..."
                    font.pixelSize: Appearance.font.pixelSize.textSmall
                    color: Appearance.m3colors.m3secondaryText
                }
            }
        }

        // Loading indicator (static images - shows while preview loads)
        Rectangle {
            anchors.fill: parent
            radius: imageRadius
            color: Appearance.colors.colLayer2
            // Show only for static images while loading
            visible: root.isStaticImage && previewImage.status !== Image.Ready && highResImage.status !== Image.Ready

            StyledText {
                anchors.centerIn: parent
                text: "..."
                color: Appearance.m3colors.m3secondaryText
            }
        }

        // Loading indicator (GIFs - when both preview and GIF are loading)
        Rectangle {
            anchors.fill: parent
            radius: imageRadius
            color: Appearance.colors.colLayer2
            visible: {
                if (!root.isGif) return false
                if (root.manualDownload) {
                    // Show while downloading (localGifSource empty) or loading
                    return root.localGifSource === "" || gifObject.status !== AnimatedImage.Ready
                }
                return gifPreview.status !== Image.Ready && gifObject.status !== AnimatedImage.Ready
            }

            StyledText {
                anchors.centerIn: parent
                text: "GIF..."
                color: Appearance.m3colors.m3secondaryText
            }
        }

        // Menu button
        RippleButton {
            id: menuButton
            anchors.top: parent.top
            anchors.right: parent.right
            property real buttonSize: 28
            anchors.margins: 6
            implicitHeight: buttonSize
            implicitWidth: buttonSize
            buttonRadius: Appearance.rounding.full
            colBackground: Qt.rgba(0, 0, 0, 0.4)
            colBackgroundHover: Qt.rgba(0, 0, 0, 0.6)

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                iconSize: 18
                color: "#ffffff"
                text: "more_vert"
            }

            onClicked: root.showActions = !root.showActions
        }

        // Download status badges (bottom-right corner) - extracted to ImageStatusBadges.qml
        ImageStatusBadges {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 6
            z: ZOrder.indicator
            isSavedLocally: root.isSavedLocally
            isSavedAsWallpaper: root.isSavedAsWallpaper
        }

        // Context menu popup - extracted to ImageContextMenu.qml
        ImageContextMenu {
            id: contextMenuPopup
            visible: root.showActions
            imageData: root.imageData
            fileName: root.fileName
            provider: root.provider
            isVideo: root.isVideo
            useGrabber: root.useGrabber
            downloadPath: root.downloadPath
            nsfwPath: root.nsfwPath
            grabberDownloader: grabberDownloader
            wallpaperDownloader: wallpaperDownloader
            menuButton: menuButton

            onDownloadStarted: root.isSavedLocally = true
            onWallpaperStarted: root.isSavedAsWallpaper = true
            onMenuClosed: root.showActions = false
        }

    }

    // Track if this image's preview is currently shown
    property bool isPreviewActive: false

    onClicked: {
        if (!showActions) {
            // Toggle preview - close if this image is already being previewed
            if (root.isPreviewActive) {
                root.hidePreview()
            } else {
                var cachedSrc = ""
                if (root.isVideo || root.isArchive) {
                    // For videos/ugoira, prefer the actual playing source if it's local
                    // This handles cases where video was downloaded after CacheIndex initialized
                    var videoSrc = videoContainer.videoSource
                    if (videoSrc && videoSrc.indexOf("file://") === 0) {
                        cachedSrc = videoSrc
                    } else if (root.cachedVideoSource) {
                        cachedSrc = root.cachedVideoSource
                    }
                } else if (root.isGif) {
                    // For GIFs, prefer the actual source if it's local
                    var gifSrc = gifObject.source.toString()
                    if (gifSrc && gifSrc.indexOf("file://") === 0) {
                        cachedSrc = gifSrc
                    } else if (root.cachedGifSource) {
                        cachedSrc = root.cachedGifSource
                    } else if (root.cachedImageSource && root.cachedImageSource.toLowerCase().endsWith(".gif")) {
                        // Zerochan GIFs found via extension variant lookup with hires_ prefix
                        cachedSrc = root.cachedImageSource
                    }
                } else if (root.cachedImageSource) {
                    cachedSrc = root.cachedImageSource
                } else if (root.localHighResSource) {
                    cachedSrc = root.localHighResSource
                }
                root.showPreview(root.imageData, cachedSrc, root.manualDownload, root.provider)
            }
        }
    }

    // Debug: Log image data when component is created (only first visible for performance)
    Component.onCompleted: {
        // Only log if this is likely to be visible (first few items)
        if (root.imageData && root.visible) {
            Services.Logger.info("BooruImage", `Loaded id=${root.imageData.id} provider=${root.provider} ${root.imageData.width}x${root.imageData.height}`)
        }
    }
}
