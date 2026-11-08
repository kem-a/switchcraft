<!-- Core project info -->
[![Download](https://img.shields.io/badge/Download-latest-blue)](https://github.com/kem-a/switchcraft/releases/latest)
[![Release](https://img.shields.io/github/v/release/kem-a/switchcraft?semver)](https://github.com/kem-a/switchcraft/releases/latest)
[![License](https://img.shields.io/github/license/kem-a/switchcraft)](https://github.com/kem-a/switchcraft/blob/main/LICENSE)
![GNOME 42+](https://img.shields.io/badge/GNOME-42%2B-blue?logo=gnome)
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

```bash
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

- Desktop: GNOME 42+ (Switchcraft follows the `org.gnome.desktop.interface color-scheme` setting)
- Build tools: a C compiler, `valac`, `meson` (>= 0.59), `ninja`, `pkg-config`, `gettext`, `glib-compile-resources`, `glib-compile-schemas`
- Libraries (with development headers): `gtk4`, `libadwaita-1` (>= 1.5), `glib-2.0` (>= 2.66), `gio-2.0`, `json-glib-1.0`
- Runtime tools: `gsettings`, `zip` and `unzip` (configuration export and import), `pkill` (stopping the background monitor)
- AnyLinux AppImage packaging with `scripts/make-anyimage.sh`: `podman` (the build runs in an Arch Linux container)
- Local AppImage packaging with `scripts/make-appimage.sh`: `bash`, `jq` and `appimagetool` (downloaded automatically if missing)

## Install

Simply [download](https://github.com/kem-a/switchcraft/releases/latest) the latest AppImage, enable execute and run it.
For seamless AppImage installation use [AppManager](https://github.com/kem-a/AppManager).

> The AnyLinux AppImage bundles GTK 4 and libadwaita, so it runs on any distro with a GNOME desktop.

## Build

<details> <summary> <H4>Install development dependencies</H4> <b>(click to open)</b> </summary>

Your distribution must provide libadwaita >= 1.5. The lists include `zip`, `unzip` and `jq`.

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

Build the portable AnyLinux AppImage (output in `build-anyimage/dist/`)

```bash
./scripts/make-anyimage.sh
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
