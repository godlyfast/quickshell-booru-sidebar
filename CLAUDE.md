# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Quickshell Booru Sidebar is a Wayland desktop widget built with [Quickshell](https://quickshell.outfoxxed.me/) for Hyprland. It provides a sidebar interface for browsing anime images from various booru APIs.

## Commands

### Run the Sidebar
```bash
qs -c booru-sidebar            # If symlinked to ~/.config/quickshell/booru-sidebar
qs --path .                    # From repo root
```

### Toggle via IPC
```bash
qs -c booru-sidebar msg sidebarLeft toggle
qs -c booru-sidebar msg sidebarLeft open
qs -c booru-sidebar msg sidebarLeft close
```

### Run Provider Integration Tests
```bash
qs --path tests                # From repo root
timeout 120 qs --path tests    # With timeout (tests take ~60-90s)
```

### Deploy for Development
```bash
./deploy.sh                    # Stop, copy to ~/.config/quickshell/booru-sidebar/, restart
```
Deploys repo files to the quickshell config directory. Preserves user's config.json.

## Supported Providers

| Provider | Key | API Type | Sorting | Notes |
|----------|-----|----------|---------|-------|
| **Moebooru** |||||
| yande.re | `yandere` | Moebooru | `order:X` | Default provider |
| Konachan | `konachan` | Moebooru | `order:X` | Has .net (SFW) and .com (NSFW) mirrors |
| Sakugabooru | `sakugabooru` | Moebooru | `order:X` | Animation sakuga clips |
| 3Dbooru | `3dbooru` | Moebooru | `order:X` | 3D renders, connection issues |
| **Danbooru** |||||
| Danbooru | `danbooru` | Danbooru | `order:X` | Strict Cloudflare, uses Grabber |
| AIBooru | `aibooru` | Danbooru | `order:X` | AI-generated art |
| **Gelbooru** |||||
| Gelbooru | `gelbooru` | Gelbooru | `sort:X` | Requires API key |
| Safebooru | `safebooru` | Gelbooru | `sort:X` | SFW-only |
| Rule34 | `rule34` | Gelbooru | `sort:X` | NSFW-only, requires API key |
| Xbooru | `xbooru` | Gelbooru | `sort:X` | NSFW focused |
| TBIB | `tbib` | Gelbooru | `sort:X` | 8M+ images aggregator |
| Hypnohub | `hypnohub` | Gelbooru | `sort:X` | Niche themed, returns XML |
| **e621** |||||
| e621 | `e621` | e621 | `order:X` | Furry, has e926.net SFW mirror |
| **Philomena** |||||
| Derpibooru | `derpibooru` | Philomena | `sf=X` param | MLP content |
| **Sankaku** |||||
| Sankaku | `sankaku` | Sankaku | `order:X` | API requires auth (blocked) |
| Idol Sankaku | `idol_sankaku` | Sankaku | `order:X` | Japanese idols (blocked) |
| **Other** |||||
| Wallhaven | `wallhaven` | REST | `sorting=X` param | Desktop wallpapers, 4K+ filter |
| Zerochan | `zerochan` | REST | `s=X` param | High-quality art, API blocked |
| waifu.im | `waifu.im` | REST | None | Limited tag set |
| nekos.best | `nekos_best` | REST | None | Random images only |
| Paheal | `paheal` | Shimmie | None | Rule34 Shimmie |
| **Grabber-only** |||||
| Anime-Pictures | `anime_pictures` | Grabber | N/A | Quality curated art |
| E-Shuushuu | `e_shuushuu` | Grabber | N/A | SFW cute art |

**SFW-only providers** (NSFW toggle hidden): `safebooru`, `nekos_best`, `zerochan`
**NSFW-only providers**: `rule34`, `xbooru`, `tbib`, `paheal`, `hypnohub`
**Mirror providers**: `e621` has e926.net (SFW), `konachan` has .com (NSFW) and .net (SFW)

## Architecture

### Entry Points
- `shell.qml` - Main entry point, instantiates ConfigLoader and SidebarLeft
- `tests/shell.qml` - Test runner entry point

### Core Services (`services/`)

