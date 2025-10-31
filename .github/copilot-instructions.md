<!-- Guidance for AI coding agents working on the Switchcraft repo. -->

# Copilot instructions — Switchcraft

Concise, actionable guidance for automated agents and contributors working on this small GNOME/libadwaita desktop app written in Vala.

What this app does
- Watches GNOME's `org.gnome.desktop.interface color-scheme` and runs user-defined shell commands when the preference switches between light and dark.
- Two-component runtime: a GTK GUI for configuration and an independent Bash monitor script for execution (`switchcraft-monitor.sh`).

Most important files
- `src/Application.vala` — persistence, monitor install/remove, and helpers. Primary API: `get_commands()` / `save_commands()`, `get_constants()` / `save_constants()`, and `set_monitoring_enabled(bool)`.
- `src/MainWindow.vala` — UI wiring (libadwaita) to the `Application` class.
- `src/ConstantsWindow.vala` — UI for managing `constants.json`.
- `switchcraft-monitor.sh` — standalone monitor script that is installed to `~/.local/bin/switchcraft-monitor.sh` when monitoring is enabled. It uses `jq` and `gsettings monitor`.
- `meson.build` — build/install targets (`ninja -C builddir install` / `remove`).

Quick dev commands (repo root)
```
# configure for user install into ~/.local
meson setup builddir --prefix="$HOME/.local"
meson compile -C builddir
./builddir/switchcraft
# install
ninja -C builddir install
ninja -C builddir remove
```

Design constraints & runtime behavior you must preserve
- Two-component separation: GUI manages configuration and installs/starts/stops the monitor script; the monitor script handles theme-watching and command execution independently.
- Commands are executed by the shell to allow redirection/pipelines/expansion. The monitor script uses `eval` to run commands — keep that explicit behavior in mind when changing execution flow.
- Monitor installation: `Application.install_monitor_script()` locates `switchcraft-monitor.sh` via MESON_SOURCE_ROOT, data dirs, or the executable path, then copies it to `~/.local/bin` and sets 0755.
- Autostart: `Application.create_autostart_entry()` writes `~/.config/autostart/switchcraft-monitor.desktop` with Exec pointing to the installed script and an autostart delay.

