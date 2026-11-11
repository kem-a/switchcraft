/* CommandDialog.vala
 * Add or edit a custom command or a built-in setting
 *
 * Copyright (c) 2026 kem-a
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Switchcraft {

    public class CommandDialog : Adw.AlertDialog {
        // builtin and value are empty for a custom command
        public signal void saved (string command, string builtin, string value, string theme);
        public signal void deleted ();

        private Application app;
        private HashTable<string, List<CommandEntry>> commands;
        private CommandEntry? entry;
        private Gtk.Label conflict_label;
        private Gtk.Label duplicate_label;
        private Adw.ComboRow type_row;
        private Gtk.ListBoxRow command_row;
        private Gtk.TextBuffer command_buffer;
        private Gtk.Box error_box;
        private Gtk.Label error_label;
        private Gtk.Label test_status;
        private Adw.Spinner test_spinner;
        private Gtk.Button test_button;
        private Cancellable? test_cancellable = null;
        private Adw.ComboRow value_row;
        private Adw.ActionRow image_row;
        private Gtk.Label image_label;
        private Adw.ToggleGroup mode_group;
        private GenericArray<string> value_ids;
        private string wallpaper_path = "";
        // Built-in settings offered in the Type list, after Custom Command
        private string[] setting_ids = {};
        private string initial_builtin = "";
        private string initial_value = "";

        public static string get_builtin_title (string setting_id) {
            switch (setting_id) {
                case "color-scheme":
                case "kde-color-scheme":
                    return _("Color Scheme");
                case "accent-color":
                    return _("Accent Color");
                case "icon-theme":
                case "kde-icon-theme":
                    return _("Icon Theme");
                case "gtk-theme":
                    return _("GTK Theme");
                case "cursor-theme":
                case "kde-cursor-theme":
                    return _("Cursor Theme");
                case "shell-theme":
                    return _("Shell Theme");
                case "wallpaper":
                case "kde-wallpaper":
                    return _("Wallpaper");
                case "night-light":
                    return _("Night Light");
                case "kde-global-theme":
                    return _("Global Theme");
                case "kde-plasma-style":
                    return _("Plasma Style");
                case "kvantum-theme":
                    return _("Kvantum Theme");
                default:
                    return "";
            }
        }

        // Wallpapers are picked as files instead of from a list
        public static bool is_image_setting (string setting_id) {
            return setting_id == "wallpaper" || setting_id == "kde-wallpaper";
        }

        // Why a command cannot run in the theme's list, or null. Commands
        // that switch to the other style would run both lists in a loop.
        public static string? find_loop_conflict (HashTable<string, List<CommandEntry>> commands,
                                                  CommandEntry? entry, string command, string builtin, string theme) {
            // GNOME follows its color-scheme key, KDE the window color of
            // its color scheme, which a global theme can also change
            bool known = false;
            bool dark = false;
            MatchInfo match;
            if (/color-scheme["']?\s+["']*(prefer-dark|prefer-light|default)\b/.match (command, 0, out match)) {
                known = true;
                dark = match.fetch (1) == "prefer-dark";
            } else if (/plasma-apply-colorscheme\s+["']?([^"'\s]+)/.match (command, 0, out match)) {
                known = Application.get_kde_scheme_dark (match.fetch (1), out dark);
            } else if (/plasma-apply-lookandfeel\s+(?:-a|--apply)\s+["']?([^"'\s]+)/.match (command, 0, out match)) {
                known = Application.get_kde_global_theme_dark (match.fetch (1), out dark);
            }
            if (known && theme == "dark" && !dark) {
                return _("Switches to the light style and would loop in Dark mode");
            }
            if (known && theme == "light" && dark) {
                return _("Switches to the dark style and would loop in Light mode");
            }
            return null;
        }

        // A command or setting that already exists in this mode. This is a
        // warning only, duplicates are allowed.
        public static string? find_duplicate (HashTable<string, List<CommandEntry>> commands,
                                              CommandEntry? entry, string command, string builtin, string theme) {
            foreach (var other in commands.lookup (theme)) {
                if (other == entry) {
                    continue;
                }
                if (builtin.length > 0 && other.builtin == builtin) {
                    var message = _("%s is already set in this mode").printf (get_builtin_title (builtin));
                    print ("%s\n", message);
                    return message;
                }
                if (other.command.strip () == command.strip ()) {
                    var message = _("This command is already in this mode");
                    print ("%s\n", message);
                    return message;
                }
            }
            return null;
        }

        public CommandDialog (Application app, HashTable<string, List<CommandEntry>> commands,
                              CommandEntry? entry, string theme) {
            Object (heading: entry != null ? _("Edit Command") : _("Add Command"));
            this.app = app;
            this.commands = commands;
            this.entry = entry;
            value_ids = new GenericArray<string> ();

            if (entry != null) {
                add_response ("delete", _("Delete"));
                set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            }
            add_response ("cancel", _("Cancel"));
            add_response ("save", entry != null ? _("Save") : _("Add"));
            set_default_response ("save");
            set_close_response ("cancel");
            set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);

            var fields = new Gtk.ListBox ();
            fields.set_selection_mode (Gtk.SelectionMode.NONE);
            fields.add_css_class ("boxed-list");
            fields.set_size_request (520, -1);

            // First item is a custom command, the rest are the built-in
            // settings for this desktop
            var type_model = new Gtk.StringList (null);
            type_model.append (_("Custom Command"));
            // Wallpaper is always the last entry in the list
            foreach (var setting_id in Application.THEME_SETTING_IDS) {
                if (is_image_setting (setting_id)) {
                    continue;
                }
                // One from another desktop stays while it is being edited
                if (app.is_setting_available (setting_id) || (entry != null && entry.builtin == setting_id)) {
                    setting_ids += setting_id;
                    type_model.append (get_builtin_title (setting_id));
                }
            }
            foreach (var setting_id in Application.THEME_SETTING_IDS) {
                if (!is_image_setting (setting_id)) {
                    continue;
                }
                if (app.is_setting_available (setting_id) || (entry != null && entry.builtin == setting_id)) {
                    setting_ids += setting_id;
                    type_model.append (get_builtin_title (setting_id));
                }
            }
            type_row = new Adw.ComboRow ();
            type_row.set_title (_("Type"));
            type_row.set_model (type_model);
            fields.append (type_row);

            // Multiline, wrapping command field that grows with its text
            var command_title = new Gtk.Label (_("Command"));
            command_title.set_xalign (0);
            command_title.add_css_class ("caption");
            command_title.add_css_class ("dim-label");

            var command_view = new Gtk.TextView ();
            command_view.set_wrap_mode (Gtk.WrapMode.WORD_CHAR);
            command_view.set_accepts_tab (false);
            command_view.add_css_class ("command-view");
            command_buffer = command_view.get_buffer ();

            var command_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            command_box.set_margin_top (8);
            command_box.set_margin_bottom (10);
            command_box.set_margin_start (12);
            command_box.set_margin_end (12);
            command_box.append (command_title);
            command_box.append (command_view);

            // Output of a failed test, selectable and copyable
            error_label = new Gtk.Label (null);
            error_label.set_xalign (0);
            error_label.set_wrap (true);
            error_label.set_wrap_mode (Pango.WrapMode.WORD_CHAR);
            error_label.set_max_width_chars (40);
            error_label.set_selectable (true);
            error_label.set_hexpand (true);
            error_label.set_valign (Gtk.Align.START);
            error_label.set_margin_top (8);
            error_label.set_margin_bottom (8);
            error_label.set_margin_start (10);
            error_label.add_css_class ("monospace");

            var error_scroll = new Gtk.ScrolledWindow ();
            error_scroll.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            error_scroll.set_propagate_natural_height (true);
            error_scroll.set_max_content_height (160);
            error_scroll.set_child (error_label);

            var copy_button = new Gtk.Button.from_icon_name ("edit-copy-symbolic");
            copy_button.set_tooltip_text (_("Copy Error"));
            copy_button.set_valign (Gtk.Align.START);
            copy_button.set_margin_top (4);
            copy_button.set_margin_end (4);
            copy_button.add_css_class ("flat");
            copy_button.clicked.connect (() => {
                get_clipboard ().set_text (error_label.get_text ());
            });

            error_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            error_box.set_margin_top (6);
            error_box.add_css_class ("card");
            error_box.append (error_scroll);
            error_box.append (copy_button);
            error_box.set_visible (false);
            command_box.append (error_box);

            test_status = new Gtk.Label (null);
            test_status.set_xalign (0);
            test_status.set_hexpand (true);
            test_status.set_wrap (true);

            test_spinner = new Adw.Spinner ();
            test_spinner.set_visible (false);

            test_button = new Gtk.Button.with_label (_("Test"));
            test_button.clicked.connect (on_test_command);

            var test_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            test_bar.set_margin_top (6);
            test_bar.append (test_status);
            test_bar.append (test_spinner);
            test_bar.append (test_button);
            command_box.append (test_bar);

            command_row = new Gtk.ListBoxRow ();
            command_row.set_activatable (false);
            command_row.set_child (command_box);
            fields.append (command_row);

            value_row = new Adw.ComboRow ();
            value_row.set_title (_("Value"));
            fields.append (value_row);

            // Wallpapers are picked as files instead of from a list
            image_row = new Adw.ActionRow ();
            image_row.set_title (_("Image"));
            image_label = new Gtk.Label (null);
            image_label.set_ellipsize (Pango.EllipsizeMode.MIDDLE);
            image_label.set_max_width_chars (20);
            image_row.add_suffix (image_label);
            var browse_button = new Gtk.Button.with_label (_("Browse…"));
            browse_button.set_valign (Gtk.Align.CENTER);
            browse_button.clicked.connect (on_browse_wallpaper);
            image_row.add_suffix (browse_button);
            image_row.set_activatable_widget (browse_button);
            fields.append (image_row);

            var mode_toggle = SlidingToggleGroup.for_theme (theme);
            mode_group = mode_toggle.group;
            var mode_row = new Adw.ActionRow ();
            mode_row.set_title (_("Mode"));
            mode_row.add_suffix (mode_toggle);
            fields.append (mode_row);

            conflict_label = new Gtk.Label (null);
            conflict_label.set_xalign (0);
            conflict_label.set_wrap (true);
            conflict_label.set_max_width_chars (40);
            conflict_label.set_margin_top (12);
            conflict_label.add_css_class ("error");
            conflict_label.set_visible (false);

            duplicate_label = new Gtk.Label (null);
            duplicate_label.set_xalign (0);
            duplicate_label.set_wrap (true);
            duplicate_label.set_max_width_chars (40);
            duplicate_label.set_margin_top (6);
            duplicate_label.add_css_class ("warning");
            duplicate_label.set_visible (false);

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            content.append (fields);
            content.append (duplicate_label);
            content.append (conflict_label);
            set_extra_child (content);

            // Fill in the entry being edited
            uint type_index = 0;
            if (entry != null && entry.builtin.length > 0) {
                for (int i = 0; i < setting_ids.length; i++) {
                    if (setting_ids[i] == entry.builtin) {
                        type_index = i + 1;
                    }
                }
            }
            if (type_index > 0) {
                initial_builtin = entry.builtin;
                initial_value = entry.value;
                if (is_image_setting (entry.builtin)) {
                    set_wallpaper (entry.value);
                }
            } else if (entry != null) {
                command_buffer.set_text (entry.command);
            }
            type_row.set_selected (type_index);
            on_type_changed ();
            update_test_button ();

            type_row.notify["selected"].connect (on_type_changed);
            value_row.notify["selected"].connect (update_save_response);
            mode_group.notify["active-name"].connect (update_save_response);
            command_buffer.changed.connect (update_save_response);
            command_buffer.changed.connect (() => {
                show_test_result (false, null);
                update_test_button ();
            });

            // Stop a test that is still running
            closed.connect (() => {
                if (test_cancellable != null) {
                    test_cancellable.cancel ();
                }
            });

            response.connect ((response_id) => {
                if (response_id == "save") {
                    emit_saved ();
                } else if (response_id == "delete") {
                    deleted ();
                }
            });
        }

        private string get_setting_id () {
            uint selected = type_row.get_selected ();
            if (selected == 0 || selected == Gtk.INVALID_LIST_POSITION) {
                return "";
            }
            return setting_ids[selected - 1];
        }

        private void on_type_changed () {
            var setting_id = get_setting_id ();
            command_row.set_visible (setting_id == "");
            image_row.set_visible (is_image_setting (setting_id));
            value_row.set_visible (setting_id != "" && !is_image_setting (setting_id));

            if (value_row.get_visible ()) {
                fill_values (setting_id);
            }
            update_save_response ();
        }

        // Starts at the edited value, or at what the desktop uses now
        private void fill_values (string setting_id) {
            value_ids = app.scan_setting_values (setting_id);
            var model = new Gtk.StringList (null);
            for (uint i = 0; i < value_ids.length; i++) {
                model.append (Application.get_setting_value_label (setting_id, value_ids[i]));
            }

            var current = setting_id == initial_builtin
                ? initial_value
                : app.get_current_theme_value (setting_id, mode_group.get_active_name ());
            uint selected = Gtk.INVALID_LIST_POSITION;
            for (uint i = 0; i < value_ids.length; i++) {
                if (value_ids[i] == current) {
                    selected = i;
                }
            }
            if (selected == Gtk.INVALID_LIST_POSITION && current.length > 0) {
                // Keep a value that discovery did not find
                value_ids.add (current);
                model.append (Application.get_setting_value_label (setting_id, current));
                selected = value_ids.length - 1;
            }

            // Long package ids are shown by their desktop names. The
            // tooltip still gives the full text when the label is clipped.
            value_row.set_model (model);
            value_row.set_factory (create_value_factory ());
            value_row.set_list_factory (create_value_factory ());
            value_row.set_selected (selected);

            bool supported = setting_id != "shell-theme" || app.has_shell_theme_support ();
            value_row.set_sensitive (supported);
            value_row.set_subtitle (supported ? "" : _("Requires the User Themes GNOME Shell extension."));
        }

        private Gtk.ListItemFactory create_value_factory () {
            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect ((object) => {
                var item = object as Gtk.ListItem;
                if (item == null) {
                    return;
                }
                var label = new Gtk.Label (null);
                label.set_xalign (0);
                label.set_ellipsize (Pango.EllipsizeMode.END);
                label.set_max_width_chars (60);
                item.set_child (label);
            });
            factory.bind.connect ((object) => {
                var item = object as Gtk.ListItem;
                if (item == null) {
                    return;
                }
                var label = item.get_child () as Gtk.Label;
                var string_object = item.get_item () as Gtk.StringObject;
                if (label == null || string_object == null) {
                    return;
                }
                var text = string_object.get_string ();
                label.set_label (text);
                label.set_tooltip_text (text);
            });
            return factory;
        }

        private string get_selected_value () {
            uint selected = value_row.get_selected ();
            if (selected == Gtk.INVALID_LIST_POSITION || selected >= value_ids.length) {
                return "";
            }
            return value_ids[selected];
        }

        private void update_save_response () {
            var setting_id = get_setting_id ();
            bool valid;
            if (setting_id == "") {
                valid = command_buffer.text.strip ().length > 0;
            } else if (is_image_setting (setting_id)) {
                valid = wallpaper_path.length > 0;
            } else {
                valid = value_row.get_sensitive () && get_selected_value ().length > 0;
            }

            // Disabled commands do not run, so they cannot loop
            string? conflict = null;
            if (valid && (entry == null || entry.enabled)) {
                conflict = find_loop_conflict (commands, entry, get_command (), setting_id, mode_group.get_active_name ());
            }
            string? duplicate = valid
                ? find_duplicate (commands, entry, get_command (), setting_id, mode_group.get_active_name ())
                : null;

            conflict_label.set_label (conflict ?? "");
            conflict_label.set_visible (conflict != null);
            duplicate_label.set_label (duplicate ?? "");
            duplicate_label.set_visible (duplicate != null);
            set_response_enabled ("save", valid && conflict == null);
        }

        // The command Save stores
        private string get_command () {
            var setting_id = get_setting_id ();
            if (setting_id == "") {
                return command_buffer.text.strip ();
            }
            var value = is_image_setting (setting_id) ? wallpaper_path : get_selected_value ();
            return app.build_builtin_command (setting_id, value);
        }

        private void update_test_button () {
            test_button.set_sensitive (test_cancellable == null && command_buffer.text.strip ().length > 0);
        }

        private void on_test_command () {
            show_test_result (false, null);
            test_cancellable = new Cancellable ();
            test_spinner.set_visible (true);
            update_test_button ();

            app.test_command.begin (command_buffer.text.strip (), test_cancellable, (obj, res) => {
                string? error_text;
                try {
                    error_text = app.test_command.end (res);
                } catch (IOError.CANCELLED e) {
                    return;
                } catch (Error e) {
                    error_text = e.message;
                }
                test_cancellable = null;
                test_spinner.set_visible (false);
                update_test_button ();
                show_test_result (true, error_text);
            });
        }

        // Shows nothing when not finished, else success or the error text
        private void show_test_result (bool finished, string? error_text) {
            bool failed = finished && error_text != null;
            if (failed) {
                print ("%s\n", error_text);
            }
            test_status.remove_css_class ("success");
            test_status.remove_css_class ("error");
            if (finished) {
                test_status.add_css_class (failed ? "error" : "success");
            }
            test_status.set_label (!finished ? "" : failed ? _("Command failed") : _("Command succeeded"));
            error_label.set_text (failed ? error_text : "");
            error_box.set_visible (failed);
        }

        private void set_wallpaper (string path) {
            wallpaper_path = path;
            image_label.set_label (path.length > 0 ? Path.get_basename (path) : "");
            image_label.set_tooltip_text (path.length > 0 ? path : null);
        }

        private void on_browse_wallpaper () {
            var dialog = new Gtk.FileDialog ();
            dialog.set_title (_("Select Wallpaper"));

            var filter = new Gtk.FileFilter ();
            filter.add_mime_type ("image/*");
            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            filters.append (filter);
            dialog.set_filters (filters);
            dialog.set_default_filter (filter);

            dialog.open.begin (get_root () as Gtk.Window, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    var path = file != null ? file.get_path () : null;
                    if (path != null && path.length > 0) {
                        set_wallpaper (path);
                        update_save_response ();
                    }
                } catch (Error e) {
                    // Cancelled
                }
            });
        }

        private void emit_saved () {
            var theme = mode_group.get_active_name ();
            var setting_id = get_setting_id ();
            if (setting_id == "") {
                saved (command_buffer.text.strip (), "", "", theme);
                return;
            }

            var value = is_image_setting (setting_id) ? wallpaper_path : get_selected_value ();
            saved (app.build_builtin_command (setting_id, value), setting_id, value, theme);
        }
    }
}
