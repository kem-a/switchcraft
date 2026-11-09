/* MainWindow.vala
 * Main application window with libadwaita UI
 *
 * Copyright (c) 2021-2025 kem-a
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Switchcraft {

    public class MainWindow : Adw.ApplicationWindow {
        private HashTable<string, List<CommandEntry>> commands;
        private HashTable<string, Adw.ComboRow> theme_combo_rows;
        private HashTable<string, ThemeSettingValue> theme_settings;
        private HashTable<string, Adw.ActionRow> wallpaper_rows;
        private Adw.Banner? banner = null;
        private PreferencesWindow? preferences_window = null;
        private Adw.ToastOverlay? toast_overlay = null;
        private Adw.ViewStack view_stack;
        private Gtk.ListBox enabled_command_listbox;
        private Gtk.ListBox disabled_command_listbox;
        private Adw.ButtonRow add_command_row;
        private AnimatedRows animated_rows;
        private Gtk.Box builtin_columns;
        private HashTable<Gtk.ListBoxRow, CommandEntry> command_row_entries;
        private CommandEntry? drag_source_entry = null;
        private string? drag_theme = null;
        private bool drag_source_enabled = false;
        private bool loading_theme_settings = false;
        private GenericArray<string> row_theme_map;
        private GenericArray<CommandEntry> row_entry_map;
        private CommandEntry? inline_editor_entry = null;
        private string inline_editor_theme = "light";
        private string inline_editor_text = "";
        private bool inline_editor_is_new = false;
        private bool should_focus_inline_editor = false;

        private const string LIGHT_ICON = "weather-clear-symbolic";
        private const string DARK_ICON = "weather-clear-night-symbolic";

        public MainWindow (Application app) {
            Object (application: app);

            set_title ("Switchcraft");
            set_default_size (850, 620);
            set_size_request (360, 294);

            theme_combo_rows = new HashTable<string, Adw.ComboRow> (str_hash, str_equal);
            wallpaper_rows = new HashTable<string, Adw.ActionRow> (str_hash, str_equal);
            command_row_entries = new HashTable<Gtk.ListBoxRow, CommandEntry> (direct_hash, direct_equal);
            row_theme_map = new GenericArray<string> ();
            row_entry_map = new GenericArray<CommandEntry> ();

            load_commands_from_application ();
            load_theme_settings_from_application ();

            build_ui ();
        }

        private void build_ui () {
            var toolbar_view = new Adw.ToolbarView ();
            var header_bar = new Adw.HeaderBar ();
            toolbar_view.add_top_bar (header_bar);

            // Add actions
            add_action_handler ("add-command", on_add_command_action);
            add_action_handler ("show-preferences", on_show_preferences_action);
            add_action_handler ("show-about", on_show_about_action);
            add_action_handler ("show-constants", on_show_constants_action);

            // Menu button
            var menu_button = new Gtk.MenuButton ();
            menu_button.set_icon_name ("open-menu-symbolic");
            var menu = new Menu ();
            menu.append (_("Preferences"), "win.show-preferences");
            menu.append (_("Constants"), "win.show-constants");
            // app.shortcuts comes from Adw.Application and shortcuts-dialog.ui
            menu.append (_("Keyboard Shortcuts"), "app.shortcuts");
            menu.append (_("About Switchcraft"), "win.show-about");
            menu.append (_("Quit"), "app.quit");
            menu_button.set_menu_model (menu);
            header_bar.pack_end (menu_button);

            // View stack for Built-in / Custom pages
            view_stack = new Adw.ViewStack ();

            var view_switcher = new Adw.ViewSwitcher ();
            view_switcher.set_stack (view_stack);
            view_switcher.set_policy (Adw.ViewSwitcherPolicy.WIDE);
            header_bar.set_title_widget (view_switcher);

            // Banner for monitoring status
            banner = new Adw.Banner (_("Background monitoring is now active"));
            banner.set_button_label (_("Dismiss"));
            banner.button_clicked.connect (() => { banner.set_revealed (false); });
            banner.set_revealed (false);

            var content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            content_box.append (banner);
            content_box.append (view_stack);

            toolbar_view.set_content (content_box);

            toast_overlay = new Adw.ToastOverlay ();
            toast_overlay.set_child (toolbar_view);
            set_content (toast_overlay);

            // Build pages
            loading_theme_settings = true;

            var builtin_page = build_builtin_page ();
            var builtin_stack_page = view_stack.add_titled (builtin_page, "builtin", _("Built-in"));
            builtin_stack_page.set_icon_name ("applications-system-symbolic");

            var custom_page = build_custom_page ();
            var custom_stack_page = view_stack.add_titled (custom_page, "custom", _("Custom"));
            custom_stack_page.set_icon_name ("utilities-terminal-symbolic");

            loading_theme_settings = false;

            // Bottom switcher bar for narrow windows
            var switcher_bar = new Adw.ViewSwitcherBar ();
            switcher_bar.set_stack (view_stack);
            toolbar_view.add_bottom_bar (switcher_bar);

            var narrow = new Adw.Breakpoint (Adw.BreakpointCondition.parse ("max-width: 550sp"));
            narrow.add_setter (switcher_bar, "reveal", true);
            narrow.add_setter (header_bar, "title-widget", Value (typeof (Gtk.Widget)));
            narrow.add_setter (builtin_columns, "orientation", Gtk.Orientation.VERTICAL);
            add_breakpoint (narrow);
        }

        // ── Built-in page (two-column theme settings) ─────────────────────

        private Gtk.Widget build_builtin_page () {
            var scrolled = new Gtk.ScrolledWindow ();
            scrolled.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            scrolled.set_hexpand (true);
            scrolled.set_vexpand (true);

            var page_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            page_box.set_margin_top (24);
            page_box.set_margin_bottom (24);
            page_box.set_margin_start (24);
            page_box.set_margin_end (24);

            builtin_columns = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 24);
            builtin_columns.set_homogeneous (true);
            builtin_columns.set_hexpand (true);

            var app = get_application () as Application;

            foreach (var theme in new string[] { "light", "dark" }) {
                var column = build_theme_column (theme, app);
                builtin_columns.append (column);
            }

            page_box.append (builtin_columns);
            scrolled.set_child (page_box);
            return scrolled;
        }

        private Gtk.Widget build_theme_column (string theme, Application? app) {
            var column = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            var group = new Adw.PreferencesGroup ();
            var label = theme == "light" ? _("Light") : _("Dark");
            var icon = new Gtk.Image.from_icon_name (theme == "light" ? LIGHT_ICON : DARK_ICON);
            var header = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            var title_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var title = new Gtk.Label (label);
            var description = new Gtk.Label (
                theme == "light" ? _("Applied when light mode activates.")
                                 : _("Applied when dark mode activates."));

            title.set_xalign (0.0f);
            title.add_css_class ("title-4");
            description.set_xalign (0.0f);
            description.add_css_class ("dim-label");

            title_row.append (icon);
            title_row.append (title);
            header.append (title_row);
            header.append (description);
            column.append (header);

            // Theme combo rows
            string[] setting_ids = { "icon-theme", "gtk-theme", "cursor-theme", "shell-theme" };
            string[] setting_titles = { _("Icon Theme"), _("GTK Theme"), _("Cursor Theme"), _("Shell Theme") };
            string[] setting_icons = { "view-grid-symbolic", "preferences-desktop-theme-symbolic", "input-mouse-symbolic", "user-desktop-symbolic" };

            for (int i = 0; i < setting_ids.length; i++) {
                var combo = create_theme_combo_row (theme, setting_ids[i], setting_titles[i], app);
                var prefix_icon = new Gtk.Image.from_icon_name (setting_icons[i]);
                combo.add_prefix (prefix_icon);
                group.add (combo);
                theme_combo_rows.insert ("%s:%s".printf (theme, setting_ids[i]), combo);
            }

            // Wallpaper row
            var wallpaper_row = create_wallpaper_row (theme);
            group.add (wallpaper_row);
            wallpaper_rows.insert (theme, wallpaper_row);

            column.append (group);
            return column;
        }

        private Adw.ComboRow create_theme_combo_row (string theme, string setting_id,
                                                      string title, Application? app) {
            var combo = new Adw.ComboRow ();
            combo.set_title (title);

            var model = new Gtk.StringList (null);
            model.append (_("Don\u2019t change"));

            if (app != null) {
                GenericArray<string>? available = null;
                switch (setting_id) {
                    case "icon-theme":
                        available = app.scan_icon_themes ();
                        break;
                    case "gtk-theme":
                        available = app.scan_gtk_themes ();
                        break;
                    case "cursor-theme":
                        available = app.scan_cursor_themes ();
                        break;
                    case "shell-theme":
                        available = app.scan_shell_themes ();
                        break;
                }
                if (available != null) {
                    for (uint i = 0; i < available.length; i++) {
                        model.append (available[i]);
                    }
                }
            }

            combo.set_model (model);

            // Set initial value
            var setting_val = theme_settings.lookup (setting_id);
            if (setting_val != null) {
                set_combo_selection (combo, setting_val.get_for_theme (theme));
            }

            combo.notify["selected"].connect (() => {
                on_theme_combo_changed ();
            });

            return combo;
        }

        private Adw.ActionRow create_wallpaper_row (string theme) {
            var row = new Adw.ActionRow ();
            row.set_title (_("Wallpaper"));
            var wp_icon = new Gtk.Image.from_icon_name ("image-x-generic-symbolic");
            row.add_prefix (wp_icon);

            var setting_val = theme_settings.lookup ("wallpaper");
            string current = setting_val != null ? setting_val.get_for_theme (theme) : "";

            if (current.length > 0) {
                row.set_subtitle (Path.get_basename (current));
            } else {
                row.set_subtitle (_("None"));
            }

            var clear_btn = new Gtk.Button.from_icon_name ("edit-clear-symbolic");
            clear_btn.add_css_class ("flat");
            clear_btn.set_valign (Gtk.Align.CENTER);
            clear_btn.set_tooltip_text (_("Clear wallpaper"));
            clear_btn.clicked.connect (() => {
                on_clear_wallpaper (theme, row);
            });
            row.add_suffix (clear_btn);

            var browse_btn = new Gtk.Button.with_label (_("Browse\u2026"));
            browse_btn.set_valign (Gtk.Align.CENTER);
            browse_btn.clicked.connect (() => {
                on_browse_wallpaper (theme, row);
            });
            row.add_suffix (browse_btn);

            return row;
        }

        private void on_browse_wallpaper (string theme, Adw.ActionRow row) {
            var dialog = new Gtk.FileDialog ();
            dialog.set_title (_("Select Wallpaper for %s Theme").printf (
                theme == "light" ? _("Light") : _("Dark")));

            var filter = new Gtk.FileFilter ();
            filter.add_mime_type ("image/*");

            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            filters.append (filter);
            dialog.set_filters (filters);
            dialog.set_default_filter (filter);

            dialog.open.begin (this, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file != null) {
                        var path = file.get_path ();
                        if (path != null && path.length > 0) {
                            update_wallpaper_setting (theme, path, row);
                        }
                    }
                } catch (Error e) {
                    // User cancelled
                }
            });
        }

        private void on_clear_wallpaper (string theme, Adw.ActionRow row) {
            update_wallpaper_setting (theme, "", row);
        }

        private void update_wallpaper_setting (string theme, string path, Adw.ActionRow row) {
            var setting_val = theme_settings.lookup ("wallpaper");
            if (setting_val == null) {
                setting_val = new ThemeSettingValue ();
                theme_settings.insert ("wallpaper", setting_val);
            }

            setting_val.set_for_theme (theme, path);
            row.set_subtitle (path.length > 0 ? Path.get_basename (path) : _("None"));

            save_theme_settings_from_ui ();
        }

        // ── Custom page (unified command list) ────────────────────────────

        private Gtk.Widget build_custom_page () {
            var page_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 24);
            page_box.set_margin_top (24);
            page_box.set_margin_bottom (24);
            page_box.set_margin_start (24);
            page_box.set_margin_end (24);

            var header_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            var title_label = new Gtk.Label (_("Custom Commands"));
            title_label.add_css_class ("heading");
            title_label.set_xalign (0);
            header_box.append (title_label);

            var desc_label = new Gtk.Label (
                _("Shell commands executed when the system switches themes. Use the toggle to assign each command to light or dark mode.")
            );
            desc_label.add_css_class ("body");
            desc_label.add_css_class ("dim-label");
            desc_label.set_xalign (0);
            desc_label.set_wrap (true);
            header_box.append (desc_label);

            page_box.append (header_box);

            add_command_row = new Adw.ButtonRow ();
            add_command_row.set_start_icon_name ("list-add-symbolic");
            add_command_row.set_tooltip_text (_("Add command"));
            add_command_row.update_property (Gtk.AccessibleProperty.LABEL, _("Add command"), -1);
            add_command_row.set_data<void*> (AnimatedRows.ROW_KEY, (void*) add_command_row);
            add_command_row.activated.connect (() => {
                on_add_command_action ();
            });

            page_box.append (create_command_section (
                _("Commands"),
                _("Active commands that will run when their theme matches."),
                out enabled_command_listbox
            ));

            page_box.append (create_command_section (
                _("Disabled"),
                _("Saved commands that are currently turned off."),
                out disabled_command_listbox
            ));

            animated_rows = new AnimatedRows (page_box,
                { enabled_command_listbox, disabled_command_listbox });

            rebuild_display_order ();
            refresh_command_list_ui ();

            var scrolled = new Gtk.ScrolledWindow ();
            scrolled.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            scrolled.set_hexpand (true);
            scrolled.set_vexpand (true);
            scrolled.set_child (animated_rows);

            return scrolled;
        }

        private Gtk.Widget create_command_section (string title, string description,
                                                   out Gtk.ListBox listbox) {
            var section_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);

            var title_label = new Gtk.Label (title);
            title_label.add_css_class ("title-4");
            title_label.set_xalign (0);
            section_box.append (title_label);

            var description_label = new Gtk.Label (description);
            description_label.add_css_class ("dim-label");
            description_label.set_wrap (true);
            description_label.set_xalign (0);
            section_box.append (description_label);

            listbox = new Gtk.ListBox ();
            listbox.set_selection_mode (Gtk.SelectionMode.NONE);
            listbox.add_css_class ("boxed-list");
            configure_listbox_for_reordering (listbox);
            section_box.append (listbox);

            return section_box;
        }

        private void rebuild_display_order () {
            row_theme_map = new GenericArray<string> ();
            row_entry_map = new GenericArray<CommandEntry> ();

            foreach (var theme in new string[] { "light", "dark" }) {
                unowned List<CommandEntry>? cmds = commands.lookup (theme);
                if (cmds != null) {
                    foreach (var e in cmds) {
                        row_theme_map.add (theme);
                        row_entry_map.add (e);
                    }
                }
            }
        }

        private void refresh_command_list_ui () {
            animated_rows.begin_reorder ();
            command_row_entries.remove_all ();
            clear_command_listbox (enabled_command_listbox);
            clear_command_listbox (disabled_command_listbox);

            for (int i = 0; i < (int) row_entry_map.length; i++) {
                var entry = row_entry_map[i];
                var listbox = entry.enabled ? enabled_command_listbox : disabled_command_listbox;

                // The editor takes the place of the row it edits
                if (entry == inline_editor_entry) {
                    listbox.append (create_inline_command_row ());
                } else {
                    listbox.append (create_command_row (row_theme_map[i], entry));
                }
            }

            // A new command is edited where the "+" row normally sits
            if (inline_editor_is_new) {
                enabled_command_listbox.append (create_inline_command_row ());
            } else {
                enabled_command_listbox.append (add_command_row);
            }
        }

        private void clear_command_listbox (Gtk.ListBox listbox) {
            Gtk.ListBoxRow? row = listbox.get_row_at_index (0);
            while (row != null) {
                listbox.remove (row);
                row = listbox.get_row_at_index (0);
            }
        }

        private void rebuild_commands_from_display_order () {
            var light = new List<CommandEntry> ();
            var dark = new List<CommandEntry> ();
            for (int i = 0; i < (int) row_entry_map.length; i++) {
                if (row_theme_map[i] == "dark") {
                    dark.append (row_entry_map[i]);
                } else {
                    light.append (row_entry_map[i]);
                }
            }
            commands.replace ("light", (owned) light);
            commands.replace ("dark", (owned) dark);
        }

        private int get_entry_index (CommandEntry entry) {
            for (int i = 0; i < (int) row_entry_map.length; i++) {
                if (row_entry_map[i] == entry) {
                    return i;
                }
            }

            return -1;
        }

        private string get_entry_theme (CommandEntry entry) {
            int index = get_entry_index (entry);
            if (index >= 0) {
                return row_theme_map[index];
            }

            return "light";
        }

        private Adw.ToggleGroup create_theme_toggle (string theme) {
            var group = new Adw.ToggleGroup ();
            group.set_valign (Gtk.Align.CENTER);
            group.add (new Adw.Toggle () { name = "light", icon_name = LIGHT_ICON, tooltip = _("Light") });
            group.add (new Adw.Toggle () { name = "dark", icon_name = DARK_ICON, tooltip = _("Dark") });
            group.set_active_name (theme);
            return group;
        }

        private Adw.SwitchRow create_command_row (string theme, CommandEntry entry) {
            var row = new Adw.SwitchRow ();
            // Commands often contain & < > which are not valid markup
            row.set_use_markup (false);
            row.set_title (entry.command);
            row.set_active (entry.enabled);
            row.set_data<void*> (AnimatedRows.ROW_KEY, (void*) entry);
            command_row_entries.insert (row, entry);

            // Drag handle
            var drag_handle = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            drag_handle.set_valign (Gtk.Align.CENTER);
            drag_handle.set_margin_end (6);
            drag_handle.set_tooltip_text (_("Drag to reorder"));

            var drag_icon = new Gtk.Image.from_icon_name ("list-drag-handle-symbolic");
            drag_icon.add_css_class ("dim-label");
            drag_handle.append (drag_icon);
            row.add_prefix (drag_handle);

            var drag_source = new Gtk.DragSource ();
            drag_source.set_actions (Gdk.DragAction.MOVE);
            double press_x = 0;
            double press_y = 0;
            drag_source.prepare.connect ((x, y) => {
                press_x = x;
                press_y = y;
                if (get_entry_index (entry) < 0) {
                    reset_drag_state ();
                    return (Gdk.ContentProvider?) null;
                }

                drag_source_entry = entry;
                drag_theme = get_entry_theme (entry);
                drag_source_enabled = entry.enabled;

                GLib.Value value = GLib.Value (typeof (string));
                value.set_string (drag_theme);
                return new Gdk.ContentProvider.for_value (value);
            });
            drag_source.drag_begin.connect ((drag) => {
                set_drag_icon (drag, row, drag_handle, press_x, press_y);
            });
            drag_source.drag_end.connect ((drag, delete_data) => {
                reset_drag_state ();
            });
            drag_source.drag_cancel.connect ((drag, reason) => {
                reset_drag_state ();
                return false;
            });
            drag_handle.add_controller (drag_source);

            // Theme toggle group (light / dark). Initial state is set before
            // connecting to avoid a spurious change.
            var theme_toggle = create_theme_toggle (theme);
            theme_toggle.set_margin_end (6);
            theme_toggle.notify["active-name"].connect (() => {
                on_theme_toggle_changed (entry, theme_toggle.get_active_name ());
            });
            row.add_prefix (theme_toggle);

            // Enable/disable switch
            row.notify["active"].connect (() => {
                on_toggle_command_state (row.get_active (), entry);
            });

            // Controls box with edit and remove buttons
            var controls_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            controls_box.set_valign (Gtk.Align.CENTER);

            var edit_button = new Gtk.Button.from_icon_name ("document-edit-symbolic");
            edit_button.add_css_class ("flat");
            edit_button.set_tooltip_text (_("Edit command"));
            edit_button.clicked.connect (() => {
                on_edit_command_clicked (entry);
            });
            controls_box.append (edit_button);

            var remove_button = new Gtk.Button.from_icon_name ("user-trash-symbolic");
            remove_button.add_css_class ("flat");
            remove_button.set_tooltip_text (_("Remove command"));
            remove_button.clicked.connect (() => {
                on_remove_command_clicked (entry);
            });
            controls_box.append (remove_button);

            row.add_suffix (controls_box);

            update_row_state (row, entry);

            return row;
        }

        private Adw.EntryRow create_inline_command_row () {
            var row = new Adw.EntryRow ();
            row.set_title (_("Command"));
            row.set_text (inline_editor_text);

            var theme_toggle = create_theme_toggle (inline_editor_theme);
            theme_toggle.notify["active-name"].connect (() => {
                inline_editor_theme = theme_toggle.get_active_name ();
            });
            row.add_prefix (theme_toggle);

            // Keep the draft when the list is rebuilt while editing
            row.changed.connect (() => {
                inline_editor_text = row.get_text ();
            });

            var save_button = new Gtk.Button.from_icon_name ("object-select-symbolic");
            save_button.add_css_class ("flat");
            save_button.set_valign (Gtk.Align.CENTER);
            save_button.set_tooltip_text (inline_editor_is_new ? _("Add command") : _("Save command"));
            save_button.clicked.connect (() => {
                save_inline_command_row (row);
            });
            row.add_suffix (save_button);

            var cancel_button = new Gtk.Button.from_icon_name ("window-close-symbolic");
            cancel_button.add_css_class ("flat");
            cancel_button.set_valign (Gtk.Align.CENTER);
            cancel_button.set_tooltip_text (_("Cancel"));
            cancel_button.clicked.connect (() => {
                cancel_inline_command_edit ();
            });
            row.add_suffix (cancel_button);

            row.entry_activated.connect (() => {
                save_inline_command_row (row);
            });

            if (should_focus_inline_editor) {
                should_focus_inline_editor = false;
                GLib.Idle.add (() => {
                    row.grab_focus ();
                    row.set_position (-1);
                    return false;
                });
            }

            return row;
        }

        private void begin_inline_command_edit (string theme, CommandEntry? entry = null) {
            view_stack.set_visible_child_name ("custom");

            inline_editor_theme = theme;
            inline_editor_entry = entry;
            inline_editor_text = entry != null ? entry.command : "";
            inline_editor_is_new = entry == null;
            should_focus_inline_editor = true;

            refresh_command_list_ui ();
        }

        private void cancel_inline_command_edit () {
            inline_editor_entry = null;
            inline_editor_theme = "light";
            inline_editor_text = "";
            inline_editor_is_new = false;
            should_focus_inline_editor = false;
            refresh_command_list_ui ();
        }

        private void save_inline_command_row (Adw.EntryRow entry_widget) {
            var command_text = entry_widget.get_text ().strip ();
            if (command_text.length == 0) {
                entry_widget.grab_focus ();
                return;
            }

            if (inline_editor_is_new) {
                var new_entry = new CommandEntry (command_text, true);
                row_theme_map.add (inline_editor_theme);
                row_entry_map.add (new_entry);
            } else if (inline_editor_entry != null) {
                inline_editor_entry.command = command_text;

                for (int i = 0; i < (int) row_entry_map.length; i++) {
                    if (row_entry_map[i] == inline_editor_entry) {
                        row_theme_map[i] = inline_editor_theme;
                        break;
                    }
                }
            }

            rebuild_commands_from_display_order ();
            inline_editor_entry = null;
            inline_editor_theme = "light";
            inline_editor_text = "";
            inline_editor_is_new = false;
            should_focus_inline_editor = false;

            save_commands ();
            refresh_command_list_ui ();
        }

        private void on_theme_toggle_changed (CommandEntry entry, string new_theme) {
            int listbox_index = get_entry_index (entry);
            if (listbox_index < 0) return;

            string old_theme = row_theme_map[listbox_index];
            if (old_theme == new_theme) return;

            // Remove from old theme list
            unowned List<CommandEntry>? old_list = commands.lookup (old_theme);
            var updated_old = new List<CommandEntry> ();
            if (old_list != null) {
                foreach (var e in old_list) {
                    if (e != entry) {
                        updated_old.append (e);
                    }
                }
            }
            commands.replace (old_theme, (owned) updated_old);

            // Add to new theme list
            unowned List<CommandEntry>? new_list = commands.lookup (new_theme);
            var updated_new = new List<CommandEntry> ();
            if (new_list != null) {
                foreach (var e in new_list) {
                    updated_new.append (e);
                }
            }
            updated_new.append (entry);
            commands.replace (new_theme, (owned) updated_new);

            // Update display tracking in-place — no UI rebuild
            row_theme_map[listbox_index] = new_theme;

            save_commands ();
            refresh_command_list_ui ();
        }

        private void update_row_state (Adw.ActionRow row, CommandEntry entry) {
            if (entry.enabled) {
                row.remove_css_class ("dim-label");
            } else {
                row.add_css_class ("dim-label");
            }
        }

        private void on_toggle_command_state (bool state, CommandEntry entry) {
            entry.enabled = state;
            save_commands ();
            // The row slides into the other section
            refresh_command_list_ui ();
        }

        private void set_drag_icon (Gdk.Drag drag, Adw.ActionRow row, Gtk.Widget handle,
                                    double press_x, double press_y) {
            // Show a copy of the row while dragging. A plain list is opaque,
            // boxed-list cards are translucent in dark mode.
            var copy = new Adw.ActionRow ();
            copy.set_use_markup (false);
            copy.set_title (row.get_title ());
            copy.add_prefix (new Gtk.Image.from_icon_name ("list-drag-handle-symbolic"));

            var list = new Gtk.ListBox ();
            list.set_size_request (row.get_width (), row.get_height ());
            list.append (copy);
            list.drag_highlight_row (copy);

            var icon = new Gtk.DragIcon.get_for_drag (drag);
            icon.set_child (list);

            // Keep the pointer where the drag started
            Graphene.Point hotspot;
            handle.compute_point (row, Graphene.Point () { x = (float) press_x, y = (float) press_y }, out hotspot);
            drag.set_hotspot ((int) hotspot.x, (int) hotspot.y);
        }

        // ── Drag-and-drop reordering ──────────────────────────────────────

        private void configure_listbox_for_reordering (Gtk.ListBox listbox) {
            var drop_target = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);

            drop_target.accept.connect ((drop) => {
                return drag_theme != null && drag_source_entry != null;
            });

            drop_target.enter.connect ((x, y) => {
                if (drag_theme == null) {
                    listbox.drag_unhighlight_row ();
                    return (Gdk.DragAction) 0;
                }
                highlight_drop_position (listbox, y);
                return Gdk.DragAction.MOVE;
            });

            drop_target.motion.connect ((x, y) => {
                if (drag_theme == null) {
                    listbox.drag_unhighlight_row ();
                    return (Gdk.DragAction) 0;
                }
                highlight_drop_position (listbox, y);
                return Gdk.DragAction.MOVE;
            });

            drop_target.leave.connect (() => {
                listbox.drag_unhighlight_row ();
            });

            drop_target.drop.connect ((value, x, y) => {
                listbox.drag_unhighlight_row ();

                if (drag_theme == null || drag_source_entry == null) {
                    reset_drag_state ();
                    return false;
                }

                string source_theme = drag_theme;
                var source_entry = (!) drag_source_entry;
                bool source_enabled = drag_source_enabled;
                reset_drag_state ();

                // Determine target
                var target_row = listbox.get_row_at_y ((int) y);
                if (target_row == null) return false;

                var target_entry = command_row_entries.lookup (target_row);
                if (target_entry == null) {
                    return false;
                }

                int source_display_idx = get_entry_index (source_entry);
                int target_display_idx = get_entry_index (target_entry);
                if (source_display_idx < 0 || target_display_idx < 0) {
                    return false;
                }

                string target_theme = get_entry_theme (target_entry);

                // Only allow reordering within the same theme
                if (source_theme != target_theme || source_enabled != target_entry.enabled) return false;

                reorder_display_command (source_display_idx, target_display_idx);
                return true;
            });

            listbox.add_controller (drop_target);
        }

        private void highlight_drop_position (Gtk.ListBox listbox, double y) {
            var row = listbox.get_row_at_y ((int) y);
            if (row != null && command_row_entries.lookup (row) != null) {
                listbox.drag_highlight_row (row);
            } else {
                listbox.drag_unhighlight_row ();
            }
        }

        private void reorder_display_command (int source_idx, int target_idx) {
            int len = (int) row_entry_map.length;
            if (source_idx < 0 || target_idx < 0 || source_idx >= len || target_idx >= len) return;
            if (source_idx == target_idx) return;

            var moved_theme = row_theme_map[source_idx];
            var moved_entry = row_entry_map[source_idx];

            if (target_idx > source_idx) {
                for (int i = source_idx; i < target_idx; i++) {
                    row_theme_map[i] = row_theme_map[i + 1];
                    row_entry_map[i] = row_entry_map[i + 1];
                }
            } else {
                for (int i = source_idx; i > target_idx; i--) {
                    row_theme_map[i] = row_theme_map[i - 1];
                    row_entry_map[i] = row_entry_map[i - 1];
                }
            }
            row_theme_map[target_idx] = moved_theme;
            row_entry_map[target_idx] = moved_entry;

            rebuild_commands_from_display_order ();
            save_commands ();
            refresh_command_list_ui ();
        }

        private void reset_drag_state () {
            drag_source_entry = null;
            drag_theme = null;
            drag_source_enabled = false;
        }

        // ── Command actions ───────────────────────────────────────────────

        private void on_add_command_action () {
            begin_inline_command_edit ("light");
        }

        private void on_edit_command_clicked (CommandEntry entry) {
            begin_inline_command_edit (get_entry_theme (entry), entry);
        }

        private void on_remove_command_clicked (CommandEntry entry) {
            int listbox_index = get_entry_index (entry);
            if (listbox_index < 0) return;

            row_theme_map.remove_index ((uint) listbox_index);
            row_entry_map.remove_index ((uint) listbox_index);

            rebuild_commands_from_display_order ();
            save_commands ();
            refresh_command_list_ui ();
        }

        // ── Theme settings persistence ────────────────────────────────────

        private void set_combo_selection (Adw.ComboRow combo, string value) {
            if (value.length == 0) {
                combo.set_selected (0);
                return;
            }

            var model = combo.get_model ();
            for (uint i = 0; i < model.get_n_items (); i++) {
                var item = model.get_item (i) as Gtk.StringObject;
                if (item != null && item.get_string () == value) {
                    combo.set_selected (i);
                    return;
                }
            }

            // Value not in discovered list — add it so the user's setting is preserved
            ((Gtk.StringList) model).append (value);
            combo.set_selected (model.get_n_items () - 1);
        }

        private string get_combo_value (Adw.ComboRow combo) {
            var selected = combo.get_selected ();
            if (selected == Gtk.INVALID_LIST_POSITION || selected == 0) {
                return "";
            }
            var item = combo.get_model ().get_item (selected) as Gtk.StringObject;
            return item != null ? item.get_string () : "";
        }

        private void on_theme_combo_changed () {
            if (loading_theme_settings) return;
            save_theme_settings_from_ui ();
        }

        private void save_theme_settings_from_ui () {
            var app = get_application () as Application;
            if (app == null) return;

            var result = new HashTable<string, ThemeSettingValue> (str_hash, str_equal);
            string[] setting_ids = { "icon-theme", "gtk-theme", "cursor-theme", "shell-theme" };

            foreach (var setting_id in setting_ids) {
                var tsv = new ThemeSettingValue ();

                foreach (var t in new string[] { "light", "dark" }) {
                    var key = "%s:%s".printf (t, setting_id);
                    var combo = theme_combo_rows.lookup (key);
                    if (combo != null) {
                        tsv.set_for_theme (t, get_combo_value (combo));
                    }
                }

                if (tsv.light.length > 0 || tsv.dark.length > 0) {
                    result.insert (setting_id, tsv);
                }
            }

            // Preserve wallpaper settings
            var existing_wallpaper = theme_settings.lookup ("wallpaper");
            if (existing_wallpaper != null &&
                (existing_wallpaper.light.length > 0 || existing_wallpaper.dark.length > 0)) {
                result.insert ("wallpaper", existing_wallpaper);
            }

            theme_settings = result;
            app.save_theme_settings (result);
        }

        private void load_theme_settings_from_application () {
            var app = get_application () as Application;
            if (app != null) {
                theme_settings = app.get_theme_settings ();
            } else {
                theme_settings = new HashTable<string, ThemeSettingValue> (str_hash, str_equal);
            }
        }

        private void refresh_theme_combos () {
            loading_theme_settings = true;
            string[] setting_ids = { "icon-theme", "gtk-theme", "cursor-theme", "shell-theme" };

            foreach (var t in new string[] { "light", "dark" }) {
                foreach (var setting_id in setting_ids) {
                    var key = "%s:%s".printf (t, setting_id);
                    var combo = theme_combo_rows.lookup (key);
                    if (combo != null) {
                        var setting_val = theme_settings.lookup (setting_id);
                        var val = setting_val != null ? setting_val.get_for_theme (t) : "";
                        set_combo_selection (combo, val);
                    }
                }

                // Refresh wallpaper rows
                var wp_row = wallpaper_rows.lookup (t);
                if (wp_row != null) {
                    var wp_val = theme_settings.lookup ("wallpaper");
                    var path = wp_val != null ? wp_val.get_for_theme (t) : "";
                    wp_row.set_subtitle (path.length > 0 ? Path.get_basename (path) : _("None"));
                }
            }
            loading_theme_settings = false;
        }

        // ── Actions ───────────────────────────────────────────────────────

        private void add_action_handler (string name, SimpleActionActivateCallback callback) {
            var action = new SimpleAction (name, null);
            action.activate.connect ((a, v) => {
                callback (a, v);
            });
            add_action (action);
        }

        private void on_show_preferences_action () {
            var app = get_application () as Application;
            if (app == null) return;

            if (preferences_window == null) {
                preferences_window = new PreferencesWindow (app, this);
            }

            preferences_window.present (this);
        }

        private void on_show_about_action () {
            var dialog = new Adw.AboutDialog.from_appdata (
                "/com/github/Switchcraft/com.github.Switchcraft.metainfo.xml", "com.github");

            var icon_theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
            var current_dir = Environment.get_current_dir ();
            var icon_dir = Path.build_filename (current_dir, "data", "icons");
            icon_theme.add_search_path (icon_dir);
            dialog.set_application_icon ("com.github.Switchcraft");

            dialog.present (this);
        }

        private void on_show_constants_action () {
            var app = get_application () as Application;
            if (app == null) return;

            var constants_window = new ConstantsWindow (app, this);
            constants_window.present ();
        }

        // ── Persistence ───────────────────────────────────────────────────

        private void save_commands () {
            var app = get_application () as Application;
            if (app == null) return;
            app.save_commands (commands);
        }

        public void reload_commands_from_storage () {
            load_commands_from_application ();
            load_theme_settings_from_application ();
            rebuild_display_order ();
            refresh_command_list_ui ();
            refresh_theme_combos ();
        }

        public void apply_monitoring_state (bool enabled) {
            var app = get_application () as Application;
            if (app == null) return;

            var previously_enabled = app.get_monitoring_enabled ();
            if (previously_enabled == enabled) return;

            app.set_monitoring_enabled (enabled);
            if (banner != null) {
                banner.set_revealed (enabled);
            }
        }

        public void show_toast (string message, bool is_error = false) {
            if (toast_overlay == null) return;

            var toast = new Adw.Toast (message);
            if (is_error) {
                toast.set_priority (Adw.ToastPriority.HIGH);
            }
            toast_overlay.add_toast (toast);
        }

        private void load_commands_from_application () {
            var app = get_application () as Application;
            commands = new HashTable<string, List<CommandEntry>> (str_hash, str_equal);

            if (app != null) {
                var app_commands = app.get_commands ();
                app_commands.foreach ((theme, cmd_list) => {
                    var new_list = new List<CommandEntry> ();
                    foreach (var entry in cmd_list) {
                        new_list.append (new CommandEntry (entry.command, entry.enabled));
                    }
                    commands.insert (theme, (owned) new_list);
                });
            }

            if (commands.lookup ("light") == null) {
                commands.insert ("light", new List<CommandEntry> ());
            }
            if (commands.lookup ("dark") == null) {
                commands.insert ("dark", new List<CommandEntry> ());
            }
        }
    }
}
