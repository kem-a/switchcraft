/* PreferencesWindow.vala
 * Application preferences dialog
 *
 * Copyright (c) 2025 kem-a
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Switchcraft {

    public class PreferencesWindow : Adw.PreferencesDialog {
        private Application app;
        private MainWindow main_window;
        private Adw.SwitchRow monitoring_row;
        private bool loading_state = false;
        
        public PreferencesWindow (Application application, MainWindow parent) {
            Object (
                title: _("Preferences")
            );
            
            app = application;
            main_window = parent;
            
            build_ui ();
            load_state ();
        }
        
        private void build_ui () {
            var general_page = new Adw.PreferencesPage ();
            add (general_page);
            
            var monitoring_group = new Adw.PreferencesGroup ();
            monitoring_group.set_title (_("Monitoring"));
            general_page.add (monitoring_group);
            
            monitoring_row = new Adw.SwitchRow ();
            monitoring_row.set_title (_("Enable Monitor"));
            monitoring_row.set_subtitle (_("Run the background process that reacts to GNOME theme changes."));
            monitoring_group.add (monitoring_row);
            monitoring_row.notify["active"].connect (() => {
                if (loading_state) {
                    return;
                }
                main_window.apply_monitoring_state (monitoring_row.get_active ());
            });
            
            var bundle_group = new Adw.PreferencesGroup ();
            bundle_group.set_title (_("Configuration"));
            bundle_group.set_description (_("Import or export commands and constants together as a zip archive."));
            general_page.add (bundle_group);
            
            var import_row = new Adw.ActionRow ();
            import_row.set_title (_("Import Configuration"));
            import_row.set_subtitle (_("Replace local commands and constants from a zip file."));
            import_row.set_activatable (false);
            var import_button = new Gtk.Button.with_label (_("Import"));
            import_button.set_valign (Gtk.Align.CENTER);
            import_button.clicked.connect (() => {
                import_configuration.begin ();
            });
            import_row.add_suffix (import_button);
            bundle_group.add (import_row);
            
            var export_row = new Adw.ActionRow ();
            export_row.set_title (_("Export Configuration"));
            export_row.set_subtitle (_("Save commands and constants into a zip file."));
            export_row.set_activatable (false);
            var export_button = new Gtk.Button.with_label (_("Export"));
            export_button.set_valign (Gtk.Align.CENTER);
            export_button.clicked.connect (() => {
                export_configuration.begin ();
            });
            export_row.add_suffix (export_button);
            bundle_group.add (export_row);

            var danger_group = new Adw.PreferencesGroup ();
            danger_group.set_title (_("Danger Zone"));
            danger_group.set_description (_("Remove all saved commands and constants from this device."));
            general_page.add (danger_group);

            var delete_row = new Adw.ActionRow ();
            delete_row.set_title (_("Delete All Configuration"));
            delete_row.set_subtitle (_("Deletes commands.json and constants.json. This cannot be undone."));
            delete_row.set_activatable (false);
            var delete_button = new Gtk.Button.with_label (_("Delete"));
            delete_button.set_valign (Gtk.Align.CENTER);
            delete_button.add_css_class ("destructive-action");
            delete_button.clicked.connect (() => {
                show_delete_confirmation ();
            });
            delete_row.add_suffix (delete_button);
            danger_group.add (delete_row);
        }
        
        private void load_state () {
            loading_state = true;
            monitoring_row.set_active (app.get_monitoring_enabled ());
            loading_state = false;
        }
        
        private async void import_configuration () {
            var dialog = new Gtk.FileDialog ();
            dialog.set_title (_("Import Configuration"));
            try {
                var file = yield dialog.open (main_window, null);
                if (file == null) {
                    return;
                }
                string error_message;
                if (app.import_configuration_bundle (file, out error_message)) {
                    main_window.reload_commands_from_storage ();
                    load_state ();
                    show_toast (_("Configuration imported"));
                } else {
                    show_toast (_("Import failed: %s").printf (error_message), true);
                }
            } catch (Error e) {
                if (e.domain == Gtk.DialogError.quark () && e.code == Gtk.DialogError.CANCELLED) {
                    return;
                }
                show_toast (_("Import failed: %s").printf (e.message), true);
            }
        }
        
        private async void export_configuration () {
            var dialog = new Gtk.FileDialog ();
            dialog.set_title (_("Export Configuration"));
            dialog.set_initial_name ("switchcraft-config.zip");
            try {
                var file = yield dialog.save (main_window, null);
                if (file == null) {
                    return;
                }
                string error_message;
                if (app.export_configuration_bundle (file, out error_message)) {
                    show_toast (_("Configuration exported"));
                } else {
                    show_toast (_("Export failed: %s").printf (error_message), true);
                }
            } catch (Error e) {
                if (e.domain == Gtk.DialogError.quark () && e.code == Gtk.DialogError.CANCELLED) {
                    return;
                }
                show_toast (_("Export failed: %s").printf (e.message), true);
            }
        }

        private void show_delete_confirmation () {
            var dialog = new Adw.AlertDialog (
                _("Delete all configuration?"),
                _("This will remove every custom command and constant. This action cannot be undone.")
            );
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("delete", _("Delete"));
            dialog.set_default_response ("cancel");
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);

            dialog.choose.begin (main_window, null, (obj, res) => {
                var response_id = dialog.choose.end (res);
                if (response_id == "delete") {
                    delete_configuration_files ();
                }
            });
        }

        private void delete_configuration_files () {
            // Stops the monitor and removes autostart before the flag is reset
            monitoring_row.set_active (false);
            string error_message;
            if (app.delete_configuration_files (out error_message)) {
                main_window.reload_commands_from_storage ();
                show_toast (_("Commands and constants deleted"));
            } else {
                show_toast (_("Delete failed: %s").printf (error_message), true);
            }
        }
        
        private void show_toast (string message, bool is_error = false) {
            main_window.show_toast (message, is_error);
        }
    }
}
