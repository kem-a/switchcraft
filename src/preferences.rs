// Application preferences dialog

use adw::prelude::*;
use adw::subclass::prelude::*;
use gtk::{gio, glib};
use std::cell::{Cell, OnceCell};

use crate::bundle;
use crate::config::APP_ID;
use crate::i18n::{gettext, i18n_f};
use crate::kde;
use crate::schedule;
use crate::window::MainWindow;

// Values of the schedule-mode key, in the order of the dropdown
const SCHEDULE_MODES: [&str; 3] = ["off", "sun", "custom"];
const TIME_SPAN_DAY: i64 = 86_400_000_000;

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct PreferencesWindow {
        pub main_window: OnceCell<MainWindow>,
        pub settings: OnceCell<gio::Settings>,
        pub schedule_row: OnceCell<adw::ComboRow>,
        pub light_row: OnceCell<adw::ActionRow>,
        pub dark_row: OnceCell<adw::ActionRow>,
        pub schedule_locked: Cell<bool>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for PreferencesWindow {
        const NAME: &'static str = "SwitchcraftPreferencesWindow";
        type Type = super::PreferencesWindow;
        type ParentType = adw::PreferencesDialog;
    }

    impl ObjectImpl for PreferencesWindow {}
    impl WidgetImpl for PreferencesWindow {}
    impl AdwDialogImpl for PreferencesWindow {}
    impl PreferencesDialogImpl for PreferencesWindow {}
}

glib::wrapper! {
    pub struct PreferencesWindow(ObjectSubclass<imp::PreferencesWindow>)
        @extends adw::PreferencesDialog, adw::Dialog, gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget, gtk::ShortcutManager;
}

impl PreferencesWindow {
    pub fn new(parent: &MainWindow) -> Self {
        let obj: Self = glib::Object::builder()
            .property("title", gettext("Preferences"))
            .build();
        let imp = obj.imp();
        imp.main_window.set(parent.clone()).unwrap();
        imp.settings.set(gio::Settings::new(APP_ID)).unwrap();

        obj.build_ui();
        obj
    }

    fn settings(&self) -> &gio::Settings {
        self.imp().settings.get().unwrap()
    }

    fn main_window(&self) -> &MainWindow {
        self.imp().main_window.get().unwrap()
    }

