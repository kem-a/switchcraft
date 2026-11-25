use gtk::glib;
use std::ffi::{CString, c_char};

use crate::config::GETTEXT_PACKAGE;
use crate::util;

unsafe extern "C" {
    fn bindtextdomain(domain: *const c_char, dir: *const c_char) -> *mut c_char;
    fn bind_textdomain_codeset(domain: *const c_char, codeset: *const c_char) -> *mut c_char;
    fn textdomain(domain: *const c_char) -> *mut c_char;
}

fn setlocale(locale: &str) -> bool {
    let l = CString::new(locale).unwrap();
    unsafe { !libc::setlocale(libc::LC_ALL, l.as_ptr()).is_null() }
}

pub fn init_i18n() {
    // Runs first in main, before any other thread exists
    if !setlocale("") {
        if setlocale("C.UTF-8") {
            unsafe {
                let _ = glib::setenv("LC_ALL", "C.UTF-8", true);
                let _ = glib::setenv("LANG", "C.UTF-8", true);
            }
        } else {
            setlocale("C");
            unsafe {
                let _ = glib::setenv("LC_ALL", "C", true);
                let _ = glib::setenv("LANG", "C", true);
            }
        }
    }

    let domain = util::cstr(GETTEXT_PACKAGE);
    let dir = util::cstr(&get_locale_dir());
    let codeset = util::cstr("UTF-8");
    unsafe {
        bindtextdomain(domain.as_ptr(), dir.as_ptr());
        bind_textdomain_codeset(domain.as_ptr(), codeset.as_ptr());
        textdomain(domain.as_ptr());
    }
}

fn get_locale_dir() -> String {
    // Check next to the running binary first. This covers local installs
    // and both AppImage layouts without trusting an inherited APPDIR.
    if let Ok(exe_path) = std::fs::read_link("/proc/self/exe") {
        let exe_path = exe_path.to_string_lossy();
        let local_locale =
            util::build_filename(&[&util::dirname(&exe_path), "..", "share", "locale"]);
        if util::is_dir(&local_locale) {
            return local_locale;
        }
    }

    if let Some(appdir) = util::getenv("APPDIR").filter(|a| !a.is_empty()) {
        let bundled = util::build_filename(&[&appdir, "share", "locale"]);
        if util::is_dir(&bundled) {
            return bundled;
        }

        let classic = util::build_filename(&[&appdir, "usr", "share", "locale"]);
        if util::is_dir(&classic) {
            return classic;
        }
    }

    "/usr/share/locale".to_string()
}

// _() in the Vala version
pub fn gettext(msgid: &str) -> String {
    glib::dgettext(Some(GETTEXT_PACKAGE), msgid).to_string()
}

// _("...").printf (...) for the %s and %d placeholders the strings use
pub fn i18n_f(msgid: &str, args: &[&str]) -> String {
    let format = gettext(msgid);
    let mut args = args.iter();
    let mut result = String::with_capacity(format.len());
    let mut chars = format.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '%' {
            match chars.peek() {
                Some('s') | Some('d') => {
                    chars.next();
                    result.push_str(args.next().copied().unwrap_or(""));
                    continue;
                }
                Some('%') => {
                    chars.next();
                    result.push('%');
                    continue;
                }
                _ => {}
            }
        }
        result.push(c);
    }
    result
}
