import subprocess
from typing import Any

from gi.repository import Gio


class ThemeMonitor:
    def __init__(self, app):
        self.app = app
        self.settings = Gio.Settings.new("org.gnome.desktop.interface")
        self.settings.connect("changed::color-scheme", self.on_theme_changed)
        self.on_theme_changed(self.settings, None)

    def on_theme_changed(self, settings, _key):
        color_scheme = settings.get_string("color-scheme")
        theme = "dark" if color_scheme == "prefer-dark" else "light"

        commands = self.app.get_commands().get(theme, [])
        for entry in commands:
            command = self._extract_command(entry)
            if command is None:
                continue
            subprocess.Popen(command, shell=True)

    def _extract_command(self, entry: Any) -> str | None:
        if isinstance(entry, str):
            return entry

        if isinstance(entry, dict):
            if not entry.get("enabled", True):
                return None
            command = entry.get("command")
            return command if isinstance(command, str) else None

        return None
