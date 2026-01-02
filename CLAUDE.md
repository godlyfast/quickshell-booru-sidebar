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

## Supported Providers

| Provider | Key | API Type | Sorting | Notes |
|----------|-----|----------|---------|-------|
| yande.re | `yandere` | Moebooru | `order:X` | Default provider |
| Konachan.net | `konachan` | Moebooru | `order:X` | SFW-only |
| Konachan.com | `konachan_com` | Moebooru | `order:X` | More NSFW than .net |
| Danbooru | `danbooru` | Danbooru | `order:X` | Strict Cloudflare |
| Gelbooru | `gelbooru` | Gelbooru | `sort:X` | Requires API key |
| Safebooru | `safebooru` | Gelbooru | `sort:X` | SFW-only |
| Rule34 | `rule34` | Gelbooru | `sort:X` | NSFW-only, requires API key |
| e621 | `e621` | e621 | `order:X` | Furry, requires User-Agent |
| e926 | `e926` | e621 | `order:X` | SFW furry, requires User-Agent |
| Wallhaven | `wallhaven` | REST | `sorting=X` param | Desktop wallpapers, 4K+ filter |
| waifu.im | `waifu.im` | REST | None | Limited tag set |
| nekos.best | `nekos_best` | REST | None | Random images only |

**SFW-only providers** (NSFW toggle hidden): `safebooru`, `e926`, `nekos_best`, `konachan`
**NSFW-only providers**: `rule34`

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

// CORRECT - ES5 syntax
var x = (item && item.property) ? item.property : "default"
var arr = items.slice()
var str = "template " + value
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

## Configuration

`config.json` structure:
```json
{
  "booru": {
    "defaultProvider": "yandere",
    "nsfw": false,
    "downloadPath": "~/Pictures/booru",
    "nsfwPath": "~/Pictures/booru/nsfw",
    "gelbooruApiKey": "",
    "gelbooruUserId": "",
    "rule34ApiKey": "",
    "rule34UserId": ""
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

API keys: Gelbooru at `gelbooru.com/index.php?page=account&s=options`, Rule34 at `rule34.xxx/index.php?page=account&s=options`

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

- **Danbooru**: Strict Cloudflare protection, often fails automated tests
- **e621/e926**: Require User-Agent header; `solo` tag often has null `sample_url`
- **Wallhaven**: Has separate `order` param (asc/desc) in addition to `sorting`
- **waifu.im**: Tags returned as objects; only supports specific tag names
- **nekos_best**: Random images only, ignores search tags
