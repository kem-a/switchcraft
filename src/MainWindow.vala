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
        private weak Gtk.ShortcutsWindow? shortcuts_window = null;
        private Adw.Banner? banner = null;
        private PreferencesWindow? preferences_window = null;
        private Adw.ToastOverlay? toast_overlay = null;
        private Gtk.Button add_button;
        private Adw.ViewStack view_stack;
        private Gtk.ListBox command_listbox;
        private Gtk.Stack command_content_stack;
        private string? drag_theme = null;
        private int drag_source_index = -1;
        private bool loading_theme_settings = false;
        private GenericArray<string> row_theme_map;
        private GenericArray<CommandEntry> row_entry_map;

        private const string LIGHT_ICON = "weather-clear-symbolic";
        private const string DARK_ICON = "weather-clear-night-symbolic";
        private const string SHORTCUTS_RESOURCE = "/com/github/Switchcraft/ui/shortcuts.ui";

        public MainWindow (Application app) {
            Object (application: app);

            set_title ("Switchcraft");
            set_default_size (850, 620);

            theme_combo_rows = new HashTable<string, Adw.ComboRow> (str_hash, str_equal);
            wallpaper_rows = new HashTable<string, Adw.ActionRow> (str_hash, str_equal);
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
            add_action_handler ("show-shortcuts", on_show_shortcuts_action);

            // Add button
            add_button = new Gtk.Button ();
            add_button.set_icon_name ("list-add-symbolic");
            add_button.set_tooltip_text ("Add Command");
            add_button.add_css_class ("flat");
            add_button.set_action_name ("win.add-command");
            header_bar.pack_start (add_button);

            // Menu button
            var menu_button = new Gtk.MenuButton ();
            menu_button.set_icon_name ("open-menu-symbolic");
            var menu = new Menu ();
            menu.append ("Preferences", "win.show-preferences");
            menu.append ("Constants", "win.show-constants");
            menu.append ("Keyboard Shortcuts", "win.show-shortcuts");
            menu.append ("About Switchcraft", "win.show-about");
            menu.append ("Quit", "app.quit");
            menu_button.set_menu_model (menu);
            header_bar.pack_end (menu_button);

            // View stack for Built-in / Custom pages
            view_stack = new Adw.ViewStack ();

            var view_switcher_title = new Adw.ViewSwitcherTitle ();
            view_switcher_title.set_stack (view_stack);
            view_switcher_title.set_title (get_title ());
            header_bar.set_title_widget (view_switcher_title);

            // Banner for monitoring status
            banner = new Adw.Banner ("Background monitoring is now active");
            banner.set_button_label ("Dismiss");
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
            var builtin_stack_page = view_stack.add_titled (builtin_page, "builtin", "Built-in");
            builtin_stack_page.set_icon_name ("applications-system-symbolic");

            var custom_page = build_custom_page ();
            var custom_stack_page = view_stack.add_titled (custom_page, "custom", "Custom");
            custom_stack_page.set_icon_name ("utilities-terminal-symbolic");

            loading_theme_settings = false;

            // Bottom switcher bar for narrow windows
            var switcher_bar = new Adw.ViewSwitcherBar ();
            switcher_bar.set_stack (view_stack);
            toolbar_view.add_bottom_bar (switcher_bar);
            view_switcher_title.bind_property ("title-visible", switcher_bar, "reveal",
                GLib.BindingFlags.SYNC_CREATE);
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

            var columns = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 24);
            columns.set_homogeneous (true);
            columns.set_hexpand (true);

            var app = get_application () as Application;

            foreach (var theme in new string[] { "light", "dark" }) {
                var column = build_theme_column (theme, app);
                columns.append (column);
            }

            page_box.append (columns);
            scrolled.set_child (page_box);
            return scrolled;
        }

        private Gtk.Widget build_theme_column (string theme, Application? app) {
            var group = new Adw.PreferencesGroup ();
            var label = theme == "light" ? "Light" : "Dark";
            group.set_title (label);
            group.set_description ("Applied when %s mode activates.".printf (theme));

            // Header suffix icon
            var icon = new Gtk.Image.from_icon_name (theme == "light" ? LIGHT_ICON : DARK_ICON);
            group.set_header_suffix (icon);

            // Theme combo rows
            string[] setting_ids = { "icon-theme", "gtk-theme", "cursor-theme", "shell-theme" };
            string[] setting_titles = { "Icon Theme", "GTK Theme", "Cursor Theme", "Shell Theme" };
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

            return group;
        }

        private Adw.ComboRow create_theme_combo_row (string theme, string setting_id,
                                                      string title, Application? app) {
            var combo = new Adw.ComboRow ();
            combo.set_title (title);

            var model = new Gtk.StringList (null);
            model.append ("Don\u2019t change");

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
            row.set_title ("Wallpaper");
            var wp_icon = new Gtk.Image.from_icon_name ("image-x-generic-symbolic");
            row.add_prefix (wp_icon);

            var setting_val = theme_settings.lookup ("wallpaper");
            string current = setting_val != null ? setting_val.get_for_theme (theme) : "";

            if (current.length > 0) {
                row.set_subtitle (Path.get_basename (current));
            } else {
                row.set_subtitle ("None");
            }

            var clear_btn = new Gtk.Button.from_icon_name ("edit-clear-symbolic");
            clear_btn.add_css_class ("flat");
            clear_btn.set_valign (Gtk.Align.CENTER);
            clear_btn.set_tooltip_text ("Clear wallpaper");
            clear_btn.clicked.connect (() => {
                on_clear_wallpaper (theme, row);
            });
            row.add_suffix (clear_btn);

            var browse_btn = new Gtk.Button.with_label ("Browse\u2026");
            browse_btn.set_valign (Gtk.Align.CENTER);
            browse_btn.clicked.connect (() => {
                on_browse_wallpaper (theme, row);
            });
            row.add_suffix (browse_btn);

            return row;
        }

        private void on_browse_wallpaper (string theme, Adw.ActionRow row) {
            var dialog = new Gtk.FileDialog ();
            dialog.set_title ("Select Wallpaper for %s Theme".printf (
                theme == "light" ? "Light" : "Dark"));

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
            row.set_subtitle (path.length > 0 ? Path.get_basename (path) : "None");

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
            var title_label = new Gtk.Label ("Custom Commands");
            title_label.add_css_class ("heading");
            title_label.set_xalign (0);
            header_box.append (title_label);

            var desc_label = new Gtk.Label (
                "Shell commands executed when the system switches themes. " +
                "Use the toggle to assign each command to light or dark mode."
            );
            desc_label.add_css_class ("body");
            desc_label.add_css_class ("dim-label");
            desc_label.set_xalign (0);
            desc_label.set_wrap (true);
            header_box.append (desc_label);

            page_box.append (header_box);

            command_listbox = new Gtk.ListBox ();
            command_listbox.set_selection_mode (Gtk.SelectionMode.SINGLE);
            command_listbox.add_css_class ("boxed-list");
            configure_listbox_for_reordering (command_listbox);

            var scrolled = new Gtk.ScrolledWindow ();
            scrolled.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            scrolled.set_hexpand (true);
            scrolled.set_vexpand (true);
            scrolled.set_child (command_listbox);

            var placeholder = new Adw.StatusPage ();
            placeholder.set_icon_name ("list-add-symbolic");
            placeholder.set_title ("No custom commands");
            placeholder.set_description (
                "Click the + button or press Ctrl+N to add a shell command."
            );

            command_content_stack = new Gtk.Stack ();
            command_content_stack.set_transition_type (Gtk.StackTransitionType.CROSSFADE);
            command_content_stack.set_hexpand (true);
            command_content_stack.set_vexpand (true);
            command_content_stack.add_named (scrolled, "list");
            command_content_stack.add_named (placeholder, "placeholder");

            page_box.append (command_content_stack);

            rebuild_display_order ();
            refresh_command_list_ui ();

            return page_box;
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
            Gtk.ListBoxRow? row = command_listbox.get_row_at_index (0);
            while (row != null) {
                command_listbox.remove (row);
                row = command_listbox.get_row_at_index (0);
            }

            for (int i = 0; i < (int) row_entry_map.length; i++) {
                command_listbox.append (create_command_row (row_theme_map[i], row_entry_map[i]));
            }

            command_content_stack.set_visible_child_name (
                row_entry_map.length > 0 ? "list" : "placeholder"
            );
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

        private string get_row_theme (int listbox_index) {
            if (listbox_index >= 0 && listbox_index < (int) row_theme_map.length) {
                return row_theme_map[listbox_index];
            }
            return "light";
        }

        private int get_theme_relative_index (int listbox_index) {
            if (listbox_index < 0 || listbox_index >= (int) row_entry_map.length) return -1;
            var entry = row_entry_map[listbox_index];
            var theme = row_theme_map[listbox_index];
            unowned List<CommandEntry>? cmds = commands.lookup (theme);
            if (cmds == null) return -1;
            int idx = 0;
            foreach (var e in cmds) {
                if (e == entry) return idx;
                idx++;
            }
            return -1;
        }

        private Adw.ActionRow create_command_row (string theme, CommandEntry entry) {
            var row = new Adw.ActionRow ();
            row.set_title (entry.command);
            row.set_activatable (false);

            // Drag handle
            var drag_handle = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            drag_handle.set_valign (Gtk.Align.CENTER);
            drag_handle.set_margin_end (6);
            drag_handle.set_tooltip_text ("Drag to reorder");

            var drag_icon = new Gtk.Image.from_icon_name ("list-drag-handle-symbolic");
            drag_icon.add_css_class ("dim-label");
            drag_handle.append (drag_icon);
            row.add_prefix (drag_handle);

            var drag_source = new Gtk.DragSource ();
            drag_source.set_actions (Gdk.DragAction.MOVE);
            drag_source.prepare.connect ((x, y) => {
                int index = row.get_index ();
                if (index < 0) {
                    reset_drag_state ();
                    return (Gdk.ContentProvider?) null;
                }

                drag_theme = get_row_theme (index);
                drag_source_index = index;

                GLib.Value value = GLib.Value (typeof (string));
                value.set_string (drag_theme);
                return new Gdk.ContentProvider.for_value (value);
            });
            drag_source.drag_end.connect ((drag, delete_data) => {
                reset_drag_state ();
            });
            drag_source.drag_cancel.connect ((drag, reason) => {
                reset_drag_state ();
                return false;
            });
            drag_handle.add_controller (drag_source);

            // Theme toggle group (light / dark)
            var toggle_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            toggle_box.add_css_class ("linked");
            toggle_box.set_valign (Gtk.Align.CENTER);
            toggle_box.set_margin_end (6);

            var light_toggle = new Gtk.ToggleButton ();
            light_toggle.set_icon_name (LIGHT_ICON);

            var dark_toggle = new Gtk.ToggleButton ();
            dark_toggle.set_icon_name (DARK_ICON);
            dark_toggle.set_group (light_toggle);

            // Set initial state BEFORE connecting signals
            if (theme == "dark") {
                dark_toggle.set_active (true);
            } else {
                light_toggle.set_active (true);
            }

            // Connect signals AFTER initial state to avoid spurious handlers
            light_toggle.toggled.connect (() => {
                if (light_toggle.get_active ()) {
                    on_theme_toggle_changed (row, "light");
                }
            });
            dark_toggle.toggled.connect (() => {
                if (dark_toggle.get_active ()) {
                    on_theme_toggle_changed (row, "dark");
                }
            });

            toggle_box.append (light_toggle);
            toggle_box.append (dark_toggle);
            row.add_prefix (toggle_box);

            // Enable/disable switch
            var toggle = new Gtk.Switch ();
            toggle.set_valign (Gtk.Align.CENTER);
            toggle.set_active (entry.enabled);
            toggle.set_tooltip_text ("Enable or disable this command");
            toggle.state_set.connect ((state) => {
                return on_toggle_command_state (toggle, state, row);
            });
            row.add_suffix (toggle);

            // Controls box with edit and remove buttons
            var controls_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            controls_box.set_valign (Gtk.Align.CENTER);

            var edit_button = new Gtk.Button.from_icon_name ("document-edit-symbolic");
            edit_button.add_css_class ("flat");
            edit_button.set_tooltip_text ("Edit command");
            edit_button.clicked.connect (() => {
                on_edit_command_clicked (row);
            });
            controls_box.append (edit_button);

            var remove_button = new Gtk.Button.from_icon_name ("user-trash-symbolic");
            remove_button.add_css_class ("flat");
            remove_button.set_tooltip_text ("Remove command");
            remove_button.clicked.connect (() => {
                on_remove_command_clicked (row);
            });
            controls_box.append (remove_button);

            row.add_suffix (controls_box);

            update_row_state (row, entry);

            return row;
        }

        private void on_theme_toggle_changed (Gtk.ListBoxRow row, string new_theme) {
            int listbox_index = row.get_index ();
            if (listbox_index < 0 || listbox_index >= (int) row_entry_map.length) return;

            string old_theme = row_theme_map[listbox_index];
            if (old_theme == new_theme) return;

            var entry = row_entry_map[listbox_index];

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
        }

        private void update_row_state (Adw.ActionRow row, CommandEntry entry) {
            if (entry.enabled) {
                row.remove_css_class ("dim-label");
            } else {
                row.add_css_class ("dim-label");
            }
        }

        private bool on_toggle_command_state (Gtk.Switch sw, bool state, Gtk.ListBoxRow row) {
            int listbox_index = row.get_index ();
            if (listbox_index < 0) return false;

            string theme = get_row_theme (listbox_index);
            int theme_index = get_theme_relative_index (listbox_index);

            unowned List<CommandEntry>? theme_commands = commands.lookup (theme);
            if (theme_commands == null) return false;

            var entry = theme_commands.nth_data (theme_index);
            if (entry != null) {
                entry.enabled = state;
                update_row_state (row as Adw.ActionRow, entry);
                save_commands ();
            }

            return false;
        }

        // ── Drag-and-drop reordering ──────────────────────────────────────

        private void configure_listbox_for_reordering (Gtk.ListBox listbox) {
            var drop_target = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);

            drop_target.accept.connect ((drop) => {
                return drag_theme != null && drag_source_index >= 0;
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

                if (drag_theme == null || drag_source_index < 0) {
                    reset_drag_state ();
                    return false;
                }

                string source_theme = drag_theme;
                int source_display_idx = drag_source_index;
                reset_drag_state ();

                // Determine target
                var target_row = listbox.get_row_at_y ((int) y);
                if (target_row == null) return false;

                int target_display_idx = target_row.get_index ();
                string target_theme = get_row_theme (target_display_idx);

                // Only allow reordering within the same theme
                if (source_theme != target_theme) return false;

                reorder_display_command (source_display_idx, target_display_idx);
                return true;
            });

            listbox.add_controller (drop_target);
        }

        private void highlight_drop_position (Gtk.ListBox listbox, double y) {
            var row = listbox.get_row_at_y ((int) y);
            if (row != null) {
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
            drag_theme = null;
            drag_source_index = -1;
        }

        // ── Command actions ───────────────────────────────────────────────

        private void on_add_command_action () {
            show_command_dialog ("light", -1);
        }

        private void on_edit_command_clicked (Gtk.ListBoxRow row) {
            int listbox_index = row.get_index ();
            if (listbox_index < 0) return;

            string theme = get_row_theme (listbox_index);
            int theme_index = get_theme_relative_index (listbox_index);
            show_command_dialog (theme, theme_index);
        }

        private void on_remove_command_clicked (Gtk.ListBoxRow row) {
            int listbox_index = row.get_index ();
            if (listbox_index < 0 || listbox_index >= (int) row_entry_map.length) return;

            row_theme_map.remove_index ((uint) listbox_index);
            row_entry_map.remove_index ((uint) listbox_index);

            rebuild_commands_from_display_order ();
            save_commands ();
            refresh_command_list_ui ();
        }

        private void show_command_dialog (string default_theme, int index) {
            bool editing = index >= 0;
            string title = editing ? "Edit Command" : "Add Command";
            string message = editing ?
                "Update the shell command." :
                "Enter the shell command to execute on theme change.";

            var dialog = new Adw.AlertDialog (title, message);
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("save", editing ? "Save" : "Add");
            dialog.set_default_response ("save");
            dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);

            var content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            content_box.set_size_request (450, -1);

            // Theme selector (for add mode)
            Gtk.ToggleButton? light_btn = null;

            if (!editing) {
                var theme_label = new Gtk.Label ("Applies to:");
                theme_label.set_xalign (0);
                content_box.append (theme_label);

                var theme_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                theme_box.add_css_class ("linked");
                theme_box.set_halign (Gtk.Align.START);

                light_btn = new Gtk.ToggleButton ();
                light_btn.set_icon_name (LIGHT_ICON);
                light_btn.set_label ("Light");

                var dark_btn = new Gtk.ToggleButton ();
                dark_btn.set_icon_name (DARK_ICON);
                dark_btn.set_label ("Dark");
                dark_btn.set_group (light_btn);

                if (default_theme == "dark") {
                    dark_btn.set_active (true);
                } else {
                    light_btn.set_active (true);
                }

                theme_box.append (light_btn);
                theme_box.append (dark_btn);
                content_box.append (theme_box);
            }

            var entry = new Gtk.Entry ();
            entry.set_placeholder_text ("e.g. notify-send 'Theme changed'");
            content_box.append (entry);

            if (editing) {
                unowned List<CommandEntry>? theme_commands = commands.lookup (default_theme);
                if (theme_commands != null && index < (int) theme_commands.length ()) {
                    var cmd_entry = theme_commands.nth_data (index);
                    if (cmd_entry != null) {
                        entry.set_text (cmd_entry.command);
                    }
                }
            }

            dialog.set_extra_child (content_box);

            // Capture reference for closure
            Gtk.ToggleButton? _light_btn = light_btn;

            dialog.choose.begin (this, null, (obj, res) => {
                var response_id = dialog.choose.end (res);

                string theme = default_theme;
                if (!editing && _light_btn != null) {
                    theme = _light_btn.get_active () ? "light" : "dark";
                }

                on_command_dialog_response (response_id, theme, index, entry);
            });

            // Focus entry after dialog is shown
            GLib.Idle.add (() => {
                entry.grab_focus ();
                return false;
            });
        }

        private void on_command_dialog_response (string response_id,
                                                  string theme, int index, Gtk.Entry entry) {
            if (response_id != "save") return;

            var command_text = entry.get_text ().strip ();
            if (command_text.length == 0) return;

            unowned List<CommandEntry>? theme_commands = commands.lookup (theme);
            if (theme_commands == null) {
                commands.replace (theme, new List<CommandEntry> ());
            }

            // Re-fetch the list after any potential replacement
            theme_commands = commands.lookup (theme);

            if (index < 0) {
                // Adding new command
                var new_entry = new CommandEntry (command_text, true);
                row_theme_map.add (theme);
                row_entry_map.add (new_entry);
                rebuild_commands_from_display_order ();
            } else if (theme_commands != null && index < (int) theme_commands.length ()) {
                // Editing existing command
                var cmd_entry = theme_commands.nth_data (index);
                if (cmd_entry != null) {
                    cmd_entry.command = command_text;
                }
            }

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
                    wp_row.set_subtitle (path.length > 0 ? Path.get_basename (path) : "None");
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

        private void on_show_shortcuts_action () {
            Gtk.ShortcutsWindow? maybe_window = shortcuts_window;

            if (maybe_window == null) {
                maybe_window = build_shortcuts_window ();
                if (maybe_window == null) return;

                Gtk.ShortcutsWindow actual_window = (!) maybe_window;
                actual_window.set_transient_for (this);
                actual_window.close_request.connect (() => {
                    shortcuts_window = null;
                    actual_window.destroy ();
                    return true;
                });

                shortcuts_window = actual_window;
            }

            Gtk.ShortcutsWindow present_window = (!) maybe_window;
            present_window.present ();
        }

        private Gtk.ShortcutsWindow? build_shortcuts_window () {
            var builder = new Gtk.Builder ();
            try {
                builder.add_from_resource (SHORTCUTS_RESOURCE);
                return builder.get_object ("shortcuts_window") as Gtk.ShortcutsWindow;
            } catch (Error e) {
                warning ("Failed to load shortcuts window: %s", e.message);
                return null;
            }
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
