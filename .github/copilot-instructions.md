<!-- Guidance for AI coding agents working on the Switchcraft repo. -->

# Copilot instructions — Switchcraft

Short, focused guidance for contributors and automated agents working on this small GNOME/libadwaita desktop app written in Vala.

What the app does
- Watches GNOME's `org.gnome.desktop.interface` `color-scheme` and runs user-defined shell commands when the preference flips between light and dark.
- Uses a **two-component architecture**: GTK GUI for configuration + independent bash monitor script.

Key files
- `src/main.vala` — application entrypoint (simplified, no background mode)
- `src/Application.vala` — main application class with configuration management and monitor script installation. Use `get_commands()` / `save_commands()` to read/write the runtime config located at `~/.config/switchcraft/commands.json`.
- `src/ThemeMonitor.vala` — ⚠️ **LEGACY CODE** - no longer used. Monitor functionality moved to bash script.
- `src/MainWindow.vala` — UI (libadwaita) implementation and wiring to `Application` for persistence.
- `src/ConstantsWindow.vala` — constants management UI for user-defined variables.
- `switchcraft-monitor.sh` — independent bash monitor script (embedded in Application.vala, installed to ~/.local/bin)
- `meson.build` — build system configuration with ninja install/remove targets.

Development notes
- Build with: `meson setup builddir && meson compile -C builddir`
- Install with: `ninja -C builddir install` (user-level) or `sudo ninja -C builddir install` (system-wide)
- Uninstall with: `ninja -C builddir remove`
- Run locally with: `./builddir/switchcraft`
- Vala compiler, GTK4, libadwaita, json-glib, and jq development headers are required. Install these via your distro package manager — see `README.md` for examples.

Design and architecture constraints
- **Two-component architecture**: GTK GUI (configuration) + bash monitor script (execution)
- Monitor script is embedded in Application.vala and installed to ~/.local/bin when monitoring enabled
- Single-process GTK app for GUI; prefer GLib/Gio signals and the GTK main loop
- Keep UI code in `MainWindow.vala` and `ConstantsWindow.vala`, app-level state/persistence in `Application.vala`
- Commands are intentionally executed with full shell support to allow arbitrary shell syntax — do not change this without documenting the reason
- Monitor script uses `gsettings monitor` + `jq` for reliable theme change detection

When making changes
- Keep patches small and focused. Update `Application` accessors if you change configuration schema used by the monitor or UI.
- Follow GNOME HIG and prefer libadwaita (`Adw`) widgets.
- Vala conventions: use PascalCase for classes, snake_case for methods/variables.
- Test both GUI and monitor script functionality when making changes.

Troubleshooting for contributors
- If build fails, ensure development packages for GTK4, libadwaita, json-glib, and jq are installed.
- Use `meson setup builddir --wipe` to reconfigure from scratch if needed.
- Monitor script issues: Check `~/.local/bin/switchcraft-monitor.sh` exists and is executable.
- Theme detection issues: Test with `gsettings monitor org.gnome.desktop.interface color-scheme`.

**Updated: 2025-10-28** - Refactored to use independent bash monitor script instead of in-app ThemeMonitor. Added ninja install/remove targets.