    fn build_ui(&self) {
        let imp = self.imp();
        let settings = self.settings().clone();
        let general_page = adw::PreferencesPage::new();
        self.add(&general_page);

        let kde = kde::get_desktop() == "kde";
        let kde_auto = kde && kde::is_kde_auto_switch_enabled();
        imp.schedule_locked.set(kde_auto);

        let schedule_group = adw::PreferencesGroup::new();
        schedule_group.set_title(&gettext("Automatic Switching"));
        schedule_group.set_description(Some(&if kde_auto {
            gettext("KDE Plasma is set to switch global themes automatically. Turn that off to use this schedule.")
        } else if kde {
            gettext("Switch KDE's default light and dark global themes on a schedule. Needs background monitoring.")
        } else {
            gettext("Switch between light and dark style on a schedule. Needs background monitoring.")
        }));
        general_page.add(&schedule_group);

        // KDE's own switch and this schedule would fight over the theme
        if kde_auto {
            let kde_row = adw::ActionRow::new();
            kde_row.set_title(&gettext("Automatic Switching Is Set in KDE"));
            kde_row.set_subtitle(&gettext(
                "Turn off “Switch to Dark Mode at Night” in System Settings to use this schedule.",
            ));

            let warning_icon = gtk::Image::from_icon_name("dialog-warning-symbolic");
            warning_icon.add_css_class("warning");
            kde_row.add_prefix(&warning_icon);

            let settings_button = gtk::Button::with_label(&gettext("Open Settings"));
            settings_button.set_valign(gtk::Align::Center);
            settings_button.connect_clicked(glib::clone!(
                #[weak(rename_to = obj)]
                self,
                move |_| obj.open_kde_settings()
            ));
            kde_row.add_suffix(&settings_button);
            kde_row.set_activatable_widget(Some(&settings_button));
            schedule_group.add(&kde_row);
        }

        let schedule_row = adw::ComboRow::new();
        schedule_row.set_title(&gettext("Schedule"));
        schedule_row.set_model(Some(&gtk::StringList::new(&[
            &gettext("Off"),
            &gettext("Sunset to Sunrise"),
            &gettext("Custom Times"),
        ])));
        let mode = settings.string("schedule-mode");
        for (i, schedule_mode) in SCHEDULE_MODES.iter().enumerate() {
            if *schedule_mode == mode {
                schedule_row.set_selected(i as u32);
            }
        }
        imp.schedule_row.set(schedule_row.clone()).unwrap();
        schedule_row.connect_selected_notify(glib::clone!(
            #[weak(rename_to = obj)]
            self,
            move |row| {
                let _ = obj
                    .settings()
                    .set_string("schedule-mode", SCHEDULE_MODES[row.selected() as usize]);
                obj.update_schedule_rows();
            }
        ));
        let light_row = self.create_time_row(&gettext("Light From"), "light-time");
        let dark_row = self.create_time_row(&gettext("Dark From"), "dark-time");
        schedule_group.add(&schedule_row);
        schedule_group.add(&light_row);
        schedule_group.add(&dark_row);
        imp.light_row.set(light_row).unwrap();
        imp.dark_row.set(dark_row).unwrap();

        // The monitor saves the location when GeoClue finds one
        settings.connect_changed(
            Some("last-coordinates"),
            glib::clone!(
                #[weak(rename_to = obj)]
                self,
                move |_, _| obj.update_schedule_rows()
            ),
        );
        self.update_schedule_rows();

        let bundle_group = adw::PreferencesGroup::new();
        bundle_group.set_title(&gettext("Configuration"));
        bundle_group.set_description(Some(&gettext(
            "Import or export commands and constants together as a zip archive.",
        )));
        general_page.add(&bundle_group);

        let import_row = adw::ActionRow::new();
        import_row.set_title(&gettext("Import Configuration"));
        import_row.set_subtitle(&gettext(
            "Replace local commands and constants from a zip file.",
        ));
        import_row.set_activatable(false);
        let import_button = gtk::Button::with_label(&gettext("Import"));
        import_button.set_valign(gtk::Align::Center);
        import_button.connect_clicked(glib::clone!(
            #[weak(rename_to = obj)]
            self,
            move |_| obj.import_configuration()
        ));
        import_row.add_suffix(&import_button);
        bundle_group.add(&import_row);

        let export_row = adw::ActionRow::new();
        export_row.set_title(&gettext("Export Configuration"));
        export_row.set_subtitle(&gettext("Save commands and constants into a zip file."));
        export_row.set_activatable(false);
        let export_button = gtk::Button::with_label(&gettext("Export"));
        export_button.set_valign(gtk::Align::Center);
        export_button.connect_clicked(glib::clone!(
            #[weak(rename_to = obj)]
            self,
            move |_| obj.export_configuration()
        ));
        export_row.add_suffix(&export_button);
        bundle_group.add(&export_row);

        let danger_group = adw::PreferencesGroup::new();
        danger_group.set_title(&gettext("Danger Zone"));
        danger_group.set_description(Some(&gettext(
            "Remove all saved commands and constants from this device.",
        )));
        general_page.add(&danger_group);

        let delete_row = adw::ActionRow::new();
        delete_row.set_title(&gettext("Delete All Configuration"));
        delete_row.set_subtitle(&gettext(
            "Deletes commands.json and constants.json. This cannot be undone.",
        ));
        delete_row.set_activatable(false);
        let delete_button = gtk::Button::with_label(&gettext("Delete"));
        delete_button.set_valign(gtk::Align::Center);
        delete_button.add_css_class("destructive-action");
        delete_button.connect_clicked(glib::clone!(
            #[weak(rename_to = obj)]
            self,
            move |_| obj.show_delete_confirmation()
        ));
        delete_row.add_suffix(&delete_button);
        danger_group.add(&delete_row);
    }

