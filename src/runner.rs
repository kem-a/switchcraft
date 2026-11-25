// Running the commands of a theme, and the dialog's test run

use gtk::gio;
use gtk::gio::prelude::*;
use gtk::glib;
use std::ffi::{OsStr, OsString};

use crate::builtins;
use crate::i18n::i18n_f;
use crate::spawn;
use crate::store;
use crate::util;

pub fn execute_commands(theme: &str) {
    let commands = store::get_commands();
    let (env, prefix) = build_command_env();

    for entry in commands.get(theme) {
        if entry.enabled() {
            let script = format!("{prefix}{}", entry.command());
            if let Err(e) = spawn::spawn_async(
                &["/bin/sh", "-c", &script],
                Some(&env),
                glib::SpawnFlags::SEARCH_PATH,
            ) {
                glib::g_log!(
                    glib::LogLevel::Warning,
                    "Failed to execute command: {}",
                    e.message()
                );
            }
        }
    }
}

// The environment for commands, and a shell prefix that expands $VARS in
// constant values
pub fn build_command_env() -> (Vec<OsString>, String) {
    let constants = store::get_constants();

    let mut env = glib::environ();
    // Plasma's cursor theme tool only searches ~/.icons when XCURSOR_PATH
    // is unset, while libXcursor also reads ~/.local/share/icons. Pass the
    // standard path so the tool can apply themes that the cursor scan lists.
    if util::getenv("XCURSOR_PATH").is_none_or(|p| p.is_empty()) {
        let path = builtins::get_cursor_search_dirs().join(":");
        env = spawn::environ_set(env, "XCURSOR_PATH", OsStr::new(&path));
    }
    // Constants arrive as plain variables. The prefix expands $VARS in
    // their values, like the old bash monitor's eval did.
    let mut prefix = String::new();
    for key in constants.sorted_keys() {
        let value = constants.lookup(&key).unwrap_or_default();
        env = spawn::environ_set(env, &key, OsStr::new(&value));
        if util::regex_match_simple("^[A-Za-z_][A-Za-z0-9_]*$", &key) {
            prefix.push_str(&format!(
                "__sc=$(eval \"printf '%s' \\\"${key}\\\"\" 2>/dev/null) && {key}=$__sc\n"
            ));
        }
    }
    if !prefix.is_empty() {
        prefix.push_str("unset __sc\n");
    }
    (env, prefix)
}

// Runs a command the way execute_commands does and waits for it. Gives
// None on success, else its output and exit status.
pub fn test_command(
    command: &str,
    cancellable: &gio::Cancellable,
    callback: impl FnOnce(Result<Option<String>, glib::Error>) + 'static,
) {
    let (env, prefix) = build_command_env();

    // Output goes to a file, so background jobs that keep it open do not
    // hold up the result
    let started = gio::File::new_tmp(Some("switchcraft-test-XXXXXX")).and_then(|(file, stream)| {
        stream.close(gio::Cancellable::NONE)?;
        let output_path = file
            .path()
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_default();

        let launcher = gio::SubprocessLauncher::new(gio::SubprocessFlags::STDERR_MERGE);
        launcher.set_environ(&env);
        launcher.set_stdout_file_path(Some(&output_path));
        let script = format!("{prefix}{command}");
        match launcher.spawn(&[OsStr::new("/bin/sh"), OsStr::new("-c"), OsStr::new(&script)]) {
            Ok(process) => Ok((process, output_path)),
            Err(e) => {
                util::remove(&output_path);
                Err(e)
            }
        }
    });

    let (process, output_path) = match started {
        Ok(started) => started,
        Err(e) => {
            // An async method that fails before its first yield still
            // finishes in a later main loop iteration
            glib::idle_add_local_once(move || callback(Err(e)));
            return;
        }
    };

    let waiting = process.clone();
    waiting.wait_async(Some(cancellable), move |result| {
        let outcome = match result {
            Err(e) => {
                if e.matches(gio::IOErrorEnum::Cancelled) {
                    process.force_exit();
                }
                Err(e)
            }
            Ok(()) if process.is_successful() => Ok(None),
            Ok(()) => {
                let status = if process.has_exited() {
                    i18n_f(
                        // xgettext:c-format
                        "Exited with code %d",
                        &[&process.exit_status().to_string()],
                    )
                } else {
                    i18n_f(
                        // xgettext:c-format
                        "Killed by signal %d",
                        &[&process.term_sig().to_string()],
                    )
                };
                util::get_contents(&output_path).map(|bytes| {
                    let output = util::make_valid(&bytes);
                    let output = util::strip(&output);
                    Some(if output.is_empty() {
                        status
                    } else {
                        format!("{output}\n{status}")
                    })
                })
            }
        };
        util::remove(&output_path);
        callback(outcome);
    });
}
