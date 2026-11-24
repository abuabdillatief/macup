# macup

A lightweight, native macOS SwiftUI app to automate your workspace on startup — or switch setups in one click from the menu bar.

Configure **CLI commands**, **apps to launch**, **macOS Desktop spaces**, and **window tiling** (left/right/top/bottom halves, corners, thirds, maximized, or centered) per profile.

## Features

- **Multiple Workspace Profiles**: Create profiles like *Work*, *Coding*, or *Focus*. Pick one as your default startup profile and trigger any profile from the menu bar.
- **CLI Commands**: Run shell commands silently in the background (`/bin/zsh -lc`) or open them in a visible Terminal window, with custom working directory and optional delay.
- **Desktops & Window Tiling**:
  - Group apps by macOS Desktop (`Desktop 1`–`9` or `Current Desktop`).
  - **Browser URLs**: Automatically detects browsers (Safari, Chrome, Arc, Firefox, Brave, Edge, etc.) so you can configure one or more URLs to open on launch (and lets you attach URLs/deep links to any app).
  - Snap windows to **Maximize**, **Left / Right / Top / Bottom Half**, **Top-Left / Top-Right / Bottom-Left / Bottom-Right Corner**, **Left / Center / Right Third**, **Left / Right Two-Thirds**, or **Centered**.
  - Live miniature monitor preview inside each Desktop card so you can visually verify your layout.
  - Multi-display support (choose Display 1, Display 2, etc.).
- **Launch at Login**: Native macOS `SMAppService` integration plus optional auto-run of your default profile on launch (with configurable startup delay).
- **Per-Item Testing & Activity Log**: Test any single CLI command or app placement right from the editor.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.10+ (Xcode or Xcode Command Line Tools)

## Build & Install

```bash
git clone <your-repo-url> macup
cd macup
./scripts/build_app.sh
open build/macup.app
```

To install permanently in `/Applications`:

```bash
cp -R build/macup.app /Applications/macup.app
open /Applications/macup.app
```

## macOS Permissions

1. **Accessibility** (*required for window tiling and Desktop switching*):
   - Open **System Settings → Privacy & Security → Accessibility** and enable **macup** (or click **Grant Access** in the in-app banner).
2. **Mission Control Desktop Shortcuts** (*for switching to Desktop 1–9*):
   - Open **System Settings → Keyboard → Keyboard Shortcuts → Mission Control** and enable **Switch to Desktop 1**, **Switch to Desktop 2**, etc. (`^1`, `^2`, ...).
3. **Automation** (*optional, for "Open in Terminal" commands and "Add New Space"*):
   - macOS will prompt automatically the first time you run a Terminal command or Mission Control action.

## Configuration Storage

Profiles and settings are stored as plain JSON at:

```
~/Library/Application Support/macup/profiles.json
```

## License

MIT — see [LICENSE](LICENSE).
