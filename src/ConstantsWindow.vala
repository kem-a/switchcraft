/* ConstantsWindow.vala
 * Constants management window
 *
 * Copyright (c) 2021-2025 kem-a
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Switchcraft {

    public class ConstantsWindow : Adw.Window {
        private Application app;
        private HashTable<string, string> constants;
        private Gtk.ListBox listbox;
        private Gtk.Stack content_stack;
        
        public ConstantsWindow (Application application, Gtk.Window parent) {
            Object ();
            
            app = application;
            constants = new HashTable<string, string> (str_hash, str_equal);
            
            set_title (_("Constants"));
            set_default_size (600, 450);
            set_transient_for (parent);
            set_modal (true);
            
            build_ui ();
            load_constants ();
        }
        
        private void build_ui () {
            var toolbar_view = new Adw.ToolbarView ();
            
            var header_bar = new Adw.HeaderBar ();
            toolbar_view.add_top_bar (header_bar);
            
            var add_button = new Gtk.Button ();
            add_button.set_icon_name ("list-add-symbolic");
            add_button.set_tooltip_text (_("Add Constant"));
            add_button.add_css_class ("flat");
            add_button.clicked.connect (on_add_constant);
            header_bar.pack_start (add_button);
            
            // Main content area
            var content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            content_box.set_margin_top (24);
            content_box.set_margin_bottom (24);
            content_box.set_margin_start (24);
            content_box.set_margin_end (24);
            
            var description = new Gtk.Label (_("Define constants to use in your commands. Reference them with $NAME or ${NAME}."));
            description.set_xalign (0);
            description.set_wrap (true);
            description.add_css_class ("body");
            content_box.append (description);
            
            listbox = new Gtk.ListBox ();
            listbox.set_selection_mode (Gtk.SelectionMode.NONE);
            listbox.add_css_class ("boxed-list");
            
            var scrolled = new Gtk.ScrolledWindow ();
            scrolled.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            scrolled.set_hexpand (true);
            scrolled.set_vexpand (true);
            scrolled.set_child (listbox);
            
            var placeholder = new Adw.StatusPage ();
            placeholder.set_icon_name ("text-x-generic-symbolic");
            placeholder.set_title (_("No Constants"));
            placeholder.set_description (_("Click the '+' button to define a constant."));
            
            content_stack = new Gtk.Stack ();
            content_stack.set_transition_type (Gtk.StackTransitionType.CROSSFADE);
            content_stack.set_hexpand (true);
            content_stack.set_vexpand (true);
            content_stack.add_named (scrolled, "list");
            content_stack.add_named (placeholder, "placeholder");
            
            content_box.append (content_stack);
            
            toolbar_view.set_content (content_box);
            set_content (toolbar_view);
        }
        
        private void load_constants () {
            constants = new HashTable<string, string> (str_hash, str_equal);
            bool needs_save = false;
            var app_constants = app.get_constants ();
            app_constants.foreach ((key, value) => {
                var normalized = normalize_constant_value (value);
                constants.insert (key, normalized);
                if (normalized != value) {
                    needs_save = true;
                }
            });

            if (needs_save) {
                save_constants ();
            }

            refresh_list ();
        }
        
        private void refresh_list () {
            // Clear existing rows
            Gtk.ListBoxRow? row = listbox.get_row_at_index (0);
            while (row != null) {
                listbox.remove (row);
                row = listbox.get_row_at_index (0);
            }
            
            // Add rows for each constant (sorted by name)
            var keys = new List<string> ();
            constants.foreach ((key, value) => {
                keys.append (key);
            });
            keys.sort (strcmp);
            
            foreach (var name in keys) {
                var value = constants.lookup (name);
                if (value != null) {
                    var constant_row = create_constant_row (name, value);
                    listbox.append (constant_row);
                }
            }
            
            // Show appropriate view
            bool has_constants = constants.size () > 0;
            content_stack.set_visible_child_name (has_constants ? "list" : "placeholder");
        }
        
        private Adw.ActionRow create_constant_row (string name, string value) {
            var row = new Adw.ActionRow ();
            // Values often contain & < > which are not valid markup
            row.set_use_markup (false);
            row.set_title (name);
            row.set_subtitle (value);
            row.set_activatable (false);
            
            var controls_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            controls_box.set_valign (Gtk.Align.CENTER);
            
            var edit_button = new Gtk.Button.from_icon_name ("document-edit-symbolic");
            edit_button.add_css_class ("flat");
            edit_button.set_tooltip_text (_("Edit constant"));
            edit_button.clicked.connect (() => {
                on_edit_constant (name);
            });
            controls_box.append (edit_button);
            
            var remove_button = new Gtk.Button.from_icon_name ("user-trash-symbolic");
            remove_button.add_css_class ("flat");
            remove_button.set_tooltip_text (_("Remove constant"));
            remove_button.clicked.connect (() => {
                on_remove_constant (name);
            });
            controls_box.append (remove_button);
            
            row.add_suffix (controls_box);
            return row;
        }
        
        private void on_add_constant () {
            show_constant_dialog ("", "");
        }
        
        private void on_edit_constant (string name) {
            var value = constants.lookup (name);
            if (value != null) {
                show_constant_dialog (name, value);
            }
        }
        
        private void on_remove_constant (string name) {
            constants.remove (name);
            save_constants ();
            refresh_list ();
        }
        
        private void show_constant_dialog (string existing_name, string existing_value) {
            bool editing = existing_name.length > 0;
            string title = editing ? _("Edit Constant") : _("Add Constant");
            
            var dialog = new Adw.AlertDialog (title, _("Define a constant name and value."));
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("save", editing ? _("Save") : _("Add"));
            dialog.set_default_response ("save");
            dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
            
            // Create form
            var form_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            form_box.set_margin_top (12);
            form_box.set_margin_bottom (12);
            form_box.set_size_request (450, -1);
            
            var fields = new Gtk.ListBox ();
            fields.set_selection_mode (Gtk.SelectionMode.NONE);
            fields.add_css_class ("boxed-list");
            form_box.append (fields);

            var name_entry = new Adw.EntryRow ();
            name_entry.set_title (_("Constant name (e.g., D2DL_SCHEMA)"));
            if (existing_name.length > 0) {
                name_entry.set_text (existing_name);
                name_entry.set_sensitive (false); // Don't allow renaming
            }
            fields.append (name_entry);

            var value_entry = new Adw.EntryRow ();
            value_entry.set_title (_("Value (e.g., org.gnome.shell.extensions.dash2dock-lite)"));
            if (existing_value.length > 0) {
                value_entry.set_text (existing_value);
            }
            fields.append (value_entry);
            
            var hint_label = new Gtk.Label (_("Use in commands as $NAME or ${NAME}. Names use letters, numbers and underscores."));
            hint_label.set_xalign (0);
            hint_label.set_wrap (true);
            hint_label.set_wrap_mode (Pango.WrapMode.WORD_CHAR);
            hint_label.set_max_width_chars (50);
            hint_label.add_css_class ("dim-label");
            hint_label.add_css_class ("caption");
            form_box.append (hint_label);
            
            // Save stays disabled until the input can be saved, so nothing
            // typed is dropped
            name_entry.changed.connect (() => {
                update_save_response (dialog, name_entry, value_entry);
            });
            value_entry.changed.connect (() => {
                update_save_response (dialog, name_entry, value_entry);
            });
            update_save_response (dialog, name_entry, value_entry);

            dialog.set_extra_child (form_box);
            dialog.choose.begin (this, null, (obj, res) => {
                var response_id = dialog.choose.end (res);
                on_constant_dialog_response (response_id, existing_name, name_entry, value_entry);
            });
        }
        
        private void update_save_response (Adw.AlertDialog dialog,
                                           Adw.EntryRow name_entry, Adw.EntryRow value_entry) {
            var name = name_entry.get_text ().strip ();
            bool name_valid = is_valid_variable_name (name);
            if (name.length > 0 && !name_valid) {
                name_entry.add_css_class ("error");
            } else {
                name_entry.remove_css_class ("error");
            }
            dialog.set_response_enabled ("save",
                name_valid && normalize_constant_value (value_entry.get_text ()).length > 0);
        }

        private void on_constant_dialog_response (string response_id,
                                                   string old_name, Adw.EntryRow name_entry, Adw.EntryRow value_entry) {
            if (response_id != "save") {
                return;
            }
            
            var name = name_entry.get_text ().strip ();
            var normalized_value = normalize_constant_value (value_entry.get_text ());
            
            // If editing, remove old name if it changed
            if (old_name.length > 0 && old_name != name) {
                constants.remove (old_name);
            }
            
            constants.insert (name, normalized_value);
            save_constants ();
            refresh_list ();
        }

        private string normalize_constant_value (string value) {
            var trimmed = value.strip ();
            if (trimmed.length >= 2) {
                char first = trimmed[0];
                char last = trimmed[trimmed.length - 1];
                if ((first == '\'' && last == '\'') || (first == '"' && last == '"')) {
                    return trimmed.substring (1, trimmed.length - 2);
                }
            }
            return trimmed;
        }
        
        private bool is_valid_variable_name (string name) {
            if (name.length == 0) {
                return false;
            }
            
            // First character must be letter or underscore
            unichar c = name.get_char (0);
            if (!c.isalpha () && c != '_') {
                return false;
            }
            
            // Remaining characters must be alphanumeric or underscore
            int i = 0;
            while (name.get_next_char (ref i, out c)) {
                if (!c.isalnum () && c != '_') {
                    return false;
                }
            }
            
            return true;
        }
        
        private void save_constants () {
            app.save_constants (constants);
        }
    }
}
