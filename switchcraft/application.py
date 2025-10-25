import copy
import json
import os
from typing import Any, Dict, List

from gi.repository import Adw, Gio

from .window import MainWindow

CONFIG_PATH = os.path.expanduser("~/.config/switchcraft/commands.json")


class SwitchcraftApp(Adw.Application):
    def __init__(self):
        super().__init__(
            application_id="io.github.switchcraft.Switchcraft",
            flags=Gio.ApplicationFlags.FLAGS_NONE,
        )
        self.set_resource_base_path("/io/github/switchcraft/Switchcraft/")
        self.set_accels_for_action("win.add-command", ["<Primary>N"])
        self.set_accels_for_action("app.quit", ["<Primary>Q"])
        
        # Add quit action
        quit_action = Gio.SimpleAction.new("quit", None)
        quit_action.connect("activate", lambda *_: self.quit())
        self.add_action(quit_action)

    def do_activate(self):
        win = MainWindow(application=self)
        win.present()

    def get_commands(self) -> Dict[str, List[Dict[str, Any]]]:
        if not os.path.exists(CONFIG_PATH):
            return self._default_commands()

        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as handle:
                raw = json.load(handle)
        except (json.JSONDecodeError, OSError):
            return self._default_commands()

        return self._normalize_commands(raw)

    def save_commands(self, commands: Dict[str, Any]) -> None:
        normalized = self._normalize_commands(commands)
        os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
        with open(CONFIG_PATH, "w", encoding="utf-8") as handle:
            json.dump(normalized, handle, indent=2)

    def _default_commands(self) -> Dict[str, List[Dict[str, Any]]]:
        return {"dark": [], "light": []}

    def _normalize_commands(self, raw: Dict[str, Any]) -> Dict[str, List[Dict[str, Any]]]:
        normalized = self._default_commands()
        if not isinstance(raw, dict):
            return normalized

        for theme in normalized.keys():
            entries = raw.get(theme, [])
            theme_commands: List[Dict[str, Any]] = []

            if isinstance(entries, list):
                for entry in entries:
                    if isinstance(entry, str):
                        theme_commands.append({"command": entry, "enabled": True})
                        continue

                    if not isinstance(entry, dict):
                        continue

                    command = entry.get("command")
                    if not command or not isinstance(command, str):
                        continue

                    enabled = bool(entry.get("enabled", True))
                    theme_commands.append({"command": command, "enabled": enabled})

            normalized[theme] = theme_commands

        return copy.deepcopy(normalized)
