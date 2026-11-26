// Process.spawn_async, Process.spawn_sync and GLib.Environ through the same
// GLib calls the Vala version used

use gtk::glib;
use gtk::glib::ffi as gffi;
use gtk::glib::translate::{FromGlibPtrFull, IntoGlib};
use std::ffi::{CStr, CString, OsStr, OsString, c_char};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::Path;

use crate::util::cstr;

// envp None inherits the environment, like passing null in Vala
pub fn spawn_async(
    argv: &[&str],
    envp: Option<&[OsString]>,
    flags: glib::SpawnFlags,
) -> Result<glib::Pid, glib::Error> {
    let argv: Vec<&Path> = argv.iter().map(Path::new).collect();
    let inherited;
    let envp = match envp {
        Some(env) => env,
        None => {
            inherited = glib::environ();
            &inherited
        }
    };
    let envp: Vec<&Path> = envp.iter().map(Path::new).collect();
    glib::spawn_async(None::<&Path>, &argv, &envp, flags, None)
}

// Returns the wait status, as Process.spawn_sync with no output captured
pub fn spawn_sync(argv: &[&str], flags: glib::SpawnFlags) -> Result<i32, glib::Error> {
    let owned: Vec<CString> = argv.iter().map(|a| cstr(a)).collect();
    let mut ptrs: Vec<*mut c_char> = owned.iter().map(|s| s.as_ptr() as *mut c_char).collect();
    ptrs.push(std::ptr::null_mut());
    let mut wait_status = 0;
    let mut error = std::ptr::null_mut();
    unsafe {
        let ok = gffi::g_spawn_sync(
            std::ptr::null(),
            ptrs.as_mut_ptr(),
            std::ptr::null_mut(),
            flags.into_glib(),
            None,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            &mut wait_status,
            &mut error,
        );
        if ok == 0 {
            return Err(glib::Error::from_glib_full(error));
        }
    }
    Ok(wait_status)
}

// GLib.Environ.set_variable
pub fn environ_set(env: Vec<OsString>, name: &str, value: &OsStr) -> Vec<OsString> {
    unsafe {
        let strv = gffi::g_malloc0((env.len() + 1) * std::mem::size_of::<*mut c_char>())
            as *mut *mut c_char;
        for (i, entry) in env.iter().enumerate() {
            let c = CString::new(entry.as_bytes()).unwrap_or_default();
            *strv.add(i) = gffi::g_strdup(c.as_ptr());
        }
        let n = cstr(name);
        let v = CString::new(value.as_bytes().split(|b| *b == 0).next().unwrap_or(&[]))
            .unwrap_or_default();
        let result = gffi::g_environ_setenv(strv, n.as_ptr(), v.as_ptr(), 1);
        let mut out = Vec::new();
        let mut i = 0;
        while !(*result.add(i)).is_null() {
            out.push(OsString::from_vec(
                CStr::from_ptr(*result.add(i)).to_bytes().to_vec(),
            ));
            i += 1;
        }
        gffi::g_strfreev(result);
        out
    }
}
