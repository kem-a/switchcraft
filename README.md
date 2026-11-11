<!-- Core project info -->
[![Download](https://img.shields.io/badge/Download-latest-blue)](https://github.com/kem-a/switchcraft/releases/latest)
[![Release](https://img.shields.io/github/v/release/kem-a/switchcraft?semver)](https://github.com/kem-a/switchcraft/releases/latest)
[![License](https://img.shields.io/github/license/kem-a/switchcraft)](https://github.com/kem-a/switchcraft/blob/main/LICENSE)
[![AnyLinux](https://img.shields.io/badge/AnyLinux-compatible-green?logo=linux&logoColor=white)](https://pkgforge-dev.github.io/Anylinux-AppImages/)
![GTK 4](https://img.shields.io/badge/GTK-4-blue?logo=gtk)
![Vala](https://img.shields.io/badge/Vala-compiler-blue?logo=vala)
[![Stars](https://img.shields.io/github/stars/kem-a/switchcraft?style=social)](https://github.com/kem-a/switchcraft/stargazers)

# <img width="48" height="48" alt="switchcraft" src="https://github.com/user-attachments/assets/410929d4-a94f-49f7-af37-b0f090270f79" /> Switchcraft

**Switchcraft** watches GNOME's or KDE Plasma light/dark preference and runs your shell commands when the theme changes.

> **This AppImage bundles everything and it should work on any Linux distro, including old and musl-based ones.**

Switchcraft doesn't require FUSE to run, thanks to the [uruntime](https://github.com/VHSgunzo/uruntime)

## Preview

<img width="900" height="670" alt="Screenshot From 2026-11-11 22-43-39" src="https://github.com/user-attachments/assets/1a31d5b4-9f38-42a5-8005-e705730cb095" />

## Features

- Run custom commands on theme switch.
- Switch between light and dark style automatically at sunset and sunrise, or at custom times (Preferences). Uses GeoClue for the location when allowed, else the system time zone. On KDE Plasma it switches the default light and dark global themes, unless Plasma's own automatic switching is enabled.
- Built-in commands: pick a setting and a value from a list instead of typing a command. Only the ones for the running desktop are offered:
  - GNOME: color scheme, accent color, icon, GTK, cursor and shell theme, wallpaper, Night Light.
  - KDE Plasma: global theme, color scheme, Plasma style, icon and cursor theme, wallpaper.
  - Any desktop: Kvantum theme, when Kvantum is installed.
- Define reusable constants for common variables in commands.
- Add, edit, enable/disable, reorder or remove commands per theme.

<details> <summary> Command Examples <b>(click to open)</b> </summary>


- Change Dash 2 Dock Lite background based on theme and using constants

Light theme:

`gsettings --schemadir $D2DL_SCHEMADIR set $D2DL_SCHEMA background-color '(0.063, 0.1216, 0.1882, 1.0)'`

Dark theme:

`gsettings --schemadir $D2DL_SCHEMADIR set $D2DL_SCHEMA background-color '(0.3373, 0.4392, 0.5294, 1.0)'`

- Set constants:

```bash
D2DL_SCHEMADIR="$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/schemas"
D2DL_SCHEMA="org.gnome.shell.extensions.dash2dock-lite"
```

- Change legacy theme to dark:
  
`gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'`

- Change icon theme to light:

`gsettings set org.gnome.desktop.interface icon-theme 'MacTahoe-light'`

</details>

## Install

Simply [download](https://github.com/kem-a/switchcraft/releases/latest) the latest AppImage, enable execute and run it.

For seamless AppImage installation use [AppManager](https://github.com/kem-a/AppManager).

## Requirements

- Build tools: a C compiler, `valac`, `meson` (>= 0.59), `ninja`, `pkg-config`, `gettext`, `glib-compile-resources`, `glib-compile-schemas`
- Libraries (with development headers): `gtk4`, `libadwaita-1` (>= 1.8), `glib-2.0` (>= 2.66), `gio-2.0`, `json-glib-1.0`
- Runtime tools: `gsettings`, `zip` and `unzip` (configuration export and import), `pgrep` and `pkill` (managing the background monitor). Optional: GeoClue with location services on, for exact sunrise and sunset; Plasma's `plasma-apply-*` tools for the KDE built-ins; `kvantummanager` for the Kvantum built-in
- AnyLinux AppImage packaging with `scripts/make-anyimage.sh`: `podman` (the build runs in an Arch Linux container)
- Local AppImage packaging with `scripts/make-appimage.sh`: `bash`, `jq` and `appimagetool` (downloaded automatically if missing)

## Build

<details> <summary> <H4>Install development dependencies</H4> <b>(click to open)</b> </summary>

Your distribution must provide libadwaita >= 1.8. The lists include `zip`, `unzip` and `jq`.

- **Debian / Ubuntu:**

```bash
sudo apt install build-essential valac meson ninja-build pkg-config gettext \
  libglib2.0-dev libgtk-4-dev libadwaita-1-dev libjson-glib-dev zip unzip jq
```

- **Fedora:**

```bash
sudo dnf install gcc vala meson ninja-build pkgconf-pkg-config gettext \
  glib2-devel gtk4-devel libadwaita-devel json-glib-devel zip unzip jq
```

- **Arch Linux / Manjaro:**

```bash
sudo pacman -S --needed base-devel vala meson ninja gettext glib2 gtk4 libadwaita json-glib zip unzip jq
```

On Arch Linux / Manjaro, `base-devel` supplies the C compiler and `pkgconf`.

`jq` is needed by `scripts/make-appimage.sh`, but not by the Meson build itself.

</details>

Default setup

```bash
meson setup build --prefix=$HOME/.local
```

Build and install

```bash
meson compile -C build
meson install -C build
```

Uninstall

```bash
ninja -C build remove
```

For a system-wide install use `--prefix=/usr/local` and run the install and remove steps with `sudo`.

Build portable AppImage versions:

```bash
scripts/make-anyimage.sh  # anylinux version (long build)
scripts/make-appimage.sh  # standard AppImage (requires FUSE)
```

## Translations

UI strings use gettext. See [po/README.md](po/README.md) for the workflow.
`./scripts/translations.sh --pot-only` refreshes the template without touching
existing `.po` files.

## Configuration

<details> <summary> Details <b>(click to open)</b> </summary>

All runtime configuration lives under `~/.local/share/switchcraft/`.

- **`commands.json`** - per-theme command lists. Example:

```json
{
  "dark": [{ "command": "notify-send 'Dark mode enabled'", "enabled": true }],
  "light": [{ "command": "notify-send 'Light mode enabled'", "enabled": true }]
}
```

- **`constants.json`** - reusable variables referenced inside commands using `$NAME` or `${NAME}`. Values are expanded by the shell, so `$HOME` works inside them.

Example:

```json
{
  "D2DL_SCHEMADIR": "$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/schemas",
  "D2DL_SCHEMA": "org.gnome.shell.extensions.dash2dock-lite"
}
```

Built-in commands are stored in `commands.json` as normal `gsettings` lines with two extra fields, so the dialog can reopen them:

```json
{ "command": "gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'",
  "enabled": true, "builtin": "gtk-theme", "value": "adw-gtk3-dark" }
```

</details>
