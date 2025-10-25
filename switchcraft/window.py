import copy
from typing import Any, Dict, List

from gi.repository import Adw, Gio, GLib, GObject, Gtk

from switchcraft.constants_window import ConstantsWindow


THEME_ICONS = {
    "light": "weather-clear-symbolic",
    "dark": "weather-clear-night-symbolic",
}


class MainWindow(Adw.ApplicationWindow):
    def __init__(self, application):
        super().__init__(application=application)
        self.set_title("Switchcraft")
        self.set_default_size(640, 480)

        self._commands: Dict[str, List[Dict[str, Any]]] = copy.deepcopy(
            application.get_commands()
        )
        self._listboxes: Dict[str, Gtk.ListBox] = {}
        self._content_stacks: Dict[str, Gtk.Stack] = {}
        self._shortcuts_window: Gtk.ShortcutsWindow | None = None
        self._banner: Adw.Banner | None = None

        for theme in ("light", "dark"):
            self._commands.setdefault(theme, [])

        self.__build_ui()

    def __build_ui(self) -> None:
        # Create breakpoint for narrow windows
        breakpoint = Adw.Breakpoint.new(Adw.breakpoint_condition_parse("max-width: 550sp"))
        
        toolbar_view = Adw.ToolbarView()
        header_bar = Adw.HeaderBar()
        toolbar_view.add_top_bar(header_bar)

        self._add_action("add-command", self._on_add_command_action)
        self._add_action("show-about", self._on_show_about_action)
        self._add_action("show-constants", self._on_show_constants_action)
        self._add_action("show-shortcuts", self._on_show_shortcuts_action)

        self._add_button = Gtk.Button()
        self._add_button.set_icon_name("list-add-symbolic")
        self._add_button.set_tooltip_text("Add Command")
        self._add_button.add_css_class("flat")
        self._add_button.set_action_name("win.add-command")
        header_bar.pack_start(self._add_button)

        # Menu button should be last (rightmost)
        menu_button = Gtk.MenuButton()
        menu_button.set_icon_name("open-menu-symbolic")
        menu = Gio.Menu()
        menu.append("Constants", "win.show-constants")
        menu.append("Keyboard Shortcuts", "win.show-shortcuts")
        menu.append("About Switchcraft", "win.show-about")
        menu.append("Quit", "app.quit")
        menu_button.set_menu_model(menu)
        header_bar.pack_end(menu_button)

        # Monitoring toggle switch (before menu button)
        application = self.get_application()
        monitoring_switch = Gtk.Switch()
        monitoring_switch.set_valign(Gtk.Align.CENTER)
        monitoring_switch.set_tooltip_text("Enable background monitoring")
        if application:
            monitoring_switch.set_active(application.get_monitoring_enabled())
        monitoring_switch.connect("state-set", self._on_monitoring_toggled)
        
        monitoring_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        monitoring_box.set_valign(Gtk.Align.CENTER)
        monitoring_label = Gtk.Label(label="Monitor")
        monitoring_box.append(monitoring_label)
        monitoring_box.append(monitoring_switch)
        header_bar.pack_end(monitoring_box)

        self._view_stack = Adw.ViewStack()
        
        # Create view switcher for header (visible on wide windows)
        view_switcher = Adw.ViewSwitcher()
        view_switcher.set_stack(self._view_stack)
        view_switcher.set_policy(Adw.ViewSwitcherPolicy.WIDE)
        header_bar.set_title_widget(view_switcher)
        
        # Create banner for logout notification
        self._banner = Adw.Banner()
        self._banner.set_title("Log out and back in to start background monitoring")
        self._banner.set_button_label("Log Out")
        self._banner.connect("button-clicked", self._on_banner_logout_clicked)
        self._banner.set_revealed(False)
        
        # Create content box with banner and view stack
        content_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        content_box.append(self._banner)
        content_box.append(self._view_stack)
        
        toolbar_view.set_content(content_box)

        supports_icon = hasattr(self._view_stack, "add_titled_with_icon")

        for theme in ("light", "dark"):
            page = self.__build_theme_page(theme)
            icon_name = THEME_ICONS.get(theme)

            if supports_icon and icon_name:
                self._view_stack.add_titled_with_icon(
                    page, theme, theme.capitalize(), icon_name
                )
            else:
                stack_page = self._view_stack.add_titled(
                    page, theme, theme.capitalize()
                )
                if icon_name:
                    stack_page.set_icon_name(icon_name)

        self._view_stack.connect("notify::visible-child-name", self._on_visible_theme)
        self._update_add_button_tooltip()

        # Create view switcher bar for bottom (visible on narrow windows)
        switcher_bar = Adw.ViewSwitcherBar()
        switcher_bar.set_stack(self._view_stack)
        toolbar_view.add_bottom_bar(switcher_bar)
        
        # Configure breakpoint: on narrow windows, show bottom bar and remove header switcher
        breakpoint.add_setter(switcher_bar, "reveal", GObject.Value(GObject.TYPE_BOOLEAN, True))
        breakpoint.add_setter(header_bar, "title-widget", GObject.Value(GObject.TYPE_OBJECT, None))
        self.add_breakpoint(breakpoint)

        self.set_content(toolbar_view)

    def __build_theme_page(self, theme: str) -> Gtk.Widget:
        page_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        page_box.set_margin_top(24)
        page_box.set_margin_bottom(24)
        page_box.set_margin_start(24)
        page_box.set_margin_end(24)

        description = Gtk.Label(
            label="Commands run when GNOME switches to the %s theme." % theme,
            xalign=0,
        )
        description.set_wrap(True)
        description.add_css_class("body")
        page_box.append(description)

        listbox = Gtk.ListBox()
        listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        listbox.add_css_class("boxed-list")

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_hexpand(True)
        scrolled.set_vexpand(True)
        scrolled.set_child(listbox)

        placeholder = Adw.StatusPage()
        placeholder.set_icon_name("list-add-symbolic")
        placeholder.set_title("No commands yet")
        placeholder.set_description(
            "Click the + button or (Ctrl+N) to add a shell command that runs when %s theme activates" % theme
        )

        stack = Gtk.Stack()
        stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        stack.set_hexpand(True)
        stack.set_vexpand(True)
        stack.add_named(scrolled, "list")
        stack.add_named(placeholder, "placeholder")

        page_box.append(stack)

        self._listboxes[theme] = listbox
        self._content_stacks[theme] = stack
        self._refresh_theme_list(theme)

        return page_box

    def _refresh_theme_list(self, theme: str) -> None:
        listbox = self._listboxes[theme]
        stack = self._content_stacks[theme]

        row = listbox.get_row_at_index(0)
        while row is not None:
            listbox.remove(row)
            row = listbox.get_row_at_index(0)

        for entry in self._commands.get(theme, []):
            listbox.append(self.__create_command_row(theme, entry))

        has_commands = bool(self._commands.get(theme))
        stack.set_visible_child_name("list" if has_commands else "placeholder")

    def __create_command_row(self, theme: str, entry: Dict[str, Any]) -> Adw.ActionRow:
        command_text = entry.get("command", "")
        row = Adw.ActionRow(title=command_text)
        row.set_activatable(False)

        toggle = Gtk.Switch()
        toggle.set_valign(Gtk.Align.CENTER)
        toggle.set_active(entry.get("enabled", True))
        toggle.set_tooltip_text("Enable or disable this command")
        toggle.connect("state-set", self._on_toggle_command_state, theme, row)
        row.add_suffix(toggle)

        controls_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        controls_box.set_valign(Gtk.Align.CENTER)

        edit_button = Gtk.Button.new_from_icon_name("document-edit-symbolic")
        edit_button.add_css_class("flat")
        edit_button.set_tooltip_text("Edit command")
        edit_button.connect("clicked", self._on_edit_command_clicked, theme, row)
        controls_box.append(edit_button)

        remove_button = Gtk.Button.new_from_icon_name("user-trash-symbolic")
        remove_button.add_css_class("flat")
        remove_button.set_tooltip_text("Remove command")
        remove_button.connect("clicked", self._on_remove_command_clicked, theme, row)
        controls_box.append(remove_button)

        row.add_suffix(controls_box)

        self._update_row_state(row, entry)
        return row

    def _update_row_state(self, row: Adw.ActionRow, entry: Dict[str, Any]) -> None:
        enabled = entry.get("enabled", True)
        row.set_subtitle("" if enabled else "Disabled")
        if enabled:
            row.remove_css_class("dim-label")
        else:
            row.add_css_class("dim-label")

    def _on_toggle_command_state(
        self,
        switch: Gtk.Switch,
        state: bool,
        theme: str,
        row: Gtk.ListBoxRow,
    ) -> bool:
        index = row.get_index()
        if index < 0:
            return False

        commands = self._commands.get(theme, [])
        if 0 <= index < len(commands):
            commands[index]["enabled"] = bool(state)
            self._update_row_state(row, commands[index])
            self._save_commands()

        return False

    def _on_add_command_action(self, _action, _param) -> None:
        theme = self._current_theme()
        self._show_command_dialog(theme)

    def _on_edit_command_clicked(self, _button, theme: str, row: Gtk.ListBoxRow) -> None:
        index = row.get_index()
        if index < 0:
            return
        self._show_command_dialog(theme, index)

    def _on_remove_command_clicked(self, _button, theme: str, row: Gtk.ListBoxRow) -> None:
        index = row.get_index()
        if index < 0:
            return

        commands = self._commands.get(theme, [])
        if 0 <= index < len(commands):
            del commands[index]
            self._save_commands()

        self._refresh_theme_list(theme)

    def _show_command_dialog(self, theme: str, index: int | None = None) -> None:
        editing = index is not None
        title = "Edit Command" if editing else "Add Command"
        message = (
            "Update the shell command executed for the %s theme." % theme
            if editing
            else "Enter the shell command to run when the %s theme activates." % theme
        )

        dialog = Adw.MessageDialog.new(self, title, message)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("save", "Save" if editing else "Add")
        dialog.set_default_response("save")
        dialog.set_response_appearance("save", Adw.ResponseAppearance.SUGGESTED)

        entry = Gtk.Entry()
        entry.set_placeholder_text(
            "e.g. notify-send 'Switched to %s theme'" % theme.capitalize()
        )
        if editing:
            commands = self._commands.get(theme, [])
            if 0 <= index < len(commands):
                entry.set_text(commands[index].get("command", ""))
        dialog.set_extra_child(entry)

        dialog.connect(
            "response",
            self._on_command_dialog_response,
            theme,
            index,
            entry,
        )
        dialog.present()

        def _focus_entry() -> bool:
            entry.grab_focus()
            return False

        GLib.idle_add(_focus_entry)

    def _on_command_dialog_response(
        self,
        dialog: Adw.MessageDialog,
        response: str,
        theme: str,
        index: int | None,
        entry: Gtk.Entry,
    ) -> None:
        try:
            if response != "save":
                return

            command_text = entry.get_text().strip()
            if not command_text:
                return

            commands = self._commands.setdefault(theme, [])

            if index is None:
                commands.append({"command": command_text, "enabled": True})
            elif 0 <= index < len(commands):
                commands[index]["command"] = command_text

            self._save_commands()
            self._refresh_theme_list(theme)
        finally:
            dialog.destroy()

    def _add_action(self, name: str, callback) -> None:
        action = Gio.SimpleAction.new(name, None)
        action.connect("activate", callback)
        self.add_action(action)

    def _on_visible_theme(self, *_args) -> None:
        self._update_add_button_tooltip()

    def _update_add_button_tooltip(self) -> None:
        theme = self._current_theme()
        tooltip = "Add a command for the %s theme" % theme
        self._add_button.set_tooltip_text(tooltip)

    def _current_theme(self) -> str:
        name = self._view_stack.get_visible_child_name()
        return name if name in ("light", "dark") else "light"

    def _on_show_about_action(self, _action, _param) -> None:
        dialog = Adw.AboutDialog()
        dialog.set_application_name("Switchcraft")
        dialog.set_developer_name("Switchcraft Contributors")
        dialog.set_version("1.0")
        dialog.present(self)

    def _on_show_shortcuts_action(self, _action, _param) -> None:
        if self._shortcuts_window is None:
            self._shortcuts_window = self._build_shortcuts_window()

        self._shortcuts_window.present()

    def _on_show_constants_action(self, _action, _param) -> None:
        application = self.get_application()
        if application is None:
            return

        constants_window = ConstantsWindow(application, self)
        constants_window.present()

    def _on_monitoring_toggled(self, switch: Gtk.Switch, state: bool) -> bool:
        """Handle monitoring toggle state change."""
        application = self.get_application()
        if application is None:
            return False

        application.set_monitoring_enabled(state)
        
        # Show banner when enabling, hide when disabling
        if self._banner:
            if state:
                self._banner.set_revealed(True)
            else:
                self._banner.set_revealed(False)
        
        return False  # Allow the switch to change state

    def _on_banner_logout_clicked(self, _banner) -> None:
        """Trigger GNOME logout when banner button is clicked."""
        try:
            # Use D-Bus to call GNOME Session Manager logout
            # Mode 0 = no confirmation dialog
            bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            bus.call_sync(
                "org.gnome.SessionManager",
                "/org/gnome/SessionManager",
                "org.gnome.SessionManager",
                "Logout",
                GLib.Variant("(u)", (0,)),  # 0 = logout without prompt
                None,
                Gio.DBusCallFlags.NONE,
                -1,
                None
            )
        except Exception as e:
            print(f"Failed to logout: {e}")
            # Fall back to just hiding the banner
            self._banner.set_revealed(False)

    def _build_shortcuts_window(self) -> Gtk.ShortcutsWindow:
        window = Gtk.ShortcutsWindow()
        window.set_transient_for(self)
        window.set_modal(True)

        section = Gtk.ShortcutsSection()
        section.props.title = "General"

        group = Gtk.ShortcutsGroup()
        group.props.title = "Switchcraft"

        add_shortcut = Gtk.ShortcutsShortcut()
        add_shortcut.props.title = "Add command"
        add_shortcut.props.accelerator = "<Primary>N"

        quit_shortcut = Gtk.ShortcutsShortcut()
        quit_shortcut.props.title = "Quit"
        quit_shortcut.props.accelerator = "<Primary>Q"

        group.add_shortcut(add_shortcut)
        group.add_shortcut(quit_shortcut)
        section.add_group(group)
        window.add_section(section)

        return window

    def _save_commands(self) -> None:
        application = self.get_application()
        if application is None:
            return
        application.save_commands(self._commands)
