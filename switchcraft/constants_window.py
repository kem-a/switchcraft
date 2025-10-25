"""Constants management window for Switchcraft."""
from typing import Dict

from gi.repository import Adw, Gtk, Gio


class ConstantsWindow(Adw.Window):
    """Window for managing user-defined constants."""

    def __init__(self, application, parent):
        super().__init__()
        self.set_title("Constants")
        self.set_default_size(600, 400)
        self.set_transient_for(parent)
        self.set_modal(True)
        
        self._app = application
        self._constants: Dict[str, str] = {}
        self._listbox: Gtk.ListBox | None = None
        self._content_stack: Gtk.Stack | None = None
        
        self.__build_ui()
        self._load_constants()

    def __build_ui(self):
        toolbar_view = Adw.ToolbarView()
        
        header_bar = Adw.HeaderBar()
        toolbar_view.add_top_bar(header_bar)
        
        add_button = Gtk.Button()
        add_button.set_icon_name("list-add-symbolic")
        add_button.set_tooltip_text("Add Constant")
        add_button.add_css_class("flat")
        add_button.connect("clicked", self._on_add_constant)
        header_bar.pack_start(add_button)
        
        # Main content area
        content_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content_box.set_margin_top(24)
        content_box.set_margin_bottom(24)
        content_box.set_margin_start(24)
        content_box.set_margin_end(24)
        
        description = Gtk.Label(
            label="Define constants to use in your commands. Reference them with $NAME or ${NAME}.",
            xalign=0,
        )
        description.set_wrap(True)
        description.add_css_class("body")
        content_box.append(description)
        
        self._listbox = Gtk.ListBox()
        self._listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        self._listbox.add_css_class("boxed-list")
        
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_hexpand(True)
        scrolled.set_vexpand(True)
        scrolled.set_child(self._listbox)
        
        placeholder = Adw.StatusPage()
        placeholder.set_icon_name("text-x-generic-symbolic")
        placeholder.set_title("No Constants")
        placeholder.set_description("Click the + button to define a constant.")
        
        self._content_stack = Gtk.Stack()
        self._content_stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self._content_stack.set_hexpand(True)
        self._content_stack.set_vexpand(True)
        self._content_stack.add_named(scrolled, "list")
        self._content_stack.add_named(placeholder, "placeholder")
        
        content_box.append(self._content_stack)
        
        toolbar_view.set_content(content_box)
        self.set_content(toolbar_view)

    def _load_constants(self):
        """Load constants from application and populate the list."""
        self._constants = self._app.get_constants().copy()
        self._refresh_list()

    def _refresh_list(self):
        """Refresh the constants list display."""
        # Clear existing rows
        row = self._listbox.get_row_at_index(0)
        while row is not None:
            self._listbox.remove(row)
            row = self._listbox.get_row_at_index(0)
        
        # Add rows for each constant
        for name, value in sorted(self._constants.items()):
            row = self._create_constant_row(name, value)
            self._listbox.append(row)
        
        # Show appropriate view
        has_constants = bool(self._constants)
        self._content_stack.set_visible_child_name("list" if has_constants else "placeholder")

    def _create_constant_row(self, name: str, value: str) -> Adw.ActionRow:
        """Create a row displaying a constant."""
        row = Adw.ActionRow()
        row.set_title(name)
        row.set_subtitle(value)
        row.set_activatable(False)
        
        controls_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        controls_box.set_valign(Gtk.Align.CENTER)
        
        edit_button = Gtk.Button.new_from_icon_name("document-edit-symbolic")
        edit_button.add_css_class("flat")
        edit_button.set_tooltip_text("Edit constant")
        edit_button.connect("clicked", self._on_edit_constant, name)
        controls_box.append(edit_button)
        
        remove_button = Gtk.Button.new_from_icon_name("user-trash-symbolic")
        remove_button.add_css_class("flat")
        remove_button.set_tooltip_text("Remove constant")
        remove_button.connect("clicked", self._on_remove_constant, name)
        controls_box.append(remove_button)
        
        row.add_suffix(controls_box)
        return row

    def _on_add_constant(self, _button):
        """Show dialog to add a new constant."""
        self._show_constant_dialog()

    def _on_edit_constant(self, _button, name: str):
        """Show dialog to edit an existing constant."""
        value = self._constants.get(name, "")
        self._show_constant_dialog(name, value)

    def _on_remove_constant(self, _button, name: str):
        """Remove a constant."""
        if name in self._constants:
            del self._constants[name]
            self._save_constants()
            self._refresh_list()

    def _show_constant_dialog(self, existing_name: str = "", existing_value: str = ""):
        """Show dialog for adding or editing a constant."""
        editing = bool(existing_name)
        title = "Edit Constant" if editing else "Add Constant"
        
        dialog = Adw.MessageDialog.new(self, title, "Define a constant name and value.")
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("save", "Save" if editing else "Add")
        dialog.set_default_response("save")
        dialog.set_response_appearance("save", Adw.ResponseAppearance.SUGGESTED)
        
        # Create form
        form_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        form_box.set_margin_top(12)
        form_box.set_margin_bottom(12)
        
        name_entry = Gtk.Entry()
        name_entry.set_placeholder_text("Constant name (e.g., D2DL_SCHEMA)")
        if existing_name:
            name_entry.set_text(existing_name)
            name_entry.set_sensitive(False)  # Don't allow renaming
        form_box.append(name_entry)
        
        value_entry = Gtk.Entry()
        value_entry.set_placeholder_text("Value (e.g., org.gnome.shell.extensions.dash2dock-lite)")
        if existing_value:
            value_entry.set_text(existing_value)
        form_box.append(value_entry)
        
        hint_label = Gtk.Label(
            label="Use in commands as $NAME or ${NAME}",
            xalign=0,
        )
        hint_label.add_css_class("dim-label")
        hint_label.add_css_class("caption")
        form_box.append(hint_label)
        
        dialog.set_extra_child(form_box)
        dialog.connect("response", self._on_constant_dialog_response, existing_name, name_entry, value_entry)
        dialog.present()

    def _on_constant_dialog_response(self, dialog, response, old_name, name_entry, value_entry):
        """Handle constant dialog response."""
        try:
            if response != "save":
                return
            
            name = name_entry.get_text().strip()
            value = value_entry.get_text().strip()
            
            if not name or not value:
                return
            
            # Validate name (should be valid shell variable name)
            if not name.replace("_", "").isalnum() or name[0].isdigit():
                error_dialog = Adw.MessageDialog.new(
                    self,
                    "Invalid Name",
                    "Constant name must be a valid shell variable name (letters, numbers, underscores)."
                )
                error_dialog.add_response("ok", "OK")
                error_dialog.present()
                return
            
            # If editing, remove old name if it changed
            if old_name and old_name != name and old_name in self._constants:
                del self._constants[old_name]
            
            self._constants[name] = value
            self._save_constants()
            self._refresh_list()
        finally:
            dialog.destroy()

    def _save_constants(self):
        """Save constants to application."""
        self._app.save_constants(self._constants)
