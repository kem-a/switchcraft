<!-- Guidance for AI coding agents working on the Switchcraft repo. -->

# Copilot instructions — Switchcraft

Short, focused guidance for contributors and automated agents working on this small GNOME/libadwaita desktop app.

What the app does
- Watches GNOME's `org.gnome.desktop.interface` `color-scheme` and runs user-defined shell commands when the preference flips between light and dark.

Key files
- `switchcraft/main.py` — application entrypoint; creates `SwitchcraftApp` and `ThemeMonitor`.
- `switchcraft/application.py` — `SwitchcraftApp` (Adw.Application); canonical accessor for configuration. Use `get_commands()` / `save_commands()` to read/write the runtime config located at `~/.config/switchcraft/commands.json`.
- `switchcraft/monitor.py` — `ThemeMonitor` watches the GNOME setting and runs enabled commands using `subprocess.Popen(cmd, shell=True)`.
- `switchcraft/window.py` — UI (libadwaita) implementation and wiring to `SwitchcraftApp` for persistence.

Development notes
- Run locally with: `python -m switchcraft.main`.
- Python 3.10+ and system PyGObject typelibs (GTK4, libadwaita) are required. Install these via your distro package manager — see `README.md` for examples.
- Use a virtualenv for Python dependencies, but keep system PyGObject installed so `gi` imports succeed.

Design and architecture constraints
- Single-process GTK app; prefer GLib/Gio signals and the GTK main loop over threads.
- Keep UI code in `window.py` and app-level state/persistence in `application.py`.
- Commands are intentionally executed with `shell=True` to allow arbitrary shell syntax — do not change this without documenting the reason.

When making changes
- Keep patches small and focused. Update `SwitchcraftApp` accessors if you change configuration schema used by the monitor or UI.
- Follow GNOME HIG and prefer libadwaita (`Adw`) widgets.

Troubleshooting for contributors
- If `import gi` fails while developing, confirm system packages for PyGObject/GTK are installed (not just pip packages).

If you update these instructions, leave a short note in the file explaining why.