**Booru.qml** - Singleton API service with:

Key Methods:
- `setProvider(provider)` - Switch active provider (validates, warns if API key missing)
- `makeRequest(tags, nsfw, limit, page)` - Execute image search
- `triggerTagSearch(query)` - Trigger tag autocomplete
- `getSortOptions()` - Get sort options for current provider
- `constructRequestUrl(tags, nsfw, limit, page)` - Build provider-specific URL
- `clearResponses()` - Clear all results
- `addSystemMessage(message)` - Add system message to results

Key Properties:
- `currentProvider` - Active provider key (default: "yandere")
- `allowNsfw` - NSFW filter toggle
- `currentSorting` - Active sort method (empty = provider default)
- `limit` - Results per page (default: 20)
- `runningRequests` - Count of pending requests
- `responses` - Array of BooruResponseData objects
- `providerList` - Array of valid provider keys
- `providerSupportsNsfw` / `providerSupportsSorting` - UI state booleans

Signals:
- `tagSuggestion(query, suggestions)` - Emitted when autocomplete completes
- `responseFinished()` - Emitted when API response processed

**BooruResponseData.qml** - Response data model:
```javascript
{
    provider: "provider_key",
    tags: ["tag1", "tag2"],
    page: 1,
    images: [ /* normalized image objects */ ],
    message: "optional system message"
}
```

**ConfigLoader.qml** - Loads `config.json`, watches for changes, applies settings

### UI Components (`modules/`)

**sidebar/SidebarLeft.qml** - PanelWindow with layer shell integration:
- `HyprlandFocusGrab` for click-outside-to-close
- Pin button disables focus grab (for screenshots)
- `GlobalShortcut` named "sidebarLeftToggle"

**sidebar/Anime.qml** - Browser interface handling commands:
- `/mode <provider>` - Switch provider
- `/sort <option>` - Set sorting (or show current)
- `/clear` - Clear results
- `/next` or `+` - Load next page
- `/safe` / `/lewd` - Toggle NSFW

**sidebar/anime/BooruImage.qml** - Image card with:
- Static images, GIFs (`AnimatedImage`), videos (`MediaPlayer`)
- Context menu: open link, download, save as wallpaper, go to source
- `ImageDownloaderProcess` for providers blocking direct requests

### Reusable Widgets (`modules/common/widgets/`)

- `RippleButton` - Material ripple button with toggle state, multiple click actions
- `StyledSwitch` - Animated toggle switch
- `StyledText` - Text with appearance integration
- `StyledTextArea` - Text input field
- `StyledToolTip` - Animated tooltip with visibility conditions
- `MaterialSymbol` - Icon widget mapping names to Unicode codepoints
- `StyledImage` - Async image with fallback source

### Styling (`modules/common/`)

**Appearance.qml** - Singleton with Material 3 / Catppuccin colors, animations, fonts
**ConfigOptions.qml** - Runtime configuration state
**Directories.qml** - XDG path resolution

### Utility Functions (`modules/common/functions/`)

- `color_utils.js` - `mix()`, `transparentize()`, HSV/HSL blending
- `object_utils.js` - `applyToQtObject()`, `toPlainObject()` for config
- `file_utils.js` - `trimFileProtocol()` removes `file://` prefix
- `fuzzysort.js` - Fuzzy search sorting library
- `levendist.js` - Levenshtein distance for autocomplete

### API Family System (`services/BooruApiTypes.js`)

Shared mapper functions by API family to eliminate code duplication. Providers reference their family via `apiType` property.

| Family | Providers | Description |
|--------|-----------|-------------|
| `moebooru` | yandere, konachan, sakugabooru, 3dbooru | Moebooru-based APIs |
| `danbooru` | danbooru, aibooru | Danbooru-based APIs |
| `gelbooru` | gelbooru, safebooru | Gelbooru 0.2 APIs |
| `gelbooruNsfw` | rule34, xbooru, hypnohub | Gelbooru 0.2 NSFW sites |
| `e621` | e621 (with e926 mirror) | e621 API |
| `philomena` | derpibooru | Philomena engine |
| `sankaku` | sankaku, idol_sankaku | Sankaku API |
| `shimmie` | paheal | Shimmie XML API |
| `wallhaven` | wallhaven | Wallhaven REST API |
| `waifuIm` | waifu.im | waifu.im REST API |
| `nekosBest` | nekos_best | nekos.best REST API |
| `zerochan` | zerochan | Zerochan REST API |

