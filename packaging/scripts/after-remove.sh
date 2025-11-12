#!/usr/bin/env bash
# Post-uninstall cleanup for switchcraft monitor artifacts
# Runs as root during package removal

# Clean up per-user artifacts created when monitoring was enabled.
cleanup_user_state() {
    local username="$1"
    local home_dir="$2"

    if [[ -z "$home_dir" || ! -d "$home_dir" ]]; then
        return 0
    fi

    local autostart_entry="$home_dir/.config/autostart/switchcraft-monitor.desktop"
    local monitor_script="$home_dir/.local/bin/switchcraft-monitor.sh"

    # Remove autostart entry and monitor script if present.
    rm -f "$autostart_entry" 2>/dev/null || true
    rm -f "$monitor_script" 2>/dev/null || true

    # Stop any remaining monitor processes for this user if pkill is available.
    if command -v pkill >/dev/null 2>&1; then
        pkill -u "$username" -f switchcraft-monitor.sh >/dev/null 2>&1 || true
    fi
}

# Attempt to clean up for the invoking sudo user first.
if [[ -n "${SUDO_USER:-}" ]]; then
    sudo_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || true)
    if [[ -n "$sudo_home" ]]; then
        cleanup_user_state "$SUDO_USER" "$sudo_home"
    fi
fi

# Fall back to iterating through all non-system users with homes under /home.
if command -v getent >/dev/null 2>&1; then
    while IFS=: read -r user _ uid _ _ home _; do
        if (( uid >= 1000 )) && [[ -d "$home" ]]; then
            cleanup_user_state "$user" "$home"
        fi
    done < <(getent passwd 2>/dev/null || true)
fi

exit 0
