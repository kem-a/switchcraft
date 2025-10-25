<!-- Guidance for AI coding agents working on the Switchcraft repo. -->

# Copilot instructions — Switchcraft

Short, focused guidance for contributors and automated agents working on this small GNOME/libadwaita desktop app written in Vala.

What the app does
- Watches GNOME's `org.gnome.desktop.interface` `color-scheme` and runs user-defined shell commands when the preference flips between light and dark.

Key files
- `src/main.vala` — application entrypoint; creates `Application` and `ThemeMonitor`.
- `src/Application.vala` — main application class; canonical accessor for configuration. Use `get_commands()` / `save_commands()` to read/write the runtime config located at `~/.config/switchcraft/commands.json`.
- `src/ThemeMonitor.vala` — watches the GNOME setting and runs enabled commands using shell execution.
- `src/MainWindow.vala` — UI (libadwaita) implementation and wiring to `Application` for persistence.
- `src/ConstantsWindow.vala` — constants management UI for user-defined variables.
- `meson.build` — build system configuration.

Development notes
- Build with: `meson setup builddir && meson compile -C builddir`
- Run locally with: `./builddir/switchcraft`
- Vala compiler, GTK4, libadwaita, and json-glib development headers are required. Install these via your distro package manager — see `README.md` for examples.

Design and architecture constraints
- Single-process GTK app; prefer GLib/Gio signals and the GTK main loop.
- Keep UI code in `MainWindow.vala` and `ConstantsWindow.vala`, app-level state/persistence in `Application.vala`.
- Commands are intentionally executed with full shell support to allow arbitrary shell syntax — do not change this without documenting the reason.

When making changes
- Keep patches small and focused. Update `Application` accessors if you change configuration schema used by the monitor or UI.
- Follow GNOME HIG and prefer libadwaita (`Adw`) widgets.
- Vala conventions: use PascalCase for classes, snake_case for methods/variables.

Troubleshooting for contributors
- If build fails with missing dependencies, ensure development packages for GTK4, libadwaita, and json-glib are installed.
- Use `meson setup builddir --wipe` to reconfigure from scratch if needed.

If you update these instructions, leave a short note in the file explaining why.