**Usage:**
```javascript
// Provider config
"yandere": {
    name: "yande.re",
    url: "https://yande.re",
    api: "https://yande.re/post.json",
    apiType: "moebooru",  // References shared mapper
    tagSearchTemplate: "https://yande.re/tag.json?order=count&limit=10&name={{query}}*"
}

// Getting mapper function
var mapFunc = Booru.getProviderMapFunc("yandere")
var images = mapFunc(response, provider)
```

## QML Patterns

### Pragma Directives
```qml
pragma Singleton              // Declare singleton (use with Singleton {} root)
pragma ComponentBehavior: Bound  // Enable automatic property binding

//@ pragma UseQApplication    // Required for Qt Quick Controls (shell.qml only)
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic  // Environment injection
```

### ES5 JavaScript Constraint

QML uses V4 engine which **does not support ES6+**. All JavaScript must be ES5:

```javascript
// WRONG - ES6+ syntax will fail
const x = item?.property ?? "default"
const arr = [...items]
const str = `template ${value}`
items.map(i => i.name)

// CORRECT - ES5 syntax
var x = (item && item.property) ? item.property : "default"
var arr = items.slice()
var str = "template " + value
items.map(function(i) { return i.name })
```

**Files requiring ES5**: All `.js` files in `modules/common/functions/` and inline JavaScript in QML files.

### Security: Shell Command Escaping

When executing shell commands with user-provided data (URLs, paths), use `shellEscape()`:

```javascript
// BooruImage.qml - prevents command injection
function shellEscape(str) {
    if (!str) return ""
    return str.replace(/'/g, "'\\''")
}

// Usage in Process commands
command: ["bash", "-c", "curl -sL '" + shellEscape(url) + "' -o '" + shellEscape(path) + "'"]
```

**Protected locations**: Download commands, ugoira converter, image fallback downloads.

### API Resilience

**XHR Request Management** (`Booru.qml`):
- `pendingXhrRequests: []` - Tracks all active XHR objects
- `clearResponses()` - Aborts all pending requests before clearing
- Prevents stale responses from updating UI after user clears

**Response Limiting**:
- `maxResponses: 50` - Caps stored responses to prevent memory bloat
- Oldest responses evicted first when limit exceeded
- ~1000 images max in memory (50 responses × 20 images)

**Provider MapFunc Safety**:
All provider `mapFunc` and `tagMapFunc` include null checks:
```javascript
mapFunc: function(response) {
    if (!response || !Array.isArray(response)) return []
    // ... safe iteration
}
```

### Normalized Image Object

All provider `mapFunc` results use this schema:
```javascript
{
    id,              // Post ID
    width, height,   // Dimensions
    aspect_ratio,    // width / height
    tags,            // Space-separated string
    rating,          // "s" (safe), "q" (questionable), "e" (explicit)
    is_nsfw,         // boolean
    md5,             // Hash for caching/identification
    preview_url,     // Thumbnail URL
    sample_url,      // Medium resolution
    file_url,        // Full resolution
    file_ext,        // File extension
    source           // Original source (Pixiv, Twitter, etc.)
}
```

## Media Type Handling

**Static Images**: Direct `Image` component with `preview_url`
**GIFs**: `AnimatedImage` with `cache: true` (required for network looping per Qt docs)
**Videos**: `MediaPlayer` + `VideoOutput` with `loops: MediaPlayer.Infinite`

Some providers (e621, e926) require `ImageDownloaderProcess` to curl images with User-Agent.

## Universal Cache-First Loading

All providers use cache-first loading for images, GIFs, and videos. This reduces bandwidth and provides instant display for previously-viewed content.

### Cache Locations (Priority Order)

