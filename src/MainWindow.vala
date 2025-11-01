/* MainWindow.vala
 * Main application window with libadwaita UI
 *
 * Copyright (c) 2021-2025 kem-a
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Switchcraft {

    public class MainWindow : Adw.ApplicationWindow {
        private HashTable<string, List<CommandEntry>> commands;
        private HashTable<string, Gtk.ListBox> listboxes;
        private HashTable<string, Gtk.Stack> content_stacks;
        private weak Gtk.ShortcutsWindow? shortcuts_window = null;
        private Adw.Banner? banner = null;
        private PreferencesWindow? preferences_window = null;
        private Adw.ToastOverlay? toast_overlay = null;
        private Gtk.Button add_button;
        private Adw.ViewStack view_stack;
        private string? drag_theme = null;
        private int drag_source_index = -1;
        
        private const string LIGHT_ICON = "weather-clear-symbolic";
        private const string DARK_ICON = "weather-clear-night-symbolic";
        
        public MainWindow (Application app) {
            Object (application: app);
            
            set_title ("Switchcraft");
            set_default_size (850, 620);
            
            listboxes = new HashTable<string, Gtk.ListBox> (str_hash, str_equal);
            content_stacks = new HashTable<string, Gtk.Stack> (str_hash, str_equal);
            
            load_commands_from_application ();
            
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
            
            // Menu button (rightmost)
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
            
            // View stack for light/dark pages
            view_stack = new Adw.ViewStack ();
            
            // Create view switcher for header (adapts automatically)
            var view_switcher_title = new Adw.ViewSwitcherTitle ();
            view_switcher_title.set_stack (view_stack);
            view_switcher_title.set_title (get_title ());
            header_bar.set_title_widget (view_switcher_title);
            
            // Create banner for logout notification
            banner = new Adw.Banner ("Log out and back in to start background monitoring");
            banner.set_button_label ("Log Out");
            banner.button_clicked.connect (on_banner_logout_clicked);
            banner.set_revealed (false);
            
            // Create content box with banner and view stack
            var content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            content_box.append (banner);
            content_box.append (view_stack);
            
            toolbar_view.set_content (content_box);

            toast_overlay = new Adw.ToastOverlay ();
            toast_overlay.set_child (toolbar_view);
            set_content (toast_overlay);

            // Build theme pages
            foreach (var theme in new string[] {"light", "dark"}) {
                var page = build_theme_page (theme);
                var icon_name = theme == "light" ? LIGHT_ICON : DARK_ICON;
                
                var stack_page = view_stack.add_titled (page, theme, theme.up (1).substring (0, 1) + theme.substring (1));
                stack_page.set_icon_name (icon_name);
            }
            
            view_stack.notify["visible-child-name"].connect (on_visible_theme);
            update_add_button_tooltip ();
            
            // Create view switcher bar for bottom (visible on narrow windows)
            var switcher_bar = new Adw.ViewSwitcherBar ();
            switcher_bar.set_stack (view_stack);
            toolbar_view.add_bottom_bar (switcher_bar);
            view_switcher_title.bind_property ("title-visible", switcher_bar, "reveal",
                GLib.BindingFlags.SYNC_CREATE);
            
        }
        
        private Gtk.Widget build_theme_page (string theme) {
            var page_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 18);
            page_box.set_margin_top (24);
            page_box.set_margin_bottom (24);
            page_box.set_margin_start (24);
            page_box.set_margin_end (24);
            
            var description = new Gtk.Label ("Commands run when GNOME switches to the %s theme.".printf (theme));
            description.set_xalign (0);
            description.set_wrap (true);
            description.add_css_class ("body");
            page_box.append (description);
            
            var listbox = new Gtk.ListBox ();
            listbox.set_selection_mode (Gtk.SelectionMode.SINGLE);
            listbox.add_css_class ("boxed-list");
            configure_listbox_for_reordering (theme, listbox);
            
            var scrolled = new Gtk.ScrolledWindow ();
            scrolled.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            scrolled.set_hexpand (true);
            scrolled.set_vexpand (true);
            scrolled.set_child (listbox);
            
            var placeholder = new Adw.StatusPage ();
            placeholder.set_icon_name ("list-add-symbolic");
            placeholder.set_title ("No commands yet");
            placeholder.set_description (
                "Click the + button or (Ctrl+N) to add a shell command that runs when %s theme activates".printf (theme)
            );
            
            var stack = new Gtk.Stack ();
            stack.set_transition_type (Gtk.StackTransitionType.CROSSFADE);
            stack.set_hexpand (true);
            stack.set_vexpand (true);
            stack.add_named (scrolled, "list");
            stack.add_named (placeholder, "placeholder");
            
            page_box.append (stack);
            
            listboxes.insert (theme, listbox);
            content_stacks.insert (theme, stack);
            refresh_theme_list (theme);
            
            return page_box;
        }

        private void refresh_theme_list (string theme) {
            var listbox = listboxes.lookup (theme);
            var stack = content_stacks.lookup (theme);
            
            if (listbox == null || stack == null) {
                return;
            }
            
            // Clear existing rows
            Gtk.ListBoxRow? row = listbox.get_row_at_index (0);
            while (row != null) {
                listbox.remove (row);
                row = listbox.get_row_at_index (0);
            }
            
            // Add rows for commands
            unowned List<CommandEntry>? theme_commands = commands.lookup (theme);
            if (theme_commands != null) {
                foreach (var entry in theme_commands) {
                    listbox.append (create_command_row (theme, entry));
                }
            }
            
            bool has_commands = theme_commands != null && theme_commands.length () > 0;
            stack.set_visible_child_name (has_commands ? "list" : "placeholder");
        }

        private void configure_listbox_for_reordering (string theme, Gtk.ListBox listbox) {
            var drop_target = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);

            drop_target.accept.connect ((drop) => {
                return drag_active_for_theme (theme);
            });

            drop_target.enter.connect ((x, y) => {
                if (!drag_active_for_theme (theme)) {
                    listbox.drag_unhighlight_row ();
                    return (Gdk.DragAction) 0;
                }

                highlight_drop_position (listbox, y);
                return Gdk.DragAction.MOVE;
            });

            drop_target.motion.connect ((x, y) => {
                if (!drag_active_for_theme (theme)) {
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

                if (!drag_active_for_theme (theme)) {
                    reset_drag_state ();
                    return false;
                }

                int source_index = drag_source_index;
                int target_index = determine_drop_index (theme, listbox, y);

                reset_drag_state ();

                if (source_index < 0 || target_index < 0) {
                    return false;
                }

                reorder_command (theme, source_index, target_index);
                return true;
            });

            listbox.add_controller (drop_target);
        }

        private bool drag_active_for_theme (string theme) {
            return drag_theme != null && drag_theme == theme && drag_source_index >= 0;
        }

        private void highlight_drop_position (Gtk.ListBox listbox, double y) {
            var row = listbox.get_row_at_y ((int) y);
            if (row != null) {
                listbox.drag_highlight_row (row);
            } else {
                listbox.drag_unhighlight_row ();
            }
        }

        private int determine_drop_index (string theme, Gtk.ListBox listbox, double y) {
            unowned List<CommandEntry>? theme_commands = commands.lookup (theme);
            int command_count = theme_commands != null ? (int) theme_commands.length () : 0;

            var row = listbox.get_row_at_y ((int) y);
            if (row == null) {
                return command_count;
            }
            
            return row.get_index ();
        }

        private void reorder_command (string theme, int source_index, int target_index) {
            unowned List<CommandEntry>? theme_commands = commands.lookup (theme);
            if (theme_commands == null) {
                return;
            }

            int length = (int) theme_commands.length ();
            if (length == 0 || source_index < 0 || source_index >= length) {
                return;
            }

            if (target_index < 0) {
                target_index = 0;
            }
            if (target_index > length) {
                target_index = length;
            }

            if (target_index == source_index || target_index == source_index + 1) {
                return;
            }

            CommandEntry[] ordered = new CommandEntry[length];
            int idx = 0;
            for (unowned List<CommandEntry>? link = theme_commands; link != null; link = link.next) {
                ordered[idx++] = link.data;
            }

            var moved = ordered[source_index];

            if (target_index > source_index) {
                for (int i = source_index; i < target_index - 1; i++) {
                    ordered[i] = ordered[i + 1];
                }
                ordered[target_index - 1] = moved;
            } else if (target_index < source_index) {
                for (int i = source_index; i > target_index; i--) {
                    ordered[i] = ordered[i - 1];
                }
                ordered[target_index] = moved;
            } else {
                return;
            }

            var new_list = new List<CommandEntry> ();
            foreach (var entry in ordered) {
                new_list.append (entry);
            }

            commands.replace (theme, (owned) new_list);
            save_commands ();
            refresh_theme_list (theme);
        }

        private void reset_drag_state () {
            drag_theme = null;
            drag_source_index = -1;
        }

        private Adw.ActionRow create_command_row (string theme, CommandEntry entry) {
            var row = new Adw.ActionRow ();
            row.set_title (entry.command);
            row.set_activatable (false);

            var drag_handle = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            drag_handle.set_valign (Gtk.Align.CENTER);
            drag_handle.set_margin_end (6);
            drag_handle.set_tooltip_text ("Drag to reorder");

            var drag_icon = new Gtk.Image.from_icon_name ("drag-handle-symbolic");
            drag_icon.add_css_class ("dim-label");
            drag_handle.append (drag_icon);
            row.add_prefix (drag_handle);

            var drag_source = new Gtk.DragSource ();
            drag_source.set_actions (Gdk.DragAction.MOVE);
            drag_source.prepare.connect ((x, y) => {
                var listbox = listboxes.lookup (theme);
                if (listbox == null) {
                    return (Gdk.ContentProvider?) null;
                }

                int index = row.get_index ();
                if (index < 0) {
                    reset_drag_state ();
                    return (Gdk.ContentProvider?) null;
                }

                drag_theme = theme;
                drag_source_index = index;

                GLib.Value value = GLib.Value (typeof (string));
                value.set_string (theme);
                return new Gdk.ContentProvider.for_value (value);
            });
            drag_source.drag_end.connect ((drag, delete_data) => {
                reset_drag_state ();
            });
            drag_source.drag_cancel.connect ((reason, delete_data) => {
                reset_drag_state ();
                return false;
            });
            drag_handle.add_controller (drag_source);
            
            // Enable/disable toggle
            var toggle = new Gtk.Switch ();
            toggle.set_valign (Gtk.Align.CENTER);
            toggle.set_active (entry.enabled);
            toggle.set_tooltip_text ("Enable or disable this command");
            toggle.state_set.connect ((state) => {
                return on_toggle_command_state (toggle, state, theme, row);
            });
            row.add_suffix (toggle);
            
            // Controls box with edit and remove buttons
            var controls_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            controls_box.set_valign (Gtk.Align.CENTER);

            var edit_button = new Gtk.Button.from_icon_name ("document-edit-symbolic");
            edit_button.add_css_class ("flat");
            edit_button.set_tooltip_text ("Edit command");
            edit_button.clicked.connect (() => {
                on_edit_command_clicked (theme, row);
            });
            controls_box.append (edit_button);
            
            var remove_button = new Gtk.Button.from_icon_name ("user-trash-symbolic");
            remove_button.add_css_class ("flat");
            remove_button.set_tooltip_text ("Remove command");
            remove_button.clicked.connect (() => {
                on_remove_command_clicked (theme, row);
            });
            controls_box.append (remove_button);
            
            row.add_suffix (controls_box);
            
            update_row_state (row, entry);

            return row;
        }
        
        private void update_row_state (Adw.ActionRow row, CommandEntry entry) {
            row.set_subtitle (entry.enabled ? "" : "Disabled");
            if (entry.enabled) {
                row.remove_css_class ("dim-label");
            } else {
                row.add_css_class ("dim-label");
            }
        }
        
        private bool on_toggle_command_state (Gtk.Switch sw, bool state, string theme, Gtk.ListBoxRow row) {
            var index = row.get_index ();
            if (index < 0) {
                return false;
            }
            
            unowned List<CommandEntry>? theme_commands = commands.lookup (theme);
            if (theme_commands == null) {
                return false;
            }
            
            var entry = theme_commands.nth_data (index);
            if (entry != null) {
                entry.enabled = state;
                update_row_state (row as Adw.ActionRow, entry);
                save_commands ();
            }
            
            return false;
        }
        
        private void on_add_command_action () {
            var theme = current_theme ();
            show_command_dialog (theme, -1);
        }
        
        private void on_edit_command_clicked (string theme, Gtk.ListBoxRow row) {
            var index = row.get_index ();
            if (index < 0) {
                return;
            }
            show_command_dialog (theme, index);
        }
        
        private void on_remove_command_clicked (string theme, Gtk.ListBoxRow row) {
            var index = row.get_index ();
            if (index < 0) {
                return;
            }
            
            unowned List<CommandEntry>? theme_commands = commands.lookup (theme);
            if (theme_commands != null && index < theme_commands.length ()) {
                // Remove entry at index
                var new_list = new List<CommandEntry> ();
                int i = 0;
                foreach (var entry in theme_commands) {
                    if (i != index) {
                        new_list.append (entry);
                    }
                    i++;
                }
                commands.replace (theme, (owned) new_list);
                
                save_commands ();
                refresh_theme_list (theme);
            }
        }

        private void show_command_dialog (string theme, int index) {
            bool editing = index >= 0;
            string title = editing ? "Edit Command" : "Add Command";
            string message = editing ?
                "Update the shell command executed for the %s theme.".printf (theme) :
                "Enter the shell command to run when the %s theme activates.".printf (theme);
            
            var dialog = new Adw.MessageDialog (this, title, message);
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("save", editing ? "Save" : "Add");
            dialog.set_default_response ("save");
            dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
            
            var entry = new Gtk.Entry ();
            entry.set_placeholder_text ("e.g. notify-send 'Switched to %s theme'".printf (theme.up (1).substring (0, 1) + theme.substring (1)));
            
            if (editing) {
                unowned List<CommandEntry>? theme_commands = commands.lookup (theme);
                if (theme_commands != null && index < theme_commands.length ()) {
                    var cmd_entry = theme_commands.nth_data (index);
                    if (cmd_entry != null) {
                        entry.set_text (cmd_entry.command);
                    }
                }
            }
            
            dialog.set_extra_child (entry);
            
            dialog.response.connect ((response_id) => {
                on_command_dialog_response (dialog, response_id, theme, index, entry);
            });
            
            dialog.present ();
            
            // Focus entry after dialog is shown
            GLib.Idle.add (() => {
                entry.grab_focus ();
                return false;
            });
        }
        
        private void on_command_dialog_response (Adw.MessageDialog dialog, string response_id,
                                                  string theme, int index, Gtk.Entry entry) {
            if (response_id != "save") {
                dialog.destroy ();
                return;
            }
            
            var command_text = entry.get_text ().strip ();
            if (command_text.length == 0) {
                dialog.destroy ();
                return;
            }
            
            unowned List<CommandEntry>? theme_commands = commands.lookup (theme);
            if (theme_commands == null) {
                var new_list = new List<CommandEntry> ();
                commands.replace (theme, (owned) new_list);
            }
            
            // Re-fetch the list after any potential replacement
            theme_commands = commands.lookup (theme);

            if (index < 0) {
                // Adding new command
                var updated_list = new List<CommandEntry> ();
                if (theme_commands != null) {
                    foreach (var existing in theme_commands) {
                        updated_list.append (existing);
                    }
                }
                updated_list.append (new CommandEntry (command_text, true));
                commands.replace (theme, (owned) updated_list);
            } else if (theme_commands != null && index < theme_commands.length ()) {
                // Editing existing command
                var cmd_entry = theme_commands.nth_data (index);
                if (cmd_entry != null) {
                    cmd_entry.command = command_text;
                }
            }
            
            save_commands ();
            refresh_theme_list (theme);
            dialog.destroy ();
        }
        
        private void add_action_handler (string name, SimpleActionActivateCallback callback) {
            var action = new SimpleAction (name, null);
            action.activate.connect ((a, v) => {
                callback (a, v);
            });
            add_action (action);
        }
        
        private void on_visible_theme () {
            update_add_button_tooltip ();
        }
        
        private void update_add_button_tooltip () {
            var theme = current_theme ();
            var tooltip = "Add a command for the %s theme".printf (theme);
            add_button.set_tooltip_text (tooltip);
        }
        
        private string current_theme () {
            var name = view_stack.get_visible_child_name ();
            if (name == "light" || name == "dark") {
                return name;
            }
            return "light";
        }
        
        private void on_show_preferences_action () {
            var app = get_application () as Application;
            if (app == null) {
                return;
            }

            if (preferences_window == null) {
                preferences_window = new PreferencesWindow (app, this);
                preferences_window.close_request.connect (() => {
                    preferences_window = null;
                    return false;
                });
            }

            preferences_window.present ();
        }

        private void on_show_about_action () {
            var app = get_application () as Application;
            var dialog = new Adw.AboutDialog ();
            dialog.set_application_name ("Switchcraft");
            dialog.set_developer_name ("Arnis Kemlers");
            var about_version = "1.0.0";
            if (app != null) {
                about_version = app.get_about_version ();
            }
            dialog.set_version (about_version);
            
            // Add icon search paths for development
            var icon_theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
            var current_dir = Environment.get_current_dir ();
            var icon_dir = Path.build_filename (current_dir, "icons");
            icon_theme.add_search_path (icon_dir);
            dialog.set_application_icon ("switchcraft");
            
            dialog.set_comments ("Watches GNOME's light/dark preference and runs your shell commands when the theme changes");
            
            // GitHub and issue reporting links
            dialog.set_website ("https://github.com/kem-a/switchcraft");
            dialog.set_issue_url ("https://github.com/kem-a/switchcraft/issues");
            
            // Credits
            dialog.add_credit_section ("Contributors", {"Switchcraft Contributors"});
            
            // Legal - License information
            dialog.set_license_type (Gtk.License.GPL_3_0);
            dialog.set_copyright ("© 2025 Arnis Kemlers");
            
            dialog.present (this);
        }
        
        private void on_show_shortcuts_action () {
            Gtk.ShortcutsWindow? maybe_window = shortcuts_window;

            if (maybe_window == null) {
                maybe_window = build_shortcuts_window ();
                if (maybe_window == null) {
                    return;
                }

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
        
        private void on_show_constants_action () {
            var app = get_application () as Application;
            if (app == null) {
                return;
            }
            
            var constants_window = new ConstantsWindow (app, this);
            constants_window.present ();
        }
        
        private void on_banner_logout_clicked () {
            try {
                // Use D-Bus to call GNOME Session Manager logout
                // Mode 0 = no confirmation dialog
                var conn = Bus.get_sync (BusType.SESSION);
                conn.call_sync (
                    "org.gnome.SessionManager",
                    "/org/gnome/SessionManager",
                    "org.gnome.SessionManager",
                    "Logout",
                    new Variant ("(u)", 0),
                    null,
                    DBusCallFlags.NONE,
                    -1,
                    null
                );
            } catch (Error e) {
                warning ("Failed to logout: %s", e.message);
                // Fall back to just hiding the banner
                if (banner != null) {
                    banner.set_revealed (false);
                }
            }
        }
        
        private Gtk.ShortcutsWindow? build_shortcuts_window () {
            var builder = new Gtk.Builder ();
            try {
                builder.add_from_string ("""
                    <?xml version="1.0" encoding="UTF-8"?>
                    <interface>
                      <object class="GtkShortcutsWindow" id="shortcuts">
                        <property name="modal">True</property>
                        <child>
                          <object class="GtkShortcutsSection">
                            <property name="section-name">general</property>
                            <property name="title" translatable="yes">General</property>
                            <child>
                              <object class="GtkShortcutsGroup">
                                <property name="title" translatable="yes">Switchcraft</property>
                                <child>
                                  <object class="GtkShortcutsShortcut">
                                    <property name="title" translatable="yes">Add command</property>
                                    <property name="accelerator">&lt;Primary&gt;N</property>
                                  </object>
                                </child>
                                <child>
                                    <object class="GtkShortcutsShortcut">
                                        <property name="title" translatable="yes">Open preferences</property>
                                        <property name="accelerator">&lt;Primary&gt;comma</property>
                                    </object>
                                </child>
                                <child>
                                    <object class="GtkShortcutsShortcut">
                                        <property name="title" translatable="yes">Show keyboard shortcuts</property>
                                        <property name="accelerator">&lt;Primary&gt;question</property>
                                    </object>
                                </child>
                                <child>
                                  <object class="GtkShortcutsShortcut">
                                    <property name="title" translatable="yes">Quit</property>
                                    <property name="accelerator">&lt;Primary&gt;Q</property>
                                  </object>
                                </child>
                              </object>
                            </child>
                          </object>
                        </child>
                      </object>
                    </interface>
                """, -1);
                
                return builder.get_object ("shortcuts") as Gtk.ShortcutsWindow;
            } catch (Error e) {
                warning ("Failed to create shortcuts window: %s", e.message);
                return null;
            }
        }
        
        private void save_commands () {
            var app = get_application () as Application;
            if (app == null) {
                return;
            }
            app.save_commands (commands);
        }

        public void reload_commands_from_storage () {
            load_commands_from_application ();
            refresh_theme_list ("light");
            refresh_theme_list ("dark");
        }

        public void apply_monitoring_state (bool enabled) {
            var app = get_application () as Application;
            if (app == null) {
                return;
            }

            var previously_enabled = app.get_monitoring_enabled ();
            if (previously_enabled == enabled) {
                return;
            }

            app.set_monitoring_enabled (enabled);
            if (banner != null) {
                banner.set_revealed (enabled);
            }
        }

        public void show_toast (string message, bool is_error = false) {
            if (toast_overlay == null) {
                return;
            }

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
