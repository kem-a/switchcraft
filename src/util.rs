// Thin wrappers over the GLib calls the Vala version used, so paths, file
// tests, string splitting and number parsing behave exactly the same.

use gtk::glib;
use gtk::glib::ffi as gffi;
use std::ffi::{CStr, CString, c_char};

// C strings end at the first NUL, like the Vala strings did
pub fn cstr(s: &str) -> CString {
    CString::new(s.split('\0').next().unwrap_or("")).unwrap_or_default()
}

// Takes ownership of a GLib-allocated string
unsafe fn take_gstring(ptr: *mut c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    unsafe {
        let s = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        gffi::g_free(ptr.cast());
        s
    }
}

// Path.build_filename
pub fn build_filename(parts: &[&str]) -> String {
    let owned: Vec<CString> = parts.iter().map(|p| cstr(p)).collect();
    let mut ptrs: Vec<*mut c_char> = owned.iter().map(|s| s.as_ptr() as *mut c_char).collect();
    ptrs.push(std::ptr::null_mut());
    unsafe { take_gstring(gffi::g_build_filenamev(ptrs.as_mut_ptr())) }
}

// Path.get_basename
pub fn basename(path: &str) -> String {
    let c = cstr(path);
    unsafe { take_gstring(gffi::g_path_get_basename(c.as_ptr())) }
}

// Path.get_dirname
pub fn dirname(path: &str) -> String {
    let c = cstr(path);
    unsafe { take_gstring(gffi::g_path_get_dirname(c.as_ptr())) }
}

pub const FILE_TEST_IS_EXECUTABLE: gffi::GFileTest = gffi::G_FILE_TEST_IS_EXECUTABLE;

// FileUtils.test
pub fn file_test(path: &str, test: gffi::GFileTest) -> bool {
    let c = cstr(path);
    unsafe { gffi::g_file_test(c.as_ptr(), test) != 0 }
}

pub fn exists(path: &str) -> bool {
    file_test(path, gffi::G_FILE_TEST_EXISTS)
}

pub fn is_dir(path: &str) -> bool {
    file_test(path, gffi::G_FILE_TEST_IS_DIR)
}

// FileUtils.remove, 0 on success
pub fn remove(path: &str) -> i32 {
    let c = cstr(path);
    unsafe { libc::remove(c.as_ptr()) }
}

// DirUtils.remove
pub fn rmdir(path: &str) -> i32 {
    let c = cstr(path);
    unsafe { libc::rmdir(c.as_ptr()) }
}

// DirUtils.create_with_parents
pub fn mkdir_with_parents(path: &str, mode: i32) -> i32 {
    glib::mkdir_with_parents(path, mode)
}

// FileUtils.get_contents
pub fn get_contents(path: &str) -> Result<Vec<u8>, glib::Error> {
    glib::file_get_contents(path).map(|bytes| bytes.to_vec())
}

// FileUtils.set_contents
pub fn set_contents(path: &str, contents: &str) -> Result<(), glib::Error> {
    glib::file_set_contents(path, contents.as_bytes())
}

// FileUtils.read_link
pub fn read_link(path: &str) -> Result<String, glib::Error> {
    let c = cstr(path);
    let mut error = std::ptr::null_mut();
    unsafe {
        let target = gffi::g_file_read_link(c.as_ptr(), &mut error);
        if target.is_null() {
            return Err(glib::translate::FromGlibPtrFull::from_glib_full(error));
        }
        Ok(take_gstring(target))
    }
}

// Environment.get_variable
pub fn getenv(name: &str) -> Option<String> {
    glib::getenv(name).map(|v| v.to_string_lossy().into_owned())
}

// Environment.find_program_in_path
pub fn find_program(name: &str) -> Option<String> {
    glib::find_program_in_path(name).map(|p| p.to_string_lossy().into_owned())
}

pub fn user_data_dir() -> String {
    glib::user_data_dir().to_string_lossy().into_owned()
}

pub fn user_config_dir() -> String {
    glib::user_config_dir().to_string_lossy().into_owned()
}

pub fn home_dir() -> String {
    glib::home_dir().to_string_lossy().into_owned()
}

pub fn system_data_dirs() -> Vec<String> {
    glib::system_data_dirs()
        .iter()
        .map(|p| p.to_string_lossy().into_owned())
        .collect()
}

pub fn system_config_dirs() -> Vec<String> {
    glib::system_config_dirs()
        .iter()
        .map(|p| p.to_string_lossy().into_owned())
        .collect()
}

pub fn user_name() -> String {
    glib::user_name().to_string_lossy().into_owned()
}

// string.strip (): g_strstrip removes ASCII white space only
pub fn strip(s: &str) -> &str {
    s.trim_matches(|c| matches!(c, ' ' | '\t' | '\n' | '\r' | '\x0b' | '\x0c'))
}

// string.down ()
pub fn down(s: &str) -> String {
    let c = cstr(s);
    unsafe { take_gstring(gffi::g_utf8_strdown(c.as_ptr(), -1)) }
}

// string.make_valid () of file contents read as a C string
pub fn make_valid(bytes: &[u8]) -> String {
    let end = bytes.iter().position(|b| *b == 0).unwrap_or(bytes.len());
    unsafe { take_gstring(gffi::g_utf8_make_valid(bytes.as_ptr().cast(), end as isize)) }
}

