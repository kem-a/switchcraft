# Switchcraft

Switchcraft automates light/dark theme transitions on GNOME by running your own shell commands whenever the system preference flips.

## Features
- Watches `org.gnome.desktop.interface color-scheme` and executes commands instantly.
- Polished libadwaita interface with light/dark pages, icons, and header-bar actions.
- Add, edit, enable/disable, or remove commands per theme; actions appear on hover or selection.
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

## Configuration
Switchcraft stores its state at `~/.config/switchcraft/commands.json`. Each entry records a command and whether it is enabled:

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

Changes made in the UI are saved automatically. Disabled commands remain in the list but are skipped when the theme switches.
