# Switchcraft

Switchcraft watches GNOME's light/dark preference and runs your shell commands when the theme changes.

## Features
- Watches `org.gnome.desktop.interface color-scheme` and executes commands instantly.
- Polished libadwaita interface with light/dark pages, icons, and header-bar actions.
- Add, edit, enable/disable, or remove commands per theme.
- Define reusable constants for common variables in commands.
- **Independent background monitoring** - separate bash script runs even when GUI is closed.
- Keyboard shortcuts (<kbd>Ctrl</kbd>+<kbd>N</kbd> to add, <kbd>Ctrl</kbd>+<kbd>Q</kbd> to quit) plus About and Shortcuts dialogs from the menu.

## Requirements
- GNOME 40+ (GTK 4 and libadwaita)
- GLib 2.66+
- Vala compiler (for building)
- Meson build system
- jq (for JSON parsing in monitor script)

### Install dependencies (examples)

**Debian/Ubuntu:**
```bash
sudo apt install meson valac libgtk-4-dev libadwaita-1-dev libjson-glib-dev jq
```

**Fedora:**
```bash
sudo dnf install meson vala gtk4-devel libadwaita-devel json-glib-devel jq
```

**Arch:**
```bash
sudo pacman -S meson vala gtk4 libadwaita json-glib jq
```

## Building and Installing

### User-Level Installation (Recommended)

```bash
# Configure for user installation
meson setup builddir --prefix="$HOME/.local"

# Compile
meson compile -C builddir

# Install to ~/.local
ninja -C builddir install

# Uninstall
ninja -C builddir remove
```

### System-Wide Installation

```bash
# Configure for system installation
meson setup builddir --prefix=/usr/local

# Compile
meson compile -C builddir

# Install system-wide
sudo ninja -C builddir install

# Uninstall
sudo ninja -C builddir remove
```

## Configuration

All runtime configuration lives under `~/.config/switchcraft/`.

- **`commands.json`** — per-theme command lists. Example:

```json
{
  "dark": [{ "command": "notify-send 'Dark mode enabled'", "enabled": true }],
  "light": [{ "command": "notify-send 'Light mode enabled'", "enabled": true }]
}
```

- **`constants.json`** — reusable variables referenced inside commands using `$NAME` or `${NAME}`.

Example:
```json
{
  "D2DL_SCHEMADIR": "$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/schemas",
  "D2DL_SCHEMA": "org.gnome.shell.extensions.dash2dock-lite"
}
```

- **`settings.json`** — app settings (e.g., `monitoring_enabled`). The UI saves changes automatically.

### Monitor Files

When monitoring is enabled:
- `~/.local/bin/switchcraft-monitor.sh` — The monitoring script (installed automatically)
- `~/.config/autostart/switchcraft-monitor.desktop` — Autostart entry for login persistence

## License

This project is provided under the terms in `LICENSE`.
