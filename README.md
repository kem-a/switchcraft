# Switchcraft

Switchcraft watches GNOME's light/dark preference and runs your shell commands when the theme changes.

## Features
- Watches `org.gnome.desktop.interface color-scheme` and executes commands instantly.
- Polished libadwaita interface with light/dark pages, icons, and header-bar actions.
- Add, edit, enable/disable, or remove commands per theme.
- Define reusable constants for common variables in commands.
- Background monitoring mode with autostart on login.
- Keyboard shortcuts (<kbd>Ctrl</kbd>+<kbd>N</kbd> to add, <kbd>Ctrl</kbd>+<kbd>Q</kbd> to quit) plus About and Shortcuts dialogs from the menu.

## Requirements
- GNOME 40+ (GTK 4 and libadwaita)
- GLib 2.66+
- Vala compiler (for building)
- Meson build system

### Install dependencies (examples)

**Debian/Ubuntu:**
```bash
sudo apt install meson valac libgtk-4-dev libadwaita-1-dev libjson-glib-dev
```

**Fedora:**
```bash
sudo dnf install meson vala gtk4-devel libadwaita-devel json-glib-devel
```

**Arch:**
```bash
sudo pacman -S meson vala gtk4 libadwaita json-glib
```

## Building and Installing

```bash
# Configure the build
meson setup builddir

# Compile
meson compile -C builddir

# Install (optional)
sudo meson install -C builddir
```

## Running

After building:
```bash
# Run from build directory
./builddir/switchcraft

# Or after installing
switchcraft
```

Run as background monitor (creates autostart when enabled via UI):
```bash
switchcraft --background
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

### Autostart
When enabled from the UI, the app writes an autostart file at `~/.config/autostart/switchcraft.desktop`.

## Key files

- `src/main.vala` — application entrypoint; creates `Application` and `ThemeMonitor`.
- `src/Application.vala` — main application class with configuration management.
- `src/ThemeMonitor.vala` — watches GNOME settings and runs enabled commands.
- `src/MainWindow.vala` — main UI window implementation (libadwaita).
- `src/ConstantsWindow.vala` — constants management UI.
- `meson.build` — build configuration.

## Development

Build in debug mode:
```bash
meson setup builddir --buildtype=debug
meson compile -C builddir
./builddir/switchcraft
```

The project follows GNOME HIG and uses libadwaita widgets exclusively.

## Notes

- Running arbitrary shell commands is an explicit feature. Commands are executed with full shell syntax support.
- Follow GNOME HIG when changing UI code and prefer libadwaita (`Adw`) widgets.

## Troubleshooting

- If build fails, ensure all development dependencies are installed.
- If commands don't run, check `~/.config/switchcraft/commands.json` for enabled flags and correct shell quoting.

## License

This project is provided under the terms in `LICENSE`.

## Contributing

Open issues or PRs on the repository. Keep changes small and focused.