    fn update_schedule_rows(&self) {
        let imp = self.imp();
        let schedule_row = imp.schedule_row.get().unwrap();
        let light_row = imp.light_row.get().unwrap();
        let dark_row = imp.dark_row.get().unwrap();
        let locked = imp.schedule_locked.get();
        let mode = SCHEDULE_MODES[schedule_row.selected() as usize];
        light_row.set_visible(mode == "custom");
        dark_row.set_visible(mode == "custom");
        light_row.set_sensitive(!locked);
        dark_row.set_sensitive(!locked);
        schedule_row.set_sensitive(!locked);
        schedule_row.set_subtitle(&if mode == "sun" {
            self.get_sun_times_text()
        } else {
            String::new()
        });
    }

    fn get_sun_times_text(&self) -> String {
        let Some((latitude, longitude)) = schedule::get_location(self.settings()) else {
            return gettext("Location unknown");
        };
        let now = glib::DateTime::now_local().expect("local time");
        let (sunrise, sunset) = schedule::get_sun_times(latitude, longitude, &now);
        let day_length = sunset.difference(&sunrise).as_microseconds();
        if day_length == 0 {
            return gettext("The sun stays down today");
        }
        if day_length >= TIME_SPAN_DAY {
            return gettext("The sun stays up today");
        }
        let format =
            |time: &glib::DateTime| time.format("%R").map(|s| s.to_string()).unwrap_or_default();
        i18n_f(
            // xgettext:c-format
            "Sunrise %s, sunset %s",
            &[&format(&sunrise), &format(&sunset)],
        )
    }

    fn open_kde_settings(&self) {
        if !kde::open_kde_global_theme_settings() {
            self.show_toast(&gettext("Could not open System Settings"), true);
        }
    }

    // A button showing the time, with hour and minute pickers in its
    // popover. The time is saved when the popover closes, so the monitor
    // does not switch the style on every step.
    fn create_time_row(&self, title: &str, key: &'static str) -> adw::ActionRow {
        let time = self.settings().int(key);
        let hour_spin = create_time_spin(23, time / 60, &gettext("Hour"));
        let minute_spin = create_time_spin(59, time % 60, &gettext("Minute"));

        let picker = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        picker.append(&hour_spin);
        picker.append(&gtk::Label::new(Some(":")));
        picker.append(&minute_spin);

        let popover = gtk::Popover::new();
        popover.set_child(Some(&picker));

        let button = gtk::MenuButton::new();
        button.set_valign(gtk::Align::Center);
        button.set_popover(Some(&popover));
        button.set_label(&format!("{:02}:{:02}", time / 60, time % 60));

        let update_label = glib::clone!(
            #[weak]
            button,
            #[weak]
            hour_spin,
            #[weak]
            minute_spin,
            move || button.set_label(&format!(
                "{:02}:{:02}",
                hour_spin.value_as_int(),
                minute_spin.value_as_int()
            ))
        );
        hour_spin.connect_value_changed(glib::clone!(
            #[strong]
            update_label,
            move |_| update_label()
        ));
        minute_spin.connect_value_changed(glib::clone!(
            #[strong]
            update_label,
            move |_| update_label()
        ));
        popover.connect_closed(glib::clone!(
            #[weak(rename_to = obj)]
            self,
            #[weak]
            hour_spin,
            #[weak]
            minute_spin,
            move |_| {
                // Takes typed text that was not confirmed with Enter
                hour_spin.update();
                minute_spin.update();
                let new_time = hour_spin.value_as_int() * 60 + minute_spin.value_as_int();
                // Even an unchanged value would make the monitor re-apply the schedule
                if new_time != obj.settings().int(key) {
                    let _ = obj.settings().set_int(key, new_time);
                }
            }
        ));

        let row = adw::ActionRow::new();
        row.set_title(title);
        row.add_suffix(&button);
        row.set_activatable_widget(Some(&button));
        row
    }

