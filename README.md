# Switchcraft

Switchcraft automates light/dark theme transitions on GNOME by running your own shell commands whenever the system preference flips.

## Features
- Watches `org.gnome.desktop.interface color-scheme` and executes commands instantly.
- Polished libadwaita interface with light/dark pages, icons, and header-bar actions.
- Add, edit, enable/disable, or remove commands per theme.
- Define reusable constants for common variables in commands.
- Background monitoring mode with autostart on login.
- Keyboard shortcuts (<kbd>Ctrl</kbd>+<kbd>N</kbd> to add, <kbd>Ctrl</kbd>+<kbd>Q</kbd> to quit) plus About and Shortcuts dialogs from the menu.

# Switchcraft

Switchcraft watches GNOME's light/dark preference and runs your shell commands when the theme changes.

Quick highlights
- Per-theme command lists (enable/disable individual commands).
- Libadwaita UI for editing commands, constants and app settings.
- Optional background monitor with autostart on login.

Requirements
- Python 3.10 or newer
- GNOME (GTK 4) and libadwaita installed (distribution provided typelibs)
- PyGObject bindings (system packages; commonly named `python3-gi`, `gir1.2-gtk-4.0`, `gir1.2-adw-1`)

# Switchcraft

Switchcraft watches GNOME's light/dark preference and runs your shell commands when the theme changes.

Quick highlights
- Per-theme command lists (enable/disable individual commands).
- Libadwaita UI for editing commands, constants and app settings.
- Optional background monitor with autostart on login.

Requirements
- Python 3.10 or newer
- GNOME (GTK 4) and libadwaita installed (distribution provided typelibs)
- PyGObject bindings (system packages; commonly named `python3-gi`, `gir1.2-gtk-4.0`, `gir1.2-adw-1`)

Install (examples)
- Debian/Ubuntu:
  ```bash
  sudo apt install python3-gi python3-gi-cairo gir1.2-gtk-4.0 gir1.2-adw-1
  ```
- Fedora:
  ```bash
  sudo dnf install python3-gobject gtk4 libadwaita
  ```
- Arch:
  ```bash
  sudo pacman -S python-gobject gtk4 libadwaita
  ```

Run locally
```bash
python -m switchcraft.main
```

Run as background monitor (same binary; creates autostart when enabled via UI):
```bash
python -m switchcraft.main --background
```

Configuration
All runtime configuration lives under `~/.config/switchcraft/`.

- `commands.json` — per-theme command lists. Example:

```json
{
  "dark": [{ "command": "notify-send 'Dark mode enabled'", "enabled": true }],
  "light": [{ "command": "notify-send 'Light mode enabled'", "enabled": true }]
}
```

- `constants.json` — reusable variables referenced inside commands using `$NAME` or `${NAME}`.

Example:
```json
{
  "D2DL_SCHEMADIR": "$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/schemas",
  "D2DL_SCHEMA": "org.gnome.shell.extensions.dash2dock-lite"
}
```

- `settings.json` — small app settings (e.g., `monitoring_enabled`). The UI saves changes automatically.

Autostart
- When enabled from the UI the app writes an autostart file at `~/.config/autostart/switchcraft.desktop`.

Key files
- `switchcraft/main.py` — application entrypoint.
- `switchcraft/application.py` — `SwitchcraftApp` handles configuration persistence and app-level state.
- `switchcraft/monitor.py` — `ThemeMonitor` watches GNOME settings and runs enabled commands via `subprocess.Popen(cmd, shell=True)`.
- `switchcraft/window.py` — UI implementation (libadwaita).

Development
- Create a virtualenv, but ensure system PyGObject typelibs are installed so `gi` imports work.

```bash
python -m venv .venv
source .venv/bin/activate
# install non-gi dev deps if needed, then run
python -m switchcraft.main
```

Notes
- Running arbitrary shell commands is an explicit feature. The app intentionally uses `shell=True` to allow complex shell syntax.
- Follow GNOME HIG when changing UI code and prefer libadwaita (`Adw`) widgets.

Troubleshooting
- If `import gi` fails, confirm you have the system PyGObject packages installed (not just pip packages).
- If commands don't run, check `~/.config/switchcraft/commands.json` for enabled flags and correct shell quoting.

License
- This project is provided under the terms in `LICENSE`.

Contributing
- Open issues or PRs on the repository. Keep changes small and focused. Update `SwitchcraftApp` accessors when modifying configuration behaviour used by the monitor or UI.
