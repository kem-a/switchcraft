<!-- Core project info -->
[![Download](https://img.shields.io/badge/Download-latest-blue)](https://github.com/kem-a/switchcraft/releases/latest)
[![Release](https://img.shields.io/github/v/release/kem-a/switchcraft?semver)](https://github.com/kem-a/switchcraft/releases/latest)
[![License](https://img.shields.io/github/license/kem-a/switchcraft)](https://github.com/kem-a/switchcraft/blob/main/LICENSE)
![GNOME 40+](https://img.shields.io/badge/GNOME-40%2B-blue?logo=gnome)
![GTK 4](https://img.shields.io/badge/GTK-4-blue?logo=gtk)
![Vala](https://img.shields.io/badge/Vala-compiler-blue?logo=vala)
[![Stars](https://img.shields.io/github/stars/kem-a/switchcraft?style=social)](https://github.com/kem-a/switchcraft/stargazers)

# <img width="48" height="48" alt="switchcraft" src="https://github.com/user-attachments/assets/410929d4-a94f-49f7-af37-b0f090270f79" /> Switchcraft

Switchcraft watches GNOME's light/dark preference and runs your shell commands when the theme changes.


<img width="607" height="400" alt="Screenshot From 2025-11-25 13-38-16" src="https://github.com/user-attachments/assets/c4e4f154-45b5-4084-bac2-c02be4b58361" />


## Features
- Watches `org.gnome.desktop.interface color-scheme` and executes commands instantly.
- Polished libadwaita interface with light/dark pages, icons, and header-bar actions.
- Add, edit, enable/disable, or remove commands per theme.
- Define reusable constants for common variables in commands.
- **Independent background monitoring** - separate bash script runs even when GUI is closed.
- Keyboard shortcuts (<kbd>Ctrl</kbd>+<kbd>N</kbd> to add, <kbd>Ctrl</kbd>+<kbd>Q</kbd> to quit) plus About and Shortcuts dialogs from the menu.

<details> <summary> Command Examples <b>(click to open)</b> </summary>

- Change legacy theme to dark:
  
`gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'`

- Change icon theme to light:

`gsettings set org.gnome.desktop.interface icon-theme 'MacTahoe-light'`

- Set constants:

```
D2DL_SCHEMADIR="$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/schemas"
D2DL_SCHEMA="org.gnome.shell.extensions.dash2dock-lite"
```

- Change Dash 2 Dock Lite background based on theme and using constants

Light theme:

`gsettings --schemadir $D2DL_SCHEMADIR set $D2DL_SCHEMA background-color '(0.063, 0.1216, 0.1882, 1.0)'`

Dark theme:

`gsettings --schemadir $D2DL_SCHEMADIR set $D2DL_SCHEMA background-color '(0.3373, 0.4392, 0.5294, 1.0)'`

</details>

## Requirements
- GNOME 40+ (GTK 4 and libadwaita)
- GLib 2.66+
- Vala compiler (for building)
- Meson build system
- jq (for JSON parsing in monitor script)
- ruby, rubygems, rpmbuild, appimagetool and chrpath (for packaging only)

<details> <summary> Install dependencies <b>(click to open)</b> </summary>
  
**Debian/Ubuntu:**
```bash
sudo apt install meson valac libgtk-4-dev libadwaita-1-dev libjson-glib-dev jq ruby ruby-dev rubygems build-essential
gem install --user-install fpm
```

**Fedora:**
```bash
sudo dnf install meson vala gtk4-devel libadwaita-devel json-glib-devel jq ruby rubygems rpmbuild chrpath
gem install --user-install fpm
```

**Arch:**
```bash
sudo pacman -S meson vala gtk4 libadwaita json-glib jq ruby
gem install --user-install fpm
```

**AppImageTool**

Download from [here](https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage) and copy to `$PATH`

</details>

## Installing

[Download latest](https://github.com/kem-a/switchcraft/releases) release rpm, deb or AppImage.
For seemless AppImage installation use [AppManager](https://github.com/kem-a/AppManager).

## Building

<details> <summary> Details <b>(click to open)</b> </summary>
  
#### User-Level building and installation (Recommended)

```bash
# Configure for user installation
meson setup build --prefix="$HOME/.local"

# Compile
meson compile -C build

# Install to ~/.local
ninja -C build install

# Uninstall
ninja -C build remove
```

#### System-Wide Installation

```bash
# Configure for system installation
meson setup build --prefix=/usr/local

# Compile
meson compile -C build

# Install system-wide
sudo ninja -C build install

# Uninstall
sudo ninja -C build remove
```
</details>
  
## Configuration

<details> <summary> Details <b>(click to open)</b> </summary>

All runtime configuration lives under `~/.config/switchcraft/`.

- **`commands.json`** - per-theme command lists. Example:

```json
{
  "dark": [{ "command": "notify-send 'Dark mode enabled'", "enabled": true }],
  "light": [{ "command": "notify-send 'Light mode enabled'", "enabled": true }]
}
```

- **`constants.json`** - reusable variables referenced inside commands using `$NAME` or `${NAME}`.

Example:
```json
{
  "D2DL_SCHEMADIR": "$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/schemas",
  "D2DL_SCHEMA": "org.gnome.shell.extensions.dash2dock-lite"
}
```

</details>

## License

This project is provided under the terms in `LICENSE`.