// string.split (): g_strsplit gives no pieces for an empty string
pub fn split<'a>(s: &'a str, separator: &str) -> Vec<&'a str> {
    if s.is_empty() {
        Vec::new()
    } else {
        s.split(separator).collect()
    }
}

// Shell.quote
pub fn shell_quote(s: &str) -> String {
    glib::shell_quote(s).to_string_lossy().into_owned()
}

// File.new_for_path (path).get_uri ()
pub fn path_to_uri(path: &str) -> String {
    gtk::gio::prelude::FileExt::uri(&gtk::gio::File::for_path(path)).to_string()
}

// int.try_parse () with base 0, as Vala implements it with strtol
pub fn int_try_parse(s: &str) -> Option<i32> {
    let c = cstr(s);
    let start = c.as_ptr();
    let mut end: *mut c_char = std::ptr::null_mut();
    unsafe {
        *libc::__errno_location() = 0;
        let value = libc::strtol(start, &mut end, 0);
        let errno = *libc::__errno_location();
        let parsed_all = end.cast_const() == start.add(c.as_bytes().len());
        if value < i32::MIN as libc::c_long || value > i32::MAX as libc::c_long {
            return None;
        }
        (errno != libc::ERANGE && errno != libc::EINVAL && parsed_all).then_some(value as i32)
    }
}

// int.parse (), which is atoi
pub fn atoi(s: &str) -> i32 {
    let c = cstr(s);
    unsafe { libc::atoi(c.as_ptr()) }
}

// Regex.match_simple
pub fn regex_match_simple(pattern: &str, s: &str) -> bool {
    glib::Regex::match_simple(
        pattern,
        s,
        glib::RegexCompileFlags::empty(),
        glib::RegexMatchFlags::empty(),
    )
}

// unichar.isalpha () and isalnum ()
pub fn unichar_isalpha(c: char) -> bool {
    unsafe { gffi::g_unichar_isalpha(c as u32) != 0 }
}

pub fn unichar_isalnum(c: char) -> bool {
    unsafe { gffi::g_unichar_isalnum(c as u32) != 0 }
}

// Names in a folder, skipping ones that are not valid UTF-8
pub fn read_dir_names(path: &str) -> Option<Vec<String>> {
    let dir = std::fs::read_dir(path).ok()?;
    Some(
        dir.filter_map(|entry| entry.ok()?.file_name().into_string().ok())
            .collect(),
    )
}

// Hash order of a GHashTable with str_hash, as Vala's HashTable iterated
pub struct StrTable(*mut gffi::GHashTable);

impl StrTable {
    pub fn new() -> Self {
        unsafe {
            StrTable(gffi::g_hash_table_new_full(
                Some(gffi::g_str_hash),
                Some(gffi::g_str_equal),
                Some(gffi::g_free),
                Some(gffi::g_free),
            ))
        }
    }

    pub fn insert(&self, key: &str, value: &str) {
        let k = cstr(key);
        let v = cstr(value);
        unsafe {
            gffi::g_hash_table_insert(
                self.0,
                gffi::g_strdup(k.as_ptr()).cast(),
                gffi::g_strdup(v.as_ptr()).cast(),
            );
        }
    }

    pub fn remove(&self, key: &str) {
        let k = cstr(key);
        unsafe {
            gffi::g_hash_table_remove(self.0, k.as_ptr().cast());
        }
    }

    pub fn lookup(&self, key: &str) -> Option<String> {
        let k = cstr(key);
        unsafe {
            let value = gffi::g_hash_table_lookup(self.0, k.as_ptr().cast());
            (!value.is_null()).then(|| CStr::from_ptr(value.cast()).to_string_lossy().into_owned())
        }
    }

    pub fn size(&self) -> u32 {
        unsafe { gffi::g_hash_table_size(self.0) }
    }

    // Entries in the order HashTable.foreach visits them
    pub fn entries(&self) -> Vec<(String, String)> {
        let mut result = Vec::new();
        unsafe {
            let mut iter = std::mem::MaybeUninit::<gffi::GHashTableIter>::uninit();
            gffi::g_hash_table_iter_init(iter.as_mut_ptr(), self.0);
            let mut key = std::ptr::null_mut();
            let mut value = std::ptr::null_mut();
            while gffi::g_hash_table_iter_next(iter.as_mut_ptr(), &mut key, &mut value) != 0 {
                result.push((
                    CStr::from_ptr(key.cast()).to_string_lossy().into_owned(),
                    CStr::from_ptr(value.cast()).to_string_lossy().into_owned(),
                ));
            }
        }
        result
    }

    pub fn sorted_keys(&self) -> Vec<String> {
        let mut keys: Vec<String> = self.entries().into_iter().map(|(k, _)| k).collect();
        keys.sort();
        keys
    }
}

impl Drop for StrTable {
    fn drop(&mut self) {
        unsafe { gffi::g_hash_table_unref(self.0) }
    }
}

// The order a HashTable with these keys, inserted in this order, iterates in
pub fn hash_order(keys: &[&str]) -> Vec<String> {
    let table = StrTable::new();
    for key in keys {
        table.insert(key, "");
    }
    table.entries().into_iter().map(|(k, _)| k).collect()
}
