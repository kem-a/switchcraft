import sys
import gi


gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from .application import SwitchcraftApp
from .monitor import ThemeMonitor


def main(argv: list[str] | None = None) -> int:
    app = SwitchcraftApp()
    ThemeMonitor(app)
    
    # Background mode: keep app alive without showing window
    args = argv or sys.argv
    if "--background" in args:
        app.hold()  # Prevent app from exiting when no windows are open
        # Remove --background from argv so GApplication doesn't complain
        args = [arg for arg in args if arg != "--background"]
    
    return app.run(args)


if __name__ == "__main__":
    raise SystemExit(main())
