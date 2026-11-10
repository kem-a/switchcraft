/* PreferencesWindow.vala
 * Application preferences dialog
 *
 * Copyright (c) 2025 kem-a
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Switchcraft {

    public class PreferencesWindow : Adw.PreferencesDialog {
        // Values of the schedule-mode key, in the order of the dropdown
        private const string[] SCHEDULE_MODES = { "off", "sun", "custom" };

        private Application app;
        private MainWindow main_window;
        private Settings settings;
        private Adw.ComboRow schedule_row;
        private Adw.ActionRow light_row;
        private Adw.ActionRow dark_row;

        public PreferencesWindow (Application application, MainWindow parent) {
            Object (
                title: _("Preferences")
            );

            app = application;
            main_window = parent;
            settings = new Settings ("com.github.Switchcraft");

            build_ui ();
        }

        private void build_ui () {
            var general_page = new Adw.PreferencesPage ();
            add (general_page);

            // Plasma ignores the GNOME setting the schedule changes, and
            // switches between light and dark on its own
            bool kde = Application.get_desktop () == "kde";
            var schedule_group = new Adw.PreferencesGroup ();
            schedule_group.set_title (_("Automatic Switching"));
            schedule_group.set_description (kde
                ? _("KDE Plasma switches between light and dark itself. Turn it on in System Settings under Colors & Themes, Global Theme.")
                : _("Switch between light and dark style on a schedule. Needs background monitoring."));
            general_page.add (schedule_group);

            schedule_row = new Adw.ComboRow ();
            schedule_row.set_title (_("Schedule"));
            schedule_row.set_model (new Gtk.StringList ({ _("Off"), _("Sunset to Sunrise"), _("Custom Times") }));
            var mode = settings.get_string ("schedule-mode");
            for (uint i = 0; i < SCHEDULE_MODES.length; i++) {
                if (SCHEDULE_MODES[i] == mode) {
                    schedule_row.set_selected (i);
                }
            }
            schedule_row.notify["selected"].connect (() => {
                settings.set_string ("schedule-mode", SCHEDULE_MODES[schedule_row.get_selected ()]);
                update_schedule_rows ();
            });
            light_row = create_time_row (_("Light From"), "light-time");
            dark_row = create_time_row (_("Dark From"), "dark-time");
            if (!kde) {
                schedule_group.add (schedule_row);
                schedule_group.add (light_row);
                schedule_group.add (dark_row);
            }

            // The monitor saves the location when GeoClue finds one
            settings.changed["last-coordinates"].connect (() => {
                update_schedule_rows ();
            });
            update_schedule_rows ();

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

        private void update_schedule_rows () {
            var mode = SCHEDULE_MODES[schedule_row.get_selected ()];
            light_row.set_visible (mode == "custom");
            dark_row.set_visible (mode == "custom");
            schedule_row.set_subtitle (mode == "sun" ? get_sun_times_text () : "");
        }

        private string get_sun_times_text () {
            double latitude, longitude;
            if (!ThemeSchedule.get_location (settings, out latitude, out longitude)) {
                return _("Location unknown");
            }
            DateTime sunrise, sunset;
            ThemeSchedule.get_sun_times (latitude, longitude, new DateTime.now_local (), out sunrise, out sunset);
            var day_length = sunset.difference (sunrise);
            if (day_length == 0) {
                return _("The sun stays down today");
            }
            if (day_length >= TimeSpan.DAY) {
                return _("The sun stays up today");
            }
            return _("Sunrise %s, sunset %s").printf (sunrise.format ("%R"), sunset.format ("%R"));
        }

        // A button showing the time, with hour and minute pickers in its
        // popover. The time is saved when the popover closes, so the
        // monitor does not switch the style on every step.
        private Adw.ActionRow create_time_row (string title, string key) {
            int time = settings.get_int (key);
            var hour_spin = create_time_spin (23, time / 60, _("Hour"));
            var minute_spin = create_time_spin (59, time % 60, _("Minute"));

            var picker = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            picker.append (hour_spin);
            picker.append (new Gtk.Label (":"));
            picker.append (minute_spin);

            var popover = new Gtk.Popover ();
            popover.set_child (picker);

            var button = new Gtk.MenuButton ();
            button.set_valign (Gtk.Align.CENTER);
            button.set_popover (popover);
            button.set_label ("%02d:%02d".printf (time / 60, time % 60));

            hour_spin.value_changed.connect (() => {
                button.set_label ("%02d:%02d".printf (hour_spin.get_value_as_int (), minute_spin.get_value_as_int ()));
            });
            minute_spin.value_changed.connect (() => {
                button.set_label ("%02d:%02d".printf (hour_spin.get_value_as_int (), minute_spin.get_value_as_int ()));
            });
            popover.closed.connect (() => {
                // Takes typed text that was not confirmed with Enter
                hour_spin.update ();
                minute_spin.update ();
                int new_time = hour_spin.get_value_as_int () * 60 + minute_spin.get_value_as_int ();
                // Even an unchanged value would make the monitor re-apply the schedule
                if (new_time != settings.get_int (key)) {
                    settings.set_int (key, new_time);
                }
            });

            var row = new Adw.ActionRow ();
            row.set_title (title);
            row.add_suffix (button);
            row.set_activatable_widget (button);
            return row;
        }

        private Gtk.SpinButton create_time_spin (int max, int value, string label) {
            var spin = new Gtk.SpinButton.with_range (0, max, 1);
            spin.set_orientation (Gtk.Orientation.VERTICAL);
            spin.set_wrap (true);
            spin.set_width_chars (2);
            spin.set_alignment (0.5f);
            spin.update_property (Gtk.AccessibleProperty.LABEL, label, -1);
            // Two digits, like a clock. Connected first, so it formats the
            // initial value too.
            spin.output.connect ((source) => {
                source.set_text ("%02d".printf (source.get_value_as_int ()));
                return true;
            });
            spin.set_value (value);
            return spin;
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
                _("This will remove every command and constant. This action cannot be undone.")
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
            main_window.apply_monitoring_state (false);
            string error_message;
            if (app.delete_configuration_files (out error_message)) {
                main_window.reload_commands_from_storage ();
                show_toast (_("Configuration deleted"));
            } else {
                show_toast (_("Delete failed: %s").printf (error_message), true);
            }
        }
        
        private void show_toast (string message, bool is_error = false) {
            main_window.show_toast (message, is_error);
        }
    }
}
