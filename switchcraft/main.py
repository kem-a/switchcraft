import sys
import gi


gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from .application import SwitchcraftApp
from .monitor import ThemeMonitor


def main(argv: list[str] | None = None) -> int:
    app = SwitchcraftApp()
    ThemeMonitor(app)
    return app.run(argv or sys.argv)


if __name__ == "__main__":
    raise SystemExit(main())