Data layout and formats (examples)
- `~/.config/switchcraft/commands.json` — per-theme arrays. Supported item forms:
  - String shorthand: "notify-send 'Hi'"
  <!-- Guidance for AI coding agents working on the Switchcraft repo. -->

  # Copilot instructions — Switchcraft

  Concise, actionable guidance for automated agents and contributors working on this small GNOME/libadwaita desktop app written in Vala.

  What this app does
  - Watches GNOME's `org.gnome.desktop.interface color-scheme` and runs user-defined shell commands when the preference switches between light and dark.
  - Two-component runtime: a GTK GUI for configuration and an independent Bash monitor script for execution (`switchcraft-monitor.sh`).

  Most important files
  - `src/Application.vala` — persistence, monitor install/remove, and helpers. Primary API: `get_commands()` / `save_commands()`, `get_constants()` / `save_constants()`, and `set_monitoring_enabled(bool)`.
  - `src/MainWindow.vala` — UI wiring (libadwaita) to the `Application` class.
  - `src/ConstantsWindow.vala` — UI for managing `constants.json`.
  - `switchcraft-monitor.sh` — standalone monitor script that is installed to `~/.local/bin/switchcraft-monitor.sh` when monitoring is enabled. It uses `jq` and `gsettings monitor`.
  - `meson.build` — build/install targets (`ninja -C builddir install` / `remove`).

  Quick dev commands (repo root)
  ```
  # configure for user install into ~/.local
  meson setup builddir --prefix="$HOME/.local"
  meson compile -C builddir
  ./builddir/switchcraft
  # install
  ninja -C builddir install
  ninja -C builddir remove
  ```

  Design constraints & runtime behavior you must preserve
  - Two-component separation: GUI manages configuration and installs/starts/stops the monitor script; the monitor script handles theme-watching and command execution independently.
  - Commands are executed by the shell to allow redirection/pipelines/expansion. The monitor script uses `eval` to run commands — keep that explicit behavior in mind when changing execution flow.
  - Monitor installation: `Application.install_monitor_script()` locates `switchcraft-monitor.sh` via MESON_SOURCE_ROOT, data dirs, or the executable path, then copies it to `~/.local/bin` and sets 0755.
  - Autostart: `Application.create_autostart_entry()` writes `~/.config/autostart/switchcraft-monitor.desktop` with Exec pointing to the installed script and an autostart delay.

  Data layout and formats (examples)
  - `~/.config/switchcraft/commands.json` — per-theme arrays. Supported item forms:
    - String shorthand: "notify-send 'Hi'"
    - Object: { "command": "...", "enabled": true }
    Application.normalize_commands accepts both; preserve that flexibility.
  - `~/.config/switchcraft/constants.json` — flat object of key->string. Monitor script exports and expands these into environment variables (watch quoting/expansion behavior).
  - `~/.config/switchcraft/settings.json` — e.g. { "monitoring_enabled": true }

  Codebase patterns & conventions
  - Vala style: PascalCase for classes, snake_case for methods/variables (follow existing `Application.vala`).
  - Keep UI code in `MainWindow.vala` / `ConstantsWindow.vala`. Persisting/IO logic belongs in `Application.vala`.
  - Small, focused patches. If you change schema or keys, update `Application` accessors and the monitor script logic accordingly.

  Integration points & external deps
  - Runtime: `gsettings` (GNOME), `jq` (monitor script), `gsettings monitor` (blocking stream). Ensure `jq` is available when testing the script.
  - The monitor script uses `XDG_CONFIG_HOME` fallback to `$HOME/.config`; `Application` uses GLib paths and writes into the same directory.

  Concrete examples to reference when editing
  - Read/save commands: `Application.get_commands()` / `Application.save_commands()` (look at `normalize_commands` and `normalize_commands_to_json`).
  - Start/stop monitor: `Application.set_monitoring_enabled(bool)` → `enable_monitoring()` / `disable_monitoring()` which calls `install_monitor_script()` and uses `Process.spawn_async` and `pkill -f switchcraft-monitor.sh`.
  - Where the packaged monitor is found: `find_monitor_script_source()` contains multiple fallbacks (user data dir, system data dirs, MESON_SOURCE_ROOT, current dir, sibling share paths).

  Edge cases & gotchas
  - `commands.json` supports both string and object entries — preserve both reading/writing behavior.
  - `constants.json` values are expanded by `switchcraft-monitor.sh` using `eval`; improper quoting can lead to unintended expansions. Test variable escapes.
  - `gsettings monitor` is blocking — do not change monitor logic without validating autostart, process management, and the `pkill` cleanup path.

  Testing and debugging tips
  - To debug monitoring outside the GUI, run `~/.local/bin/switchcraft-monitor.sh` directly (ensure `jq` is installed and config files are present).
  - Use `gsettings get org.gnome.desktop.interface color-scheme` and `gsettings monitor org.gnome.desktop.interface color-scheme` to simulate/observe changes.
  - Rebuild if native deps change: `meson setup builddir --wipe` then `meson compile -C builddir`.

  When making changes
  - Update `src/Application.vala` accessors when changing schema or runtime file locations.
  - Keep UI changes within libadwaita patterns used in `MainWindow.vala` and `ConstantsWindow.vala`.

  Resources and follow-ups
  - README.md contains detailed build instructions and examples (see `samples/` for command templates).
  - `ARCHITECTURE.md` and `samples/` include longer examples and are helpful when modifying cross-cutting behavior.

  ---
  If anything above is unclear or you'd like more examples (JSON samples, monitor script flows, or exact call sites), tell me what to expand and I'll iterate.
