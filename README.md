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

### Run from Source (Development)

```bash
# Configure
meson setup builddir

# Compile
meson compile -C builddir

# Run directly
./builddir/switchcraft
```

## How It Works

Switchcraft uses a **two-component architecture**:

1. **Main GUI Application** (`switchcraft`) - GTK4/libadwaita interface for configuration
2. **Monitor Script** (`switchcraft-monitor.sh`) - Independent bash script that watches theme changes

### Monitor Toggle Behavior

When you **enable monitoring** in the GUI:
- Monitor script is installed to `~/.local/bin/switchcraft-monitor.sh`
- Autostart desktop entry created at `~/.config/autostart/switchcraft-monitor.desktop`
- Script starts immediately and runs in background

When you **disable monitoring**:
- Autostart entry removed
- Running monitor processes killed
- Script removed from `~/.local/bin`

### Command Execution Flow

```
GNOME theme changes
    ↓
gsettings monitor detects change
    ↓
switchcraft-monitor.sh reads commands.json
    ↓
Loads constants.json as environment variables
    ↓
Executes enabled commands for current theme
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

## Key files

- `src/main.vala` — application entrypoint (simplified, no background mode)
- `src/Application.vala` — main application class with configuration management and monitor script installation
- `src/ThemeMonitor.vala` — ⚠️ **Legacy code** - no longer used (monitor script handles theme watching)
- `src/MainWindow.vala` — main UI window implementation (libadwaita)
- `src/ConstantsWindow.vala` — constants management UI
- `switchcraft-monitor.sh` — independent bash monitor script copied to `~/.local/bin` when monitoring is enabled
- `meson.build` — build system configuration with ninja install/remove targets
- `ARCHITECTURE.md` — detailed architecture documentation
- `samples/` — example scripts for common theme-switching use cases

## Development

Build in debug mode:
```bash
meson setup builddir --buildtype=debug
meson compile -C builddir
./builddir/switchcraft
```

The project follows GNOME HIG and uses libadwaita widgets exclusively.

## Troubleshooting

- **Build fails**: Ensure all development dependencies are installed (including `jq`)
- **Commands don't run**: Check `~/.config/switchcraft/commands.json` for enabled flags and correct shell quoting
- **Monitor not working**: Enable monitoring in the GUI, check `~/.local/bin/switchcraft-monitor.sh` exists and is executable
- **Theme changes not detected**: Verify GNOME settings are working with `gsettings get org.gnome.desktop.interface color-scheme`
- **Rebuild issues**: Use `meson setup builddir --wipe` to reconfigure from scratch

## Notes

- Commands are executed with full shell syntax support - this is an explicit feature
- The monitor script runs independently and works even when the GUI is closed
- Follow GNOME HIG when changing UI code and prefer libadwaita (`Adw`) widgets
- The app is designed for per-user installation but supports system-wide deployment

## License

This project is provided under the terms in `LICENSE`.

## Contributing

Open issues or PRs on the repository. Keep changes small and focused.
