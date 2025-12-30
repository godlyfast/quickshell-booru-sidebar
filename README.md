# Quickshell Booru Sidebar

A beautiful anime image browser sidebar for [Quickshell](https://quickshell.outfoxxed.me/) on Hyprland. Browse images from multiple booru sources directly from your desktop.

![Booru Sidebar](https://img.shields.io/badge/Quickshell-0.2.1+-blue) ![Hyprland](https://img.shields.io/badge/Hyprland-Required-green)

## Features

- **Multiple Booru Sources**: yande.re, Konachan, Danbooru, Gelbooru, waifu.im
- **Tag Search**: Search images by tags with autocomplete suggestions
- **NSFW Toggle**: Filter content based on your preferences
- **Image Actions**: Open source, view full image, download to custom paths
- **Responsive Grid**: Auto-sizing image grid with smooth scrolling
- **Material Design**: Beautiful Material 3 inspired UI with Catppuccin colors
- **Keyboard Support**: ESC to close, click outside to dismiss

## Requirements

- [Quickshell](https://quickshell.outfoxxed.me/) 0.2.1+
- [Hyprland](https://hyprland.org/) (for focus grab and layer shell)
- `ttf-material-symbols-variable` font (for icons)
- `curl` (for image downloads)

### Install Dependencies (Arch Linux)

```bash
# Quickshell (AUR)
yay -S quickshell-git

# Material Symbols font
sudo pacman -S ttf-material-symbols-variable

# curl (usually pre-installed)
sudo pacman -S curl
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

## Configuration

Edit `config.json` to customize:

```json
{
  "booru": {
    "defaultProvider": "yandere",
    "nsfw": false,
    "downloadPath": "~/Pictures/booru",
    "nsfwPath": "~/Pictures/booru/nsfw",
    "gelbooruApiKey": "",
    "gelbooruUserId": ""
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

## Supported Booru APIs

| Provider | API Type | NSFW Support | Auth Required |
|----------|----------|--------------|---------------|
| yande.re | Moebooru | Yes | No |
| Konachan | Moebooru | Yes | No |
| Danbooru | Danbooru | Yes | No |
| Gelbooru | Gelbooru | Yes | **Yes** |
| waifu.im | REST | Yes | No |

### Gelbooru API Key

Gelbooru requires API authentication. To use Gelbooru:

1. Create an account at [gelbooru.com](https://gelbooru.com)
2. Go to [Account Options](https://gelbooru.com/index.php?page=account&s=options)
3. Copy your **API Key** and **User ID**
4. Add them to your `config.json`:

```json
{
  "booru": {
    "gelbooruApiKey": "your_api_key_here",
    "gelbooruUserId": "your_user_id_here"
  }
}
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
