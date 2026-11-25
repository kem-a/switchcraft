// Main application class: command line, background monitor and window

use adw::prelude::*;
use adw::subclass::prelude::*;
use gtk::{gio, glib};
use std::cell::{Cell, OnceCell, RefCell};
use std::ops::ControlFlow;
use std::rc::Rc;

use crate::config::{APP_ID, VERSION};
use crate::i18n::gettext;
use crate::monitor;
use crate::runner;
use crate::schedule::ThemeSchedule;
use crate::store;
use crate::window::MainWindow;

// Commands that switch the style back, like a dark command setting
// prefer-light, would run the commands of both styles in a loop. Switches
// closer together than LOOP_GAP count as a loop, and the commands stop after
// LOOP_MAX_RUNS of them in a row.
const LOOP_GAP: i64 = 2 * 1_000_000;
const LOOP_MAX_RUNS: i32 = 4;

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct Application {
        pub settings: OnceCell<gio::Settings>,
        pub schedule: RefCell<Option<Rc<ThemeSchedule>>>,
        pub hold: RefCell<Option<gio::ApplicationHoldGuard>>,
        pub last_switch_time: Cell<i64>,
        pub quick_switches: Cell<i32>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for Application {
        const NAME: &'static str = "SwitchcraftApplication";
        type Type = super::Application;
        type ParentType = adw::Application;
    }

    impl ObjectImpl for Application {}

    impl ApplicationImpl for Application {
        fn activate(&self) {
            let obj = self.obj();
            let settings = obj.settings();
            monitor::migrate_legacy_monitor(&settings);

            // Repair the autostart path (e.g. a moved AppImage) and make sure
            // the monitor runs when it is enabled
            if obj.get_monitoring_enabled() {
                monitor::enable_monitoring();
            }

            // A second launch shows the open window instead of a new one
            let win = obj
                .active_window()
                .unwrap_or_else(|| MainWindow::new(&obj).upcast());
            win.present();
        }

        // Runs in the calling process, so the output reaches its terminal
        fn handle_local_options(&self, options: &glib::VariantDict) -> ControlFlow<glib::ExitCode> {
            if options.contains("version") {
                glib::g_print!("Switchcraft {}\n", VERSION);
                return ControlFlow::Break(glib::ExitCode::SUCCESS);
            }
            ControlFlow::Continue(())
        }

        fn command_line(&self, command_line: &gio::ApplicationCommandLine) -> glib::ExitCode {
            let obj = self.obj();
            let options = command_line.options_dict();

            if options.contains("background") {
                *self.hold.borrow_mut() = Some(obj.hold());
                let style_manager = adw::StyleManager::default();

                style_manager.connect_dark_notify(glib::clone!(
                    #[weak]
                    obj,
                    move |style_manager| {
                        obj.execute_monitored_commands(if style_manager.is_dark() {
                            "dark"
                        } else {
                            "light"
                        });
                    }
                ));

                // Initial execution
                obj.execute_monitored_commands(if style_manager.is_dark() {
                    "dark"
                } else {
                    "light"
                });

                *self.schedule.borrow_mut() = Some(ThemeSchedule::new(&obj.settings()));

                // Keep running. -1 in the Vala version, the same exit status.
                return glib::ExitCode::from(255);
            }

            obj.activate();
            glib::ExitCode::SUCCESS
        }

        fn local_command_line(
            &self,
            arguments: &mut gio::subclass::ArgumentList,
        ) -> ControlFlow<glib::ExitCode> {
            let obj = self.obj();
            if arguments
                .iter()
                .any(|arg| arg == "--background" || arg == "-b")
            {
                obj.set_flags(obj.flags() | gio::ApplicationFlags::NON_UNIQUE);
            }
            self.parent_local_command_line(arguments)
        }
    }

    impl GtkApplicationImpl for Application {}
    impl AdwApplicationImpl for Application {}
}

glib::wrapper! {
    pub struct Application(ObjectSubclass<imp::Application>)
        @extends adw::Application, gtk::Application, gio::Application,
        @implements gio::ActionGroup, gio::ActionMap;
}

impl Application {
    pub fn new() -> Self {
        let obj: Self = glib::Object::builder()
            .property("application-id", APP_ID)
            .property("flags", gio::ApplicationFlags::HANDLES_COMMAND_LINE)
            .build();

        obj.imp().settings.set(gio::Settings::new(APP_ID)).unwrap();

        store::migrate_config_files();
        store::migrate_theme_settings();

        obj.add_main_option(
            "version",
            glib::Char::from(b'v'),
            glib::OptionFlags::NONE,
            glib::OptionArg::None,
            &gettext("Show version information"),
            None,
        );
        obj.add_main_option(
            "background",
            glib::Char::from(b'b'),
            glib::OptionFlags::NONE,
            glib::OptionArg::None,
            &gettext("Run in background for theme monitoring"),
            None,
        );

        obj.set_resource_base_path(Some("/com/github/Switchcraft/"));
        obj.set_accels_for_action("win.add-command", &["<Primary>N"]);
        obj.set_accels_for_action("app.quit", &["<Primary>Q"]);
        obj.set_accels_for_action("win.show-preferences", &["<Primary>comma"]);

        // Add quit action
        let quit_action = gio::SimpleAction::new("quit", None);
        quit_action.connect_activate(glib::clone!(
            #[weak]
            obj,
            move |_, _| obj.quit()
        ));
        obj.add_action(&quit_action);

        obj
    }

    pub fn settings(&self) -> gio::Settings {
        self.imp().settings.get().unwrap().clone()
    }

    pub fn get_monitoring_enabled(&self) -> bool {
        monitor::get_monitoring_enabled(&self.settings())
    }

    pub fn set_monitoring_enabled(&self, enabled: bool) {
        monitor::set_monitoring_enabled(&self.settings(), enabled);
    }

    fn execute_monitored_commands(&self, theme: &str) {
        let imp = self.imp();
        let now = glib::monotonic_time();
        let last = imp.last_switch_time.get();
        let quick = if last > 0 && now - last < LOOP_GAP {
            imp.quick_switches.get() + 1
        } else {
            0
        };
        imp.quick_switches.set(quick);
        imp.last_switch_time.set(now);
        if quick >= LOOP_MAX_RUNS {
            glib::g_log!(
                glib::LogLevel::Warning,
                "The style switched {} times in a row, skipping {} commands to stop a loop",
                quick + 1,
                theme
            );
            return;
        }
        runner::execute_commands(theme);
    }
}
