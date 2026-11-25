// Desktop detection and KDE Plasma configuration helpers

use gtk::glib;

use crate::json;
use crate::spawn;
use crate::util;

// Text of a file as a C string, which ends at the first NUL
pub fn read_text(path: &str) -> Option<String> {
    let bytes = util::get_contents(path).ok()?;
    let end = bytes.iter().position(|b| *b == 0).unwrap_or(bytes.len());
    Some(String::from_utf8_lossy(&bytes[..end]).into_owned())
}

// "gnome", "kde", or "" for other desktops
pub fn get_desktop() -> &'static str {
    let current = util::down(&util::getenv("XDG_CURRENT_DESKTOP").unwrap_or_default());
    let desktops = util::split(&current, ":");
    if desktops.contains(&"kde") {
        return "kde";
    }
    if desktops.contains(&"gnome") {
        "gnome"
    } else {
        ""
    }
}

// Full path of the Plasma tool that applies the setting, or None
pub fn get_kde_program(setting_id: &str) -> Option<String> {
    match setting_id {
        "kde-global-theme" => util::find_program("plasma-apply-lookandfeel"),
        "kde-color-scheme" => util::find_program("plasma-apply-colorscheme"),
        "kde-plasma-style" => util::find_program("plasma-apply-desktoptheme"),
        "kde-cursor-theme" => util::find_program("plasma-apply-cursortheme"),
        "kde-wallpaper" => util::find_program("plasma-apply-wallpaperimage"),
        "kde-icon-theme" => {
            // Not on PATH, and each distribution keeps it elsewhere
            for dir in [
                "/usr/libexec",
                "/usr/lib",
                "/usr/lib64/libexec",
                "/usr/lib/x86_64-linux-gnu/libexec",
                "/usr/lib/aarch64-linux-gnu/libexec",
            ] {
                let path = util::build_filename(&[dir, "plasma-changeicons"]);
                if util::file_test(&path, util::FILE_TEST_IS_EXECUTABLE) {
                    return Some(path);
                }
            }
            util::find_program("plasma-changeicons")
        }
        _ => None,
    }
}

// The subfolder in the user's and the system's data folders
pub fn get_data_dirs(subdir: &str) -> Vec<String> {
    let mut dirs = vec![util::build_filename(&[&util::user_data_dir(), subdir])];
    for dir in util::system_data_dirs() {
        dirs.push(util::build_filename(&[&dir, subdir]));
    }
    dirs
}

// Whether KDE reports the dark style for this color scheme. Like its
// portal, a window background darker than gray 192 is dark. None when the
// scheme is not found.
pub fn get_kde_scheme_dark(name: &str) -> Option<bool> {
    for dir in get_data_dirs("color-schemes") {
        let path = util::build_filename(&[&dir, &format!("{name}.colors")]);
        if !util::exists(&path) {
            continue;
        }

        // KDE color schemes also use nested group headers, which KeyFile
        // cannot parse.
        let value = read_key_file_value(&path, "Colors:Window", "BackgroundNormal");
        let parts = util::split(&value, ",");
        if parts.len() < 3 {
            return None;
        }
        let red = util::int_try_parse(util::strip(parts[0]))?;
        let green = util::int_try_parse(util::strip(parts[1]))?;
        let blue = util::int_try_parse(util::strip(parts[2]))?;
        // Wraps on overflow like the C int arithmetic did
        let gray = red
            .wrapping_mul(11)
            .wrapping_add(green.wrapping_mul(16))
            .wrapping_add(blue.wrapping_mul(5));
        return Some(gray / 32 < 192);
    }
    None
}

// A global theme applies a color scheme, which decides the style
pub fn get_kde_global_theme_dark(id: &str) -> Option<bool> {
    for dir in get_data_dirs(&util::build_filename(&["plasma", "look-and-feel"])) {
        // Not in this folder
        let Some(contents) = read_text(&util::build_filename(&[&dir, id, "contents", "defaults"]))
        else {
            continue;
        };
        // KeyFile rejects group lines like [kdeglobals][General]
        let mut in_general = false;
        for line in util::split(&contents, "\n") {
            let line = util::strip(line);
            if line.starts_with('[') {
                in_general = line == "[kdeglobals][General]";
            } else if in_general && line.starts_with("ColorScheme=") {
                return get_kde_scheme_dark(&line["ColorScheme=".len()..]);
            }
        }
        return None;
    }
    None
}