    fn import_configuration(&self) {
        let dialog = gtk::FileDialog::new();
        dialog.set_title(&gettext("Import Configuration"));
        dialog.open(
            Some(self.main_window()),
            gio::Cancellable::NONE,
            glib::clone!(
                #[weak(rename_to = obj)]
                self,
                move |result| obj.finish_import(result)
            ),
        );
    }

    fn finish_import(&self, result: Result<gio::File, glib::Error>) {
        let error_message = match result {
            Ok(file) => match bundle::import_configuration_bundle(&file) {
                Ok(()) => {
                    self.main_window().reload_commands_from_storage();
                    self.show_toast(&gettext("Configuration imported"), false);
                    return;
                }
                Err(error_message) => error_message,
            },
            Err(e) if e.matches(gtk::DialogError::Cancelled) => return,
            Err(e) => e.message().to_string(),
        };
        let message = i18n_f(
            // xgettext:c-format
            "Import failed: %s",
            &[&error_message],
        );
        self.show_toast(&message, true);
    }

    fn export_configuration(&self) {
        let dialog = gtk::FileDialog::new();
        dialog.set_title(&gettext("Export Configuration"));
        dialog.set_initial_name(Some("switchcraft-config.zip"));
        dialog.save(
            Some(self.main_window()),
            gio::Cancellable::NONE,
            glib::clone!(
                #[weak(rename_to = obj)]
                self,
                move |result| obj.finish_export(result)
            ),
        );
    }

    fn finish_export(&self, result: Result<gio::File, glib::Error>) {
        let error_message = match result {
            Ok(file) => match bundle::export_configuration_bundle(&file) {
                Ok(()) => {
                    self.show_toast(&gettext("Configuration exported"), false);
                    return;
                }
                Err(error_message) => error_message,
            },
            Err(e) if e.matches(gtk::DialogError::Cancelled) => return,
            Err(e) => e.message().to_string(),
        };
        let message = i18n_f(
            // xgettext:c-format
            "Export failed: %s",
            &[&error_message],
        );
        self.show_toast(&message, true);
    }

    fn show_delete_confirmation(&self) {
        let dialog = adw::AlertDialog::new(
            Some(&gettext("Delete all configuration?")),
            Some(&gettext(
                "This will remove every command and constant. This action cannot be undone.",
            )),
        );
        dialog.add_response("cancel", &gettext("Cancel"));
        dialog.add_response("delete", &gettext("Delete"));
        dialog.set_default_response(Some("cancel"));
        dialog.set_response_appearance("delete", adw::ResponseAppearance::Destructive);

        dialog.choose(
            Some(self.main_window()),
            gio::Cancellable::NONE,
            glib::clone!(
                #[weak(rename_to = obj)]
                self,
                move |response_id| {
                    if response_id == "delete" {
                        obj.delete_configuration_files();
                    }
                }
            ),
        );
    }

    fn delete_configuration_files(&self) {
        // Stops the monitor and removes autostart before the flag is reset
        self.main_window().apply_monitoring_state(false);
        match bundle::delete_configuration_files(self.settings()) {
            Ok(()) => {
                self.main_window().reload_commands_from_storage();
                self.show_toast(&gettext("Configuration deleted"), false);
            }
            Err(error_message) => {
                let message = i18n_f(
                    // xgettext:c-format
                    "Delete failed: %s",
                    &[&error_message],
                );
                self.show_toast(&message, true);
            }
        }
    }

    fn show_toast(&self, message: &str, is_error: bool) {
        self.main_window().show_toast(message, is_error);
    }
}

fn create_time_spin(max: i32, value: i32, label: &str) -> gtk::SpinButton {
    let spin = gtk::SpinButton::with_range(0.0, max as f64, 1.0);
    spin.set_orientation(gtk::Orientation::Vertical);
    spin.set_wrap(true);
    spin.set_width_chars(2);
    spin.set_alignment(0.5);
    spin.update_property(&[gtk::accessible::Property::Label(label)]);
    // Two digits, like a clock. Connected first, so it formats the initial
    // value too.
    spin.connect_output(|source| {
        source.set_text(&format!("{:02}", source.value_as_int()));
        glib::Propagation::Stop
    });
    spin.set_value(value as f64);
    spin
}
