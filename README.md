# Switchcraft

Switchcraft automates light/dark theme transitions on GNOME by running your own shell commands whenever the system preference flips.

## Features
- Watches `org.gnome.desktop.interface color-scheme` and executes commands instantly.
- Polished libadwaita interface with light/dark pages, icons, and header-bar actions.
- Add, edit, enable/disable, or remove commands per theme.
- Define reusable constants for common variables in commands.
- Background monitoring mode with autostart on login.
- Keyboard shortcuts (<kbd>Ctrl</kbd>+<kbd>N</kbd> to add, <kbd>Ctrl</kbd>+<kbd>Q</kbd> to quit) plus About and Shortcuts dialogs from the menu.

## Requirements
- Python 3.10+.
- GNOME with GTK 4 and libadwaita typelibs.
- PyGObject stack from your distribution (examples):
  - Debian/Ubuntu: `sudo apt install python3-gi python3-gi-cairo gir1.2-gtk-4.0 gir1.2-adw-1`
  - Fedora: `sudo dnf install python3-gobject gtk4 libadwaita`
  - Arch: `sudo pacman -S python-gobject gtk4 libadwaita`

## Running
```bash
python -m switchcraft.main
```
Run inside a virtual environment if you prefer, but ensure the system PyGObject packages are available so the `gi` bindings load correctly.

## Background Monitoring

**By default, the app only monitors theme changes while the window is open.** To enable automatic monitoring in the background:

1. Launch Switchcraft and toggle the **"Monitor"** switch in the header bar.
2. A banner will appear prompting you to log out and back in.
3. After logging back in, Switchcraft will run in the background and execute commands when you switch themes.

The toggle creates an autostart entry at `~/.config/autostart/switchcraft.desktop`. To disable background monitoring, simply toggle the switch off—the autostart entry will be removed automatically.

You can also manually run the background monitor:
```bash
python -m switchcraft.main --background
```

## Configuration
Switchcraft stores its configuration in `~/.config/switchcraft/`:

### commands.json
Commands to execute per theme:
```json
{
  "dark": [
    { "command": "notify-send 'Dark mode enabled'", "enabled": true }
  ],
  "light": [
    { "command": "notify-send 'Light mode enabled'", "enabled": true }
  ]
}
```

### constants.json
Reusable variables for commands:
```json
{
  "D2DL_SCHEMADIR": "$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/schemas",
  "D2DL_SCHEMA": "org.gnome.shell.extensions.dash2dock-lite"
}
```

Use constants in commands with `$NAME` or `${NAME}` syntax:
```bash
gsettings --schemadir "$D2DL_SCHEMADIR" set "$D2DL_SCHEMA" customize-label 'true'
```

### settings.json
Application settings:
```json
{
  "monitoring_enabled": true
}
```

Changes made in the UI are saved automatically. Disabled commands remain in the list but are skipped when the theme switches.
