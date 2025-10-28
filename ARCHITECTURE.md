# Switchcraft Architecture

## How It Works (Post-Refactor)

Switchcraft now uses a **separate bash monitoring script** to watch for GNOME theme changes and execute user commands. This ensures commands run reliably without requiring the main GUI application to stay open.

### Components

1. **Main Application (`switchcraft`)** - GTK4/libadwaita GUI
   - Manages command configuration via `~/.config/switchcraft/commands.json`
   - Controls the Monitor toggle which enables/disables the background script
   - Manages constants in `~/.config/switchcraft/constants.json`

2. **Monitor Script (`switchcraft-monitor.sh`)** - Background daemon
   - **Embedded in the application** and installed to `~/.local/bin/switchcraft-monitor.sh` when monitoring is first enabled
   - Watches `org.gnome.desktop.interface color-scheme` using `gsettings monitor`
   - Reads commands from `commands.json` and executes enabled ones
   - Expands constants from `constants.json` as environment variables
   - Runs in the background, independent of the GUI
   - **Per-user**: Each user has their own copy in their home directory

3. **Autostart Entry** - `~/.config/autostart/switchcraft-monitor.desktop`
   - Created/removed when Monitor toggle is switched
   - Launches the monitor script on login
   - Only exists when monitoring is enabled

### Monitor Toggle Behavior

When you **enable** monitoring:
- Installs monitor script to `~/.local/bin/switchcraft-monitor.sh` (if not already present)
- Creates autostart desktop entry in `~/.config/autostart/`
- Starts the monitor script immediately (no need to log out)
- Shows banner: "Log out and back in to start background monitoring" (for persistence)

When you **disable** monitoring:
- Removes autostart desktop entry
- Kills any running monitor script processes
- Commands will no longer execute on theme changes

### Command Execution Flow

```
GNOME theme changes
    ↓
gsettings monitor detects change
    ↓
switchcraft-monitor.sh reads commands.json
    ↓
Loads constants.json and exports as env vars
    ↓
Executes enabled commands for current theme (light/dark)
    ↓
Each command runs in background with full shell support
```

### Why This Architecture?

**Previous design**: Main app (`switchcraft --background`) had to run constantly to monitor theme changes via GSettings in Vala.

**Problem**: If the app crashed or wasn't started, commands wouldn't execute.

**New design**: Bash script runs independently, using standard GNOME tools (`gsettings monitor`).

**Benefits**:
- More reliable (follows the pattern in `samples/extension-theme-switcher`)
- Simpler to debug (pure bash + jq)
- Lower resource usage (no GTK app running in background)
- Commands execute even if GUI is closed
- **Per-user installation**: No need for system-wide installation or root privileges
- Works whether app is installed globally or run locally

### Files

- `src/Application.vala` - Embeds monitor script and installs to `~/.local/bin` on first enable
- `src/main.vala` - Simplified (removed --background mode)
- `src/ThemeMonitor.vala` - ⚠️ Still exists but **not used** (can be removed)
- `meson.build` - Simplified (no longer installs monitor script separately)

### Dependencies

The monitor script requires:
- `bash` (or `zsh`)
- `jq` - for JSON parsing
- `gsettings` - for monitoring theme changes
- `pkill` - for stopping the monitor process

### Configuration Files

All config stored in `~/.config/switchcraft/`:
- `commands.json` - User commands for light/dark themes
- `constants.json` - User-defined variables
- `settings.json` - App settings (monitoring enabled state)

### Future Improvements

- Remove unused `ThemeMonitor.vala` completely
- Add better error handling if `jq` is not installed
- Show warning in UI if dependencies are missing
