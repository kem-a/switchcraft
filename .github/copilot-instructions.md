<!--
Guidance for AI coding agents working on the Switchcraft repo.
Keep this file short, concrete, and tied to actual files and patterns in the codebase.
-->

# Copilot instructions — Switchcraft

Work quickly and conservatively. This is a small GNOME/libadwaita desktop app that monitors GNOME's theme preference and runs user-defined shell commands when the theme switches.

Key files
- `switchcraft/main.py` — app entrypoint. Instantiates `switchcraft.application.SwitchcraftApp` and `switchcraft.monitor.ThemeMonitor`.
- `switchcraft/application.py` — `SwitchcraftApp` (Adw.Application). Manages resource base path and persistent commands (see `CONFIG_PATH`). Use `get_commands()` / `save_commands()` to read/write `~/.config/switchcraft/commands.json`. Normalizes configuration to support enabled/disabled command entries.
- `switchcraft/monitor.py` — `ThemeMonitor` watches `org.gnome.desktop.interface` `color-scheme`. On change it decides `"dark"` vs `"light"` and runs enabled commands via `subprocess.Popen(cmd, shell=True)`.
- `switchcraft/window.py` — `MainWindow` builds a libadwaita UI with header bar, add command button, menu (About/Shortcuts/Quit), per-theme pages with icons, and command rows with edit/enable/delete controls revealed on hover. UI code keeps state in the application layer via `get_commands()`/`save_commands()`.
- `commands.json` — example/default command list. The runtime config is stored in `~/.config/switchcraft/commands.json` with format: `{"dark": [{"command": "...", "enabled": true}], "light": [...]}`.

- UI rules (must-follow)
- Always follow GNOME HIG when designing app UI and interactions.
- Always use libadwaita (`Adw`) widgets and patterns whenever possible; prefer `Adw` APIs over raw `Gtk` where available.

Architecture and patterns
- Single-process GTK application: creation happens in `switchcraft/main.py`. The `ThemeMonitor` is instantiated with the `SwitchcraftApp` instance so it can call `app.get_commands()`.
- Configuration is JSON stored under `~/.config/switchcraft/commands.json`. `SwitchcraftApp` is the canonical accessor/authority for this configuration. Commands are stored as dicts with `command` (str) and `enabled` (bool) keys.
- Side effects (running user commands) are executed with `subprocess.Popen(..., shell=True)`. Be conservative when editing this behavior — it's an intentional design to allow arbitrary shell syntax. Only enabled commands are executed.
- GTK UI code uses libadwaita (`Adw`) and standard `Gtk` widgets. Follow the existing pattern: `MainWindow` that calls `__build_ui()` to compose widgets; avoid moving GTK logic into unrelated modules.

Developer workflows and commands
- Run the app locally: `python -m switchcraft.main` (see `README.md`).
- Dependencies: Python 3.10+, PyGObject (system package), GNOME with GTK4/libadwaita.
- Configuration during development: edit `commands.json` or the real config at `~/.config/switchcraft/commands.json`.

Conventions and constraints for patches
- Keep changes minimal and focused. Match the project's style: small, explicit functions; no heavy frameworks or external infrastructure.
- When adding new public functions/methods, update `SwitchcraftApp` accessors if they touch configuration/state used by `ThemeMonitor` or UI.
- Avoid introducing background threads; use GLib/Gio signals and the GTK main loop for scheduling.

Security and safety notes
- Running arbitrary shell commands is an explicit feature. When modifying `switchcraft/monitor.py` or command execution, do not silently sanitize or drop shell invocation semantics unless the change is deliberate and documented.

Examples to reference
- To add a new UI control that updates commands, call `app.get_commands()`, modify the dict, then `app.save_commands(commands)` to persist.
- To detect theme change logic, `switchcraft/monitor.py` maps `settings.get_string("color-scheme") == "prefer-dark"` to `"dark"`.

If anything in this file looks wrong or incomplete, edit the file and leave a concise note explaining why (references to the changed lines are helpful).
