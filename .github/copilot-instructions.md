<!-- Guidance for AI coding agents working on the Switchcraft repo. -->

# Copilot instructions — Switchcraft

Concise, actionable guidance for automated agents and contributors working on this GNOME/libadwaita desktop app written in Vala.

What this app does
- Watches GNOME's `org.gnome.desktop.interface color-scheme` and runs user-defined shell commands when the preference switches between light and dark.
- Two-component runtime: a GTK GUI for configuration and an independent Bash monitor script for execution (`switchcraft-monitor.sh`).

Most important files
- `src/Application.vala` — persistence, monitor install/remove, helpers, and import/export routines for commands/constants.
- `src/MainWindow.vala` — primary UI wiring to `Application`; handles command lists and shows modals.
- `src/PreferencesWindow.vala` — preferences dialog for monitor enablement and import/export actions.
- `src/ConstantsWindow.vala` — constants.json management UI.
- `switchcraft-monitor.sh` — standalone monitor script installed to `~/.local/bin/switchcraft-monitor.sh` when monitoring is enabled.
- `meson.build` — build/install targets (`ninja -C builddir install` / `remove`).

Development environment
- Work inside the `toolbox` container before building or running commands. Activate with `toolbox enter` in the repo root.
- Configure for user installs into `~/.local`:
  ```
  meson setup builddir --prefix="$HOME/.local"
  meson compile -C builddir
  ./builddir/switchcraft
  ```

Design constraints & behavior
- Keep GUI/monitor separation: the GTK app manages configuration and installs/starts/stops the monitor script; the Bash script handles theme watching and execution.
- Commands run through the shell via `eval` in the monitor script; maintain quoting/expansion behavior.
- Monitor installation: `Application.install_monitor_script()` resolves the packaged script location, copies it into `~/.local/bin`, and sets mode 0755.
- Autostart: `Application.create_autostart_entry()` writes `~/.config/autostart/switchcraft-monitor.desktop` with the installed script and delay.

Data layout and formats
- `~/.local/share/switchcraft/commands.json` — per-theme arrays supporting string or `{ "command", "enabled" }` objects; `Application.normalize_commands()` accepts both.
- `~/.local/share/switchcraft/constants.json` — flat key/value map; monitor exports as environment variables, so watch quoting.
- **GSettings** — app settings (e.g., `monitoring-enabled`) are stored in dconf under `com.github.switchcraft.Switchcraft`.

Code patterns & expectations
- Vala style: PascalCase classes, snake_case methods/variables (follow `Application.vala`).
- UI code belongs in `MainWindow.vala`, `PreferencesWindow.vala`, or `ConstantsWindow.vala`; persistence/IO stays in `Application.vala`.
- When altering schema or on-disk layout, update `Application` accessors and the monitor script accordingly.

Testing & debug tips
- Run `~/.local/bin/switchcraft-monitor.sh` directly (ensure `jq` present) to test monitoring logic.
- Use `gsettings monitor org.gnome.desktop.interface color-scheme` to observe live theme changes.
- Rebuild after dependency changes with `meson setup builddir --wipe` followed by `meson compile -C builddir`.

Resources
- README.md has build instructions and JSON samples (see `samples/`).
- `ARCHITECTURE.md` documents component boundaries.
