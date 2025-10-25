import subprocess
import os
from typing import Any

from gi.repository import Gio


class ThemeMonitor:
    def __init__(self, app):
        self.app = app
        self.settings = Gio.Settings.new("org.gnome.desktop.interface")
        self.settings.connect("changed::color-scheme", self.on_theme_changed)
        # Don't execute commands on startup, only on theme changes

    def on_theme_changed(self, settings, _key):
        color_scheme = settings.get_string("color-scheme")
        theme = "dark" if color_scheme == "prefer-dark" else "light"

        # Get user-defined constants for substitution
        constants = self.app.get_constants()

        commands = self.app.get_commands().get(theme, [])
        for entry in commands:
            command = self._extract_command(entry)
            if command is None:
                continue
            
            # Substitute constants in the command
            expanded_command = self._expand_constants(command, constants)
            subprocess.Popen(expanded_command, shell=True, env=self._build_env(constants))

    def _extract_command(self, entry: Any) -> str | None:
        if isinstance(entry, str):
            return entry

        if isinstance(entry, dict):
            if not entry.get("enabled", True):
                return None
            command = entry.get("command")
            return command if isinstance(command, str) else None

        return None

    def _expand_constants(self, command: str, constants: dict[str, str]) -> str:
        """Expand user-defined constants in command string."""
        expanded = command
        for key, value in constants.items():
            # Support both $VAR and ${VAR} syntax
            expanded = expanded.replace(f"${key}", value)
            expanded = expanded.replace(f"${{{key}}}", value)
        return expanded

    def _build_env(self, constants: dict[str, str]) -> dict[str, str]:
        """Build environment with constants as environment variables."""
        env = os.environ.copy()
        env.update(constants)
        return env
