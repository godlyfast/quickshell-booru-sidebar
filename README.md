# Quickshell Booru Sidebar

A beautiful anime image browser sidebar for [Quickshell](https://quickshell.outfoxxed.me/) on Hyprland. Browse images from multiple booru sources directly from your desktop.

![Booru Sidebar](https://img.shields.io/badge/Quickshell-0.2.1+-blue) ![Hyprland](https://img.shields.io/badge/Hyprland-Required-green)

## Features

- **23 Booru Sources**: yande.re, Danbooru, Gelbooru, e621, Wallhaven, Derpibooru, Sakugabooru, and more
- **Animated Media**: GIFs, videos, and ugoira (Pixiv ZIP animations) play automatically
- **Smart Downloads**: Filename templates with artist/character metadata via imgbrd-grabber
- **Intelligent Caching**: Cache-first loading for all providers - instant display of previously-viewed images
- **4K+ Wallpapers**: Wallhaven filtering by resolution (3840x2160+) and toplist periods
- **Tag Autocomplete**: Fuzzy search with provider-specific suggestions
- **NSFW Filtering**: Per-provider toggle with SFW-only options
- **Sorting Options**: Score, date, favorites, random (provider-dependent)
- **Material Design**: Material 3 inspired UI with Catppuccin colors
- **IPC Control**: Keybind integration via Quickshell messaging

## Requirements

- [Quickshell](https://quickshell.outfoxxed.me/) 0.2.1+
- [Hyprland](https://hyprland.org/) (for focus grab and layer shell)
- `ttf-material-symbols-variable` font (for icons)
- `curl` (for image downloads)

### Optional Dependencies

- [imgbrd-grabber](https://github.com/Bionus/imgbrd-grabber) - Enhanced downloads with artist-aware filenames and Cloudflare bypass
- `ffmpeg` + `unzip` - Required for ugoira (animated ZIP) playback

#### Why imgbrd-grabber?

imgbrd-grabber is a powerful booru downloader that provides:
- **Smart Filenames**: Include artist, character, copyright in filenames (e.g., `yande.re 1249799 - kantoku.jpg`)
- **Cloudflare Bypass**: Works with sites that block direct API access (Danbooru)
- **Duplicate Detection**: Automatically skips already-downloaded images
- **Rich Metadata**: Access to tag categories (artist, character, copyright) not available in raw APIs

Without imgbrd-grabber, downloads use generic filenames based on the image ID only.

### Install Dependencies (Arch Linux)

```bash
# Core dependencies
yay -S quickshell-git
sudo pacman -S ttf-material-symbols-variable curl

# Optional: for ugoira support
sudo pacman -S ffmpeg unzip

# Optional: for enhanced downloads
yay -S imgbrd-grabber
```

## Installation

### Option 1: Clone to Quickshell Config

```bash
git clone https://github.com/godlyfast/quickshell-booru-sidebar.git ~/.config/quickshell/booru-sidebar
```

### Option 2: Clone Anywhere and Symlink

```bash
git clone https://github.com/godlyfast/quickshell-booru-sidebar.git ~/quickshell-booru-sidebar
ln -s ~/quickshell-booru-sidebar ~/.config/quickshell/booru-sidebar
```

## Usage

### Start the Sidebar

```bash
# If installed in quickshell config directory
qs -c booru-sidebar

# If installed elsewhere
qs --path /path/to/quickshell-booru-sidebar
```

### Toggle Sidebar

Via IPC (for keybinds):
```bash
qs -c booru-sidebar msg sidebarLeft toggle
```

### Hyprland Keybind

Add to your `~/.config/hypr/hyprland.conf` or keybinds file:

```conf
# Toggle Booru Sidebar with SUPER + SHIFT + B
bind = $mainMod SHIFT, B, exec, ~/.config/hypr/scripts/BooruSidebarToggle.sh
```

Create the toggle script `~/.config/hypr/scripts/BooruSidebarToggle.sh`:

```bash
#!/usr/bin/env bash
CONFIG_NAME="booru-sidebar"

if pgrep -f "qs.*${CONFIG_NAME}" > /dev/null; then
    qs -c "$CONFIG_NAME" msg sidebarLeft toggle
else
    qs -c "$CONFIG_NAME" &
    sleep 0.3
    qs -c "$CONFIG_NAME" msg sidebarLeft open
fi
```

Make it executable:
```bash
chmod +x ~/.config/hypr/scripts/BooruSidebarToggle.sh
```

### Autostart

To start the sidebar with Hyprland, add to your startup config:

```conf
exec-once = qs -c booru-sidebar -d
```

## Commands

Type these in the search bar:

| Command | Description |
|---------|-------------|
| `/mode <provider>` | Switch provider (e.g., `/mode danbooru`) |
| `/mirror <name>` | Switch provider mirror (e.g., `/mirror konachan.com`) |
| `/sort <option>` | Set sorting (e.g., `/sort score`, `/sort random`) |
| `/res <resolution>` | Wallhaven resolution filter (e.g., `/res 3840x2160`) |
| `/safe` | Disable NSFW content |
| `/lewd` | Enable NSFW content |
| `/clear` | Clear image list |
| `/next` or `+` | Load next page |

## Sorting Options

Each provider supports different sort options. Use `/sort <option>` or click the sort chip.

| Provider Type | Sort Options |
|---------------|--------------|
| **Moebooru** (yandere, konachan, sakugabooru, 3dbooru) | `score`, `score_asc`, `favcount`, `random`, `rank`, `id`, `id_desc`, `change`, `comment`, `mpixels`, `landscape`, `portrait` |
| **Danbooru** (danbooru, aibooru) | `rank`, `score`, `favcount`, `random`, `id`, `id_desc`, `change`, `comment`, `note`, `mpixels`, `landscape`, `portrait` |
| **e621** | `score`, `favcount`, `random`, `id`, `id_asc`, `comment_count`, `tagcount`, `mpixels`, `filesize`, `landscape`, `portrait` |
| **Gelbooru** (gelbooru, safebooru, rule34, xbooru) | `score`, `score:asc`, `score:desc`, `id`, `id:asc`, `updated`, `random` |
| **Wallhaven** | `toplist`, `random`, `date_added`, `relevance`, `views`, `favorites`, `hot` |
| **Derpibooru** | `score`, `wilson_score`, `relevance`, `random`, `created_at`, `updated_at`, `width`, `height` |

### Age Filter

For providers with large datasets, an age filter prevents search timeouts when sorting by score or favorites.

- **Providers**: yandere, konachan, sakugabooru, 3dbooru, danbooru, aibooru
- **Options**: 1d, 1w, 1M, 3M, 1y, All (click the clock chip to cycle)

## Supported Providers

### Main Providers

| Provider | Key | API Type | NSFW | Auth Required |
|----------|-----|----------|------|---------------|
| yande.re | `yandere` | Moebooru | Yes | No |
| Konachan | `konachan` | Moebooru | Mirror | No |
| Danbooru | `danbooru` | Danbooru | Yes | No |
| Gelbooru | `gelbooru` | Gelbooru | Yes | **Yes** |
| Safebooru | `safebooru` | Gelbooru | SFW only | No |
| Rule34 | `rule34` | Gelbooru | NSFW only | **Yes** |
| e621 | `e621` | e621 | Mirror | No |
| Wallhaven | `wallhaven` | REST | Yes* | Optional |
| waifu.im | `waifu.im` | REST | Yes | No |
| nekos.best | `nekos_best` | REST | SFW only | No |
| AIBooru | `aibooru` | Danbooru | Yes | No |
| Derpibooru | `derpibooru` | Philomena | Yes | No |
| Sakugabooru | `sakugabooru` | Moebooru | Yes | No |

*Wallhaven NSFW requires API key

### Mirror Providers

| Provider | Mirrors | Description |
|----------|---------|-------------|
| konachan | `.net` (SFW), `.com` (NSFW) | Use `/mirror konachan.com` to switch |
| e621 | `e621.net` (NSFW), `e926.net` (SFW) | Use `/mirror e926.net` to switch |
| danbooru | `danbooru.donmai.us`, `safebooru.donmai.us` (SFW) | Use `/mirror` to switch |

### Additional Providers

| Provider | Key | Notes |
|----------|-----|-------|
| 3Dbooru | `3dbooru` | 3D renders (connection issues) |
| Xbooru | `xbooru` | NSFW focused |
| TBIB | `tbib` | 8M+ images aggregator |
| Paheal | `paheal` | Rule34 Shimmie |
| Hypnohub | `hypnohub` | Niche themed (returns XML) |
| Zerochan | `zerochan` | High-quality art (API blocked) |
| Sankaku | `sankaku` | Anime art (API requires auth) |
| Idol Sankaku | `idol_sankaku` | Japanese idols (API requires auth) |

### Grabber-only Providers

These providers use imgbrd-grabber for all requests (no direct API):

| Provider | Key | Notes |
|----------|-----|-------|
| Anime-Pictures | `anime_pictures` | Quality curated art |
| E-Shuushuu | `e_shuushuu` | SFW cute art |

## Configuration

Edit `config.json` to customize:

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
      "uiFont": "Open Sans",
      "iconFont": "Material Symbols Rounded",
      "codeFont": "JetBrains Mono NF"
    }
  }
}
```

### Filename Template Tokens (imgbrd-grabber)

These tokens are available when [imgbrd-grabber](https://github.com/Bionus/imgbrd-grabber) is installed. Configure via `filenameTemplate` in config.json:

| Token | Description |
|-------|-------------|
| `%website%` | Source site name |
| `%id%` | Post ID |
| `%artist%` | Artist name(s) |
| `%copyright%` | Series/copyright |
| `%character%` | Character name(s) |
| `%md5%` | File hash |
| `%ext%` | File extension |

Example: `%website% %id% - %artist%.%ext%` → `yande.re 1249799 - kantoku.jpg`

See [imgbrd-grabber documentation](https://bionus.github.io/imgbrd-grabber/docs/filename.html) for the full list of available tokens.

## API Keys

### Gelbooru

1. Create an account at [gelbooru.com](https://gelbooru.com)
2. Go to [Account Options](https://gelbooru.com/index.php?page=account&s=options)
3. Copy your **API Key** and **User ID**
4. Add to `config.json`:

```json
"gelbooruApiKey": "your_api_key",
"gelbooruUserId": "your_user_id"
```

### Rule34

1. Create an account at [rule34.xxx](https://rule34.xxx)
2. Go to [Account Options](https://rule34.xxx/index.php?page=account&s=options)
3. Copy your **API Key** and **User ID**
4. Add to `config.json`:

```json
"rule34ApiKey": "your_api_key",
"rule34UserId": "your_user_id"
```

### Wallhaven (for NSFW)

1. Create an account at [wallhaven.cc](https://wallhaven.cc)
2. Go to [Settings > Account](https://wallhaven.cc/settings/account)
3. Copy your **API Key**
4. Add to `config.json`:

```json
"wallhavenApiKey": "your_api_key"
```

## IPC Commands

```bash
# Toggle visibility
qs -c booru-sidebar msg sidebarLeft toggle

# Open sidebar
qs -c booru-sidebar msg sidebarLeft open

# Close sidebar
qs -c booru-sidebar msg sidebarLeft close
```

## Caching

All images, GIFs, and videos are cached locally for instant subsequent viewing. The cache system checks multiple locations in priority order:

1. **Hi-res cache**: `~/.cache/quickshell/booru/previews/hires_*`
2. **Download folder**: `~/Pictures/booru/`
3. **NSFW folder**: `~/Pictures/booru/nsfw/`
4. **Wallpapers**: `~/Pictures/wallpapers/`

**Benefits:**
- View an image, scroll away, view again → loads instantly from cache
- Download an image, restart app → shows from local file instead of re-downloading
- Reduced bandwidth and faster browsing experience

The cache is stored in `~/.cache/quickshell/booru/previews/` and can be cleared manually if needed.

## File Structure

```
quickshell-booru-sidebar/
├── shell.qml                 # Entry point
├── config.json               # Configuration
├── modules/
│   ├── sidebar/
│   │   ├── SidebarLeft.qml   # Main panel window
│   │   ├── Anime.qml         # Browser UI
│   │   └── anime/
│   │       ├── BooruImage.qml    # Image card
│   │       └── BooruResponse.qml # Image grid
│   └── common/
│       ├── Appearance.qml    # Theme/styling
│       ├── widgets/          # Reusable UI components
│       └── utils/            # Utility components
└── services/
    ├── Booru.qml             # API service
    └── BooruResponseData.qml # Data model
```

## Credits

- Original implementation from [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)
- Adapted for standalone use with Quickshell
- Material Design 3 color scheme (Catppuccin inspired)

## License

MIT License - See individual files for attribution.