fn unescape_config_value(value: &str) -> String {
    if !value.contains('\\') {
        return value.to_string();
    }

    let bytes = value.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        let c = bytes[i];
        if c != b'\\' || i + 1 >= bytes.len() {
            out.push(c);
            i += 1;
            continue;
        }
        i += 1;
        out.push(match bytes[i] {
            b's' => b' ',
            b't' => b'\t',
            b'n' => b'\n',
            b'r' => b'\r',
            next => next,
        });
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

// KConfig files are not strict ini files. They use nested group headers
// like [Colors:Header][Inactive], which KeyFile rejects. Read the keys
// directly instead, and accept KConfig's Theme[$e].
pub fn read_key_file_value(path: &str, group: &str, key: &str) -> String {
    let Some(contents) = read_text(path) else {
        return String::new();
    };

    let mut in_group = false;
    for raw_line in util::split(&contents, "\n") {
        let line = util::strip(raw_line);
        if line.is_empty() || line.starts_with('#') || line.starts_with(';') {
            continue;
        }
        if line.starts_with('[') {
            // The first bracket is the top-level group, e.g.
            // [Colors:Header][Inactive] is Colors:Header.
            in_group = matches!(line.find(']'), Some(end) if end > 1 && &line[1..end] == group);
            continue;
        }
        if !in_group {
            continue;
        }
        let Some(equals) = line.find('=') else {
            continue;
        };
        let name = util::strip(&line[..equals]);
        if name != key && name != format!("{key}[$e]") {
            continue;
        }
        return unescape_config_value(util::strip(&line[equals + 1..]));
    }
    String::new()
}

// A value from an ini file in the config folder, as KDE keeps them, or "".
// KDE falls back to kdedefaults and the system config directories when the
// user's file has no value, so do the same here.
pub fn read_config_value(file_name: &str, group: &str, key: &str) -> String {
    let config = util::user_config_dir();
    let mut paths = vec![
        util::build_filename(&[&config, file_name]),
        util::build_filename(&[&config, "kdedefaults", file_name]),
    ];
    for dir in util::system_config_dirs() {
        paths.push(util::build_filename(&[&dir, file_name]));
        paths.push(util::build_filename(&[&dir, "kdedefaults", file_name]));
    }

    for path in paths {
        if !util::exists(&path) {
            continue;
        }
        let value = read_key_file_value(&path, group, key);
        if !value.is_empty() {
            return value;
        }
    }
    String::new()
}

fn read_config_bool(file_name: &str, group: &str, key: &str, fallback: bool) -> bool {
    let value = util::down(&read_config_value(file_name, group, key));
    if value.is_empty() {
        return fallback;
    }
    value == "true" || value == "1"
}

// Plasma's own automatic light/dark switch. When it is on, Switchcraft's
// schedule must stay out of the way.
pub fn is_kde_auto_switch_enabled() -> bool {
    get_desktop() == "kde" && read_config_bool("kdeglobals", "KDE", "AutomaticLookAndFeel", false)
}

pub fn get_kde_current_look_and_feel() -> String {
    read_config_value("kdeglobals", "KDE", "LookAndFeelPackage")
}

// The global themes Plasma's automatic switch uses. Plasma keeps these next
// to the current theme in kdeglobals.
pub fn get_kde_default_look_and_feel(dark: bool) -> String {
    let value = read_config_value(
        "kdeglobals",
        "KDE",
        if dark {
            "DefaultDarkLookAndFeel"
        } else {
            "DefaultLightLookAndFeel"
        },
    );
    if !value.is_empty() {
        return value;
    }
    if dark {
        "org.kde.breezedark.desktop"
    } else {
        "org.kde.breeze.desktop"
    }
    .to_string()
}

pub fn open_kde_global_theme_settings() -> bool {
    for name in [
        "systemsettings",
        "systemsettings5",
        "kcmshell6",
        "kcmshell5",
    ] {
        let Some(program) = util::find_program(name) else {
            continue;
        };
        match spawn::spawn_async(
            &[&program, "kcm_lookandfeel"],
            None,
            glib::SpawnFlags::SEARCH_PATH,
        ) {
            Ok(_) => return true,
            Err(e) => glib::g_log!(
                glib::LogLevel::Warning,
                "Failed to open System Settings: {}",
                e.message()
            ),
        }
    }
    false
}

pub fn get_kde_package_name(subdir: &str, id: &str) -> String {
    for dir in get_data_dirs(subdir) {
        let package_dir = util::build_filename(&[&dir, id]);
        let metadata = util::build_filename(&[&package_dir, "metadata.json"]);
        if util::exists(&metadata) {
            // On errors, try the desktop file below
            if let Ok(contents) = util::get_contents(&metadata)
                && let Ok(parser) = json::Parser::load(&contents)
                && let Some(root) = parser.root()
                && root.node_type() == json::NodeType::Object
                && let Some(plugin) = root.object().member("KPlugin")
                && plugin.node_type() == json::NodeType::Object
                && let Some(name) = plugin
                    .object()
                    .member("Name")
                    .and_then(|n| n.string_value())
                && !name.is_empty()
            {
                return name;
            }
        }

        let desktop = util::build_filename(&[&package_dir, "metadata.desktop"]);
        if util::exists(&desktop) {
            let name = read_key_file_value(&desktop, "Desktop Entry", "Name");
            if !name.is_empty() {
                return name;
            }
        }
    }
    id.to_string()
}

pub fn get_kde_color_scheme_name(id: &str) -> String {
    for dir in get_data_dirs("color-schemes") {
        let path = util::build_filename(&[&dir, &format!("{id}.colors")]);
        if !util::exists(&path) {
            continue;
        }
        let name = read_key_file_value(&path, "General", "Name");
        if !name.is_empty() {
            return name;
        }
    }
    id.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unescapes_kconfig_values() {
        assert_eq!(unescape_config_value("plain"), "plain");
        assert_eq!(
            unescape_config_value(r"a\sb\tc\nd\re\\f\x"),
            "a b\tc\nd\re\\fx"
        );
        assert_eq!(unescape_config_value(r"end\"), r"end\");
    }
}
