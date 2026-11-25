// The background monitor's autostart entry and process

use gtk::gio;
use gtk::gio::prelude::*;
use gtk::glib;

use crate::i18n::gettext;
use crate::spawn;
use crate::util;

// Matches the monitor binary in native and AppImage installs, but not the
// AppImage runtime, the GUI or other apps' --background-* options
const MONITOR_PATTERN: &str = "(^|/)switchcraft --background$";
const LEGACY_MONITOR_SCRIPT: &str = "switchcraft-monitor.sh";
// Only the bash process running the script, not editors or shells that
// mention its path
const LEGACY_MONITOR_PATTERN: &str = "(^|/)bash .*/switchcraft-monitor\\.sh$";

pub fn autostart_path() -> String {
    util::build_filename(&[
        &util::user_config_dir(),
        "autostart",
        "switchcraft-monitor.desktop",
    ])
}

pub fn get_monitoring_enabled(settings: &gio::Settings) -> bool {
    settings.boolean("monitoring-enabled")
}

pub fn set_monitoring_enabled(settings: &gio::Settings, enabled: bool) {
    let _ = settings.set_boolean("monitoring-enabled", enabled);

    // Manage autostart desktop entry
    if enabled {
        enable_monitoring();
    } else {
        disable_monitoring();
    }
}

pub fn enable_monitoring() {
    create_autostart_entry();
    start_monitor();
}

fn disable_monitoring() {
    remove_autostart_entry();
    // SIGTERM, so an AppImage runtime can unmount cleanly
    run_process(&["pkill", "-u", &util::user_name(), "-f", MONITOR_PATTERN]);
}

fn start_monitor() {
    if run_process(&["pgrep", "-u", &util::user_name(), "-f", MONITOR_PATTERN]) == 0 {
        return;
    }

    match spawn::spawn_async(
        &[&get_exec_path(), "--background"],
        None,
        glib::SpawnFlags::SEARCH_PATH | glib::SpawnFlags::DO_NOT_REAP_CHILD,
    ) {
        // Reap it if it exits while the GUI is still open
        Ok(pid) => {
            glib::child_watch_add_local(pid, |_, _| {});
        }
        Err(e) => glib::g_log!(
            glib::LogLevel::Warning,
            "Failed to start background monitor: {}",
            e.message()
        ),
    }
}

// Returns the exit status, or -1 if the process could not run
fn run_process(argv: &[&str]) -> i32 {
    let flags = glib::SpawnFlags::SEARCH_PATH
        | glib::SpawnFlags::STDOUT_TO_DEV_NULL
        | glib::SpawnFlags::STDERR_TO_DEV_NULL;
    match spawn::spawn_sync(argv, flags) {
        Ok(status) if libc::WIFEXITED(status) => libc::WEXITSTATUS(status),
        Ok(_) => -1,
        Err(e) => {
            glib::g_log!(
                glib::LogLevel::Warning,
                "Failed to run {}: {}",
                argv[0],
                e.message()
            );
            -1
        }
    }
}

// Inside an AppImage /proc/self/exe points into a temporary mount that is
// gone once the app exits, so use $APPIMAGE there. It is only trusted when
// this binary runs from $APPDIR, because both variables leak into processes
// started from other AppImages (e.g. a terminal).
fn get_exec_path() -> String {
    let exe_path = match util::read_link("/proc/self/exe") {
        Ok(path) => path,
        Err(e) => {
            glib::g_log!(
                glib::LogLevel::Warning,
                "Failed to resolve executable path: {}",
                e.message()
            );
            "switchcraft".to_string()
        }
    };

    let appimage = util::getenv("APPIMAGE").unwrap_or_default();
    let appdir = util::getenv("APPDIR").unwrap_or_default();
    if !appimage.is_empty() && !appdir.is_empty() && exe_path.starts_with(&format!("{appdir}/")) {
        return appimage;
    }
    exe_path
}

// Versions before 2.0 ran ~/.local/bin/switchcraft-monitor.sh from the
// same autostart file. Stop it, delete it and keep the user's choice by
// switching the built-in monitor on.
pub fn migrate_legacy_monitor(settings: &gio::Settings) {
    let script = util::build_filename(&[&util::home_dir(), ".local", "bin", LEGACY_MONITOR_SCRIPT]);
    let autostart = autostart_path();
    let mut legacy_autostart = false;
    if util::exists(&autostart) {
        match util::get_contents(&autostart) {
            Ok(contents) => {
                let end = contents
                    .iter()
                    .position(|b| *b == 0)
                    .unwrap_or(contents.len());
                legacy_autostart = contents[..end]
                    .windows(LEGACY_MONITOR_SCRIPT.len())
                    .any(|w| w == LEGACY_MONITOR_SCRIPT.as_bytes());
            }
            Err(e) => glib::g_log!(
                glib::LogLevel::Warning,
                "Failed to read autostart entry: {}",
                e.message()
            ),
        }
    }

    if !legacy_autostart && !util::exists(&script) {
        return;
    }

    run_process(&[
        "pkill",
        "-u",
        &util::user_name(),
        "-f",
        LEGACY_MONITOR_PATTERN,
    ]);
    util::remove(&script);
    // activate () then rewrites the autostart file for the new monitor
    if legacy_autostart {
        let _ = settings.set_boolean("monitoring-enabled", true);
    }
    glib::g_log!(
        glib::LogLevel::Message,
        "Replaced legacy {} with the built-in monitor",
        LEGACY_MONITOR_SCRIPT
    );
}

fn create_autostart_entry() {
    let mut exe_path = get_exec_path();
    if exe_path.contains(' ') || exe_path.contains('\t') {
        exe_path = format!("\"{exe_path}\"");
    }

    let desktop_entry = format!(
        "[Desktop Entry]\n\
         Type=Application\n\
         Name={}\n\
         Comment={}\n\
         Exec={} --background\n\
         Icon=com.github.Switchcraft\n\
         Terminal=false\n\
         Categories=Utility;GNOME;GTK;\n\
         StartupNotify=false\n\
         X-GNOME-Autostart-enabled=true\n\
         X-GNOME-Autostart-Delay=2\n\
         Hidden=false\n",
        gettext("Switchcraft Monitor"),
        gettext("Monitor theme changes and run commands"),
        exe_path
    );

    let path = autostart_path();
    util::mkdir_with_parents(&util::dirname(&path), 0o755);
    if let Err(e) = util::set_contents(&path, &desktop_entry) {
        glib::g_log!(
            glib::LogLevel::Warning,
            "Failed to create autostart entry: {}",
            e.message()
        );
    }
}

fn remove_autostart_entry() {
    let path = autostart_path();
    if util::exists(&path) {
        util::remove(&path);
    }
}