| Location | Path | Contents |
|----------|------|----------|
| Hi-res cache | `~/.cache/quickshell/booru/previews/hires_*` | Cached full-resolution images |
| Preview cache | `~/.cache/quickshell/booru/previews/<filename>` | Preview images (full-res for Sankaku) |
| Download folder | `~/Pictures/booru/<filename>` | User downloads |
| NSFW folder | `~/Pictures/booru/nsfw/<filename>` | NSFW user downloads |
| Wallpapers | `~/Pictures/wallpapers/<filename>` | Saved wallpapers |

### Sankaku Optimization

Sankaku uses the same URL for both preview and hi-res (`preview_url === file_url`). To avoid downloading the same file twice:
- `previewIsFullRes` property detects when URLs match
- Single download serves both preview and hi-res display
- Cache check includes preview path for these providers

### How It Works

1. **Cache check**: On image load, check all cache locations for existing file
2. **Display from cache**: If found, load from local file immediately
3. **Download to cache**: If not found, download from network and save to cache
4. **Subsequent views**: Future views load instantly from cache

### Implementation (`BooruImage.qml`)

**Properties**:
- `universalCacheChecked` / `gifCacheChecked` / `videoCacheChecked` - Cache check completed flags
- `cachedImageSource` / `cachedGifSource` / `cachedVideoSource` - Local file paths (file://)

**Processes**:
- `universalCacheCheck` - Checks all cache locations for static images
- `gifCacheCheck` - Checks cache locations for GIFs
- `videoCacheCheck` - Checks cache locations for videos

**Downloaders**:
- `universalHighResDownloader` - Downloads hi-res to cache (non-manual providers)
- `universalGifDownloader` - Downloads GIFs to cache
- `universalVideoDownloader` - Downloads videos to cache

### Source Binding Pattern

All image source bindings follow this priority:
```qml
source: {
    // 1. Universal cache (any provider)
    if (root.cachedImageSource.length > 0) return root.cachedImageSource
    // 2. Manual download path (Cloudflare-blocked providers)
    if (root.manualDownload) return root.localHighResSource
    // 3. Wait for cache check before network
    if (!root.universalCacheChecked) return ""
    // 4. Network fallback
    return modelData.file_url
}
```

### Benefits

- **View → scroll → view again**: Instant from cache
- **Download → restart app**: Loads from local file
- **Reduced bandwidth**: No re-downloading previously viewed images
- **Works with all providers**: Not just Cloudflare-blocked ones

## Configuration

`config.json` structure:
```json
{
  "booru": {
    "defaultProvider": "yandere",
    "nsfw": false,
    "downloadPath": "~/Pictures/booru",
    "nsfwPath": "~/Pictures/booru/nsfw",
    "filenameTemplate": "%website% %id% - %artist%.%ext%",
    "gelbooruApiKey": "",
    "gelbooruUserId": "",
    "rule34ApiKey": "",
    "rule34UserId": "",
    "wallhavenApiKey": ""
  },
  "appearance": {
    "transparency": 0.5,
    "sidebarWidth": 420
  },
  "font": {
    "family": {
      "uiFont": "Noto Sans",
      "iconFont": "Material Symbols Rounded",
      "codeFont": "JetBrainsMono Nerd Font Mono"
    },
    "pixelSize": {
      "textSmall": 13,
      "textBase": 15,
      "textMedium": 16,
      "textLarge": 19
    }
  }
}
```

API keys: Gelbooru at `gelbooru.com/index.php?page=account&s=options`, Rule34 at `rule34.xxx/index.php?page=account&s=options`, Wallhaven at `wallhaven.cc/settings/account` (required for NSFW content)

## Testing

`tests/ProviderTests.qml` validates:
- All required image fields present and valid
- Provider `mapFunc` correctness
- URL validity (must start with `http`)
- Tag autocomplete functionality
- Sorting configuration per provider
- Edge cases: null URL fallbacks (`solo` tag on e621/e926)
- Cloudflare bypass requirements (curl with User-Agent for e621/e926)

Providers skipped in tests: `danbooru` (strict Cloudflare JS challenge)

## Provider-Specific Notes

- **Danbooru**: Uses Grabber fallback by default (Cloudflare bypass)
- **e621/e926**: Require User-Agent header; `solo` tag often has null `sample_url`
- **Wallhaven**: Has separate `order` param (asc/desc) in addition to `sorting`
- **waifu.im**: Tags returned as objects; only supports specific tag names
- **nekos_best**: Random images only, ignores search tags

## Sorting Options

Each provider has API-specific sort options. Use `/sort <option>` command.

### Sort Options by API Type

| API Type | Providers | Sort Options |
|----------|-----------|--------------|
| **Moebooru** | yandere, konachan | `score`, `score_asc`, `favcount`, `random`, `rank`, `id`, `id_desc`, `change`, `comment`, `mpixels`, `landscape`, `portrait` |
| **Danbooru** | danbooru, aibooru | `rank`, `score`, `favcount`, `random`, `id`, `id_desc`, `change`, `comment`, `comment_bumped`, `note`, `mpixels`, `landscape`, `portrait` |
| **e621** | e621, e926 | `score`, `favcount`, `random`, `id`, `id_asc`, `comment_count`, `tagcount`, `mpixels`, `filesize`, `landscape`, `portrait` |
| **Gelbooru** | gelbooru, safebooru, rule34, xbooru | `score`, `score:asc`, `score:desc`, `id`, `id:asc`, `updated`, `random` |
| **Gelbooru** | tbib, hypnohub | `score`, `score:asc`, `score:desc`, `id`, `id:asc`, `updated` |
| **Wallhaven** | wallhaven | `toplist`, `random`, `date_added`, `relevance`, `views`, `favorites`, `hot` |
| **Sankaku** | sankaku, idol_sankaku | `popularity`, `date`, `quality`, `score`, `favcount`, `random`, `id`, `id_asc`, `recently_favorited`, `recently_voted` |
| **None** | waifu.im, nekos_best, paheal | No sorting support |

### Age Filter

Providers supporting the `age:` metatag show an age chip in the UI. This prevents search timeouts when sorting by score/favcount on large datasets.

**Supported providers**: `danbooru`, `aibooru`, `yandere`, `konachan`

**Options**: `1d`, `1w`, `1M`, `3M`, `1y`, `All`

**Properties** (`Booru.qml`):
- `ageFilter` - Current age filter value (default: "1month")
- `ageFilterProviders` - Array of providers supporting age filter
- `providerSupportsAgeFilter` - Boolean for UI binding

## imgbrd-grabber Integration

The sidebar integrates with [imgbrd-grabber](https://github.com/Bionus/imgbrd-grabber) for enhanced downloads and Cloudflare bypass.

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `GrabberDownloader` | `modules/common/utils/` | Downloads with filename templates |
| `GrabberRequest` | `modules/common/utils/` | Search API fallback |

### Grabber-Enabled Features

**Downloads** (Phase 1):
- Artist-aware filenames: `%website% %id% - %artist%.%ext%`
- Token support: `%md5%`, `%copyright%`, `%character%`
- Automatic duplicate detection with `-n` flag
- Fallback to curl if Grabber fails or provider unsupported

**Search Fallback** (Phase 2):
- Danbooru uses Grabber by default (`useGrabberFallback: true`)
- Bypasses strict Cloudflare JS challenges
- Returns richer metadata (separated tag categories)

### Configuration

```json
"booru": {
    "filenameTemplate": "%website% %id% - %artist%.%ext%"
}
```

### Grabber Source Mapping

```javascript
// services/Booru.qml - grabberSources
{
    "yandere": "yande.re",
    "konachan": "konachan.com",
    "danbooru": "danbooru.donmai.us",
    "gelbooru": "gelbooru.com",
    "e621": "e621.net",
    "wallhaven": "wallhaven.cc"
    // waifu.im, nekos_best, tbib, paheal not supported
}
```

### CLI Reference

```bash
# Search with JSON output
/usr/bin/Grabber -c -s "yande.re" -t "landscape" -m 20 -j --ri --load-details

# Download with template
/usr/bin/Grabber -c -s "yande.re" -t "id:1249799" -m 1 --download \
  -l "/path/to/folder" -f "%website% %id% - %artist%.%ext%"
```
