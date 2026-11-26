// Built-in settings: their gsettings keys, current values, the command
// lines that apply them and the values discovery offers

use gtk::gio;
use gtk::gio::prelude::*;
use gtk::glib;

use crate::i18n::{gettext, i18n_f};
use crate::kde;
use crate::store::CommandEntry;
use crate::store::Commands;
use crate::util;

// Stored for the shell theme's empty name, since "" means "not set"
pub const SHELL_THEME_DEFAULT: &str = "Default";
const USER_THEME_SCHEMA: &str = "org.gnome.shell.extensions.user-theme";
const USER_THEME_EXTENSION: &str = "user-theme@gnome-shell-extensions.gcampax.github.com";

fn get_setting_key(setting_id: &str, theme: &str) -> (&'static str, String) {
    match setting_id {
        "shell-theme" => (USER_THEME_SCHEMA, "name".to_string()),
        "wallpaper" => (
            "org.gnome.desktop.background",
            if theme == "dark" {
                "picture-uri-dark"
            } else {
                "picture-uri"
            }
            .to_string(),
        ),
        "night-light" => (
            "org.gnome.settings-daemon.plugins.color",
            "night-light-enabled".to_string(),
        ),
        _ => ("org.gnome.desktop.interface", setting_id.to_string()),
    }
}

// Built-ins are offered for the running desktop when their tool is installed
pub fn is_setting_available(setting_id: &str) -> bool {
    if setting_id == "kvantum-theme" {
        return util::find_program("kvantummanager").is_some();
    }
    if setting_id.starts_with("kde-") {
        return kde::get_desktop() == "kde" && kde::get_kde_program(setting_id).is_some();
    }
    if kde::get_desktop() != "gnome" {
        return false;
    }
    // The value row explains how to get shell themes
    if setting_id == "shell-theme" {
        return true;
    }
    let (schema_id, key) = get_setting_key(setting_id, "light");
    matches!(lookup_schema(schema_id).0, Some(schema) if schema.has_key(&key))
}

// Extensions from extensions.gnome.org keep their schema in their own
// folder, where the default schema source does not look. Returns the
// schema and that folder.
fn lookup_schema(schema_id: &str) -> (Option<gio::SettingsSchema>, Option<String>) {
    let source = gio::SettingsSchemaSource::default();
    let schema = source.as_ref().and_then(|s| s.lookup(schema_id, true));
    if schema.is_some() || schema_id != USER_THEME_SCHEMA {
        return (schema, None);
    }

    for base_dir in [util::user_data_dir().as_str(), "/usr/share"] {
        let dir = util::build_filename(&[
            base_dir,
            "gnome-shell",
            "extensions",
            USER_THEME_EXTENSION,
            "schemas",
        ]);
        if !util::exists(&util::build_filename(&[&dir, "gschemas.compiled"])) {
            continue;
        }
        match gio::SettingsSchemaSource::from_directory(&dir, source.as_ref(), false) {
            Ok(extension_source) => {
                if let Some(schema) = extension_source.lookup(schema_id, false) {
                    return (Some(schema), Some(dir));
                }
            }
            Err(e) => glib::g_log!(
                glib::LogLevel::Warning,
                "Failed to load schemas from {}: {}",
                dir,
                e.message()
            ),
        }
    }
    (None, None)
}

pub fn has_shell_theme_support() -> bool {
    lookup_schema(USER_THEME_SCHEMA).0.is_some()
}

// What GNOME currently uses, shown for settings the user has not set
pub fn get_current_theme_value(setting_id: &str, theme: &str) -> String {
    match setting_id {
        "kde-global-theme" => {
            return kde::read_config_value("kdeglobals", "KDE", "LookAndFeelPackage");
        }
        "kde-color-scheme" => {
            return kde::read_config_value("kdeglobals", "General", "ColorScheme");
        }
        "kde-plasma-style" => return kde::read_config_value("plasmarc", "Theme", "name"),
        "kde-icon-theme" => return kde::read_config_value("kdeglobals", "Icons", "Theme"),
        "kde-cursor-theme" => return kde::read_config_value("kcminputrc", "Mouse", "cursorTheme"),
        "kvantum-theme" => {
            return kde::read_config_value(
                &util::build_filename(&["Kvantum", "kvantum.kvconfig"]),
                "General",
                "theme",
            );
        }
        // Plasma keeps one per desktop
        "kde-wallpaper" => return String::new(),
        _ => {}
    }

    let (schema_id, key) = get_setting_key(setting_id, theme);
    let Some(schema) = lookup_schema(schema_id).0.filter(|s| s.has_key(&key)) else {
        return String::new();
    };

    let key_settings = gio::Settings::new_full(&schema, None::<&gio::SettingsBackend>, None);
    if setting_id == "night-light" {
        return key_settings.boolean(&key).to_string();
    }
    let value = key_settings.string(&key).to_string();
    if setting_id == "shell-theme" && value.is_empty() {
        return SHELL_THEME_DEFAULT.to_string();
    }
    if setting_id == "wallpaper" && !value.is_empty() {
        return gio::File::for_uri(&value)
            .path()
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or(value);
    }
    value
}

// The name the desktop shows for a built-in value. The stored value stays
// the package id a tool expects.
pub fn get_setting_value_label(setting_id: &str, value: &str) -> String {
    if value.is_empty() {
        return String::new();
    }
    match setting_id {
        "kde-global-theme" => {
            kde::get_kde_package_name(&util::build_filename(&["plasma", "look-and-feel"]), value)
        }
        "kde-plasma-style" => {
            kde::get_kde_package_name(&util::build_filename(&["plasma", "desktoptheme"]), value)
        }
        "kde-color-scheme" => kde::get_kde_color_scheme_name(value),
        "icon-theme" | "kde-icon-theme" | "cursor-theme" | "kde-cursor-theme" => {
            get_icon_theme_name(value)
        }
        _ => value.to_string(),
    }
}

fn get_icon_theme_name(id: &str) -> String {
    for dir in get_icon_search_dirs() {
        let path = util::build_filename(&[&dir, id, "index.theme"]);
        if !util::exists(&path) {
            continue;
        }
        let name = kde::read_key_file_value(&path, "Icon Theme", "Name");
        if !name.is_empty() {
            return name;
        }
    }
    id.to_string()
}

// The gsettings line a built-in command runs. The wallpaper sets both keys,
// so it shows whichever style GNOME is in.
pub fn build_builtin_command(setting_id: &str, value: &str) -> String {
    let q = util::shell_quote;
    match setting_id {
        "kde-global-theme" => return format!("plasma-apply-lookandfeel -a {}", q(value)),
        "kde-color-scheme" => return format!("plasma-apply-colorscheme {}", q(value)),
        "kde-plasma-style" => return format!("plasma-apply-desktoptheme {}", q(value)),
        "kde-icon-theme" => {
            let program = kde::get_kde_program(setting_id)
                .unwrap_or_else(|| "plasma-changeicons".to_string());
            return format!("{} {}", q(&program), q(value));
        }
        "kde-cursor-theme" => return format!("plasma-apply-cursortheme {}", q(value)),
        "kde-wallpaper" => return format!("plasma-apply-wallpaperimage {}", q(value)),
        "kvantum-theme" => return format!("kvantummanager --set {}", q(value)),
        _ => {}
    }

    let (schema_id, key) = get_setting_key(setting_id, "light");
    let gsettings = match lookup_schema(schema_id).1 {
        Some(schema_dir) => format!("gsettings --schemadir {}", q(&schema_dir)),
        None => "gsettings".to_string(),
    };

    if setting_id == "wallpaper" {
        // Escapes characters like # and % in the path
        let uri = q(&if value.contains("://") {
            value.to_string()
        } else {
            util::path_to_uri(value)
        });
        return format!(
            "{gsettings} set {schema_id} picture-uri {uri} && {gsettings} set {schema_id} picture-uri-dark {uri}"
        );
    }

    let name = if setting_id == "shell-theme" && value == SHELL_THEME_DEFAULT {
        ""
    } else {
        value
    };
    format!("{gsettings} set {schema_id} {key} {}", q(name))
}

pub fn scan_setting_values(setting_id: &str) -> Vec<String> {
    let strings = |values: &[&str]| values.iter().map(|v| v.to_string()).collect();
    match setting_id {
        "color-scheme" => strings(&["prefer-light", "prefer-dark", "default"]),
        "accent-color" => strings(&[
            "blue", "teal", "green", "yellow", "orange", "red", "pink", "purple", "slate",
        ]),
        "night-light" => strings(&["true", "false"]),
        "kde-global-theme" => scan_names(
            &kde::get_data_dirs(&util::build_filename(&["plasma", "look-and-feel"])),
            match_kde_package,
        ),
        "kde-color-scheme" => scan_names(&kde::get_data_dirs("color-schemes"), |_, name| {
            name.strip_suffix(".colors").map(str::to_string)
        }),
        "kde-plasma-style" => scan_names(
            &kde::get_data_dirs(&util::build_filename(&["plasma", "desktoptheme"])),
            match_kde_package,
        ),
        "kvantum-theme" => {
            let mut kvantum_dirs = kde::get_data_dirs("Kvantum");
            kvantum_dirs.push(util::build_filename(&[&util::user_config_dir(), "Kvantum"]));
            scan_names(&kvantum_dirs, |dir_path, name| {
                let config = util::build_filename(&[dir_path, name, &format!("{name}.kvconfig")]);
                util::exists(&config).then(|| name.to_string())
            })
        }
        "icon-theme" | "kde-icon-theme" => scan_icon_themes(),
        "gtk-theme" => scan_gtk_themes(),
        "cursor-theme" | "kde-cursor-theme" => scan_cursor_themes(),
        "shell-theme" => {
            let mut themes = scan_shell_themes();
            themes.insert(0, SHELL_THEME_DEFAULT.to_string());
            themes
        }
        _ => Vec::new(),
    }
}

// Sorted names matched in any of the folders, without duplicates. The
// matcher gives the name to list for a folder entry, or None to skip it.
fn scan_names(dirs: &[String], matcher: impl Fn(&str, &str) -> Option<String>) -> Vec<String> {
    let mut names: Vec<String> = Vec::new();
    for dir_path in dirs {
        let Some(entries) = util::read_dir_names(dir_path) else {
            continue;
        };
        for file_name in entries {
            let name = if file_name.starts_with('.') {
                None
            } else {
                matcher(dir_path, &file_name)
            };
            if let Some(name) = name
                && !names.contains(&name)
            {
                names.push(name);
            }
        }
    }
    names.sort();
    names
}

// Plasma packages, like global themes and Plasma styles
fn match_kde_package(dir_path: &str, name: &str) -> Option<String> {
    let json = util::build_filename(&[dir_path, name, "metadata.json"]);
    let desktop = util::build_filename(&[dir_path, name, "metadata.desktop"]);
    (util::exists(&json) || util::exists(&desktop)).then(|| name.to_string())
}

fn scan_icon_themes() -> Vec<String> {
    scan_names(&get_icon_search_dirs(), |dir_path, name| {
        util::exists(&util::build_filename(&[dir_path, name, "index.theme"]))
            .then(|| name.to_string())
    })
}

fn scan_gtk_themes() -> Vec<String> {
    scan_names(&get_theme_search_dirs(), |dir_path, name| {
        let gtk4 = util::build_filename(&[dir_path, name, "gtk-4.0"]);
        let gtk3 = util::build_filename(&[dir_path, name, "gtk-3.0"]);
        (util::is_dir(&gtk4) || util::is_dir(&gtk3)).then(|| name.to_string())
    })
}

fn scan_cursor_themes() -> Vec<String> {
    scan_names(&get_cursor_search_dirs(), |dir_path, name| {
        util::is_dir(&util::build_filename(&[dir_path, name, "cursors"])).then(|| name.to_string())
    })
}

fn scan_shell_themes() -> Vec<String> {
    scan_names(&get_theme_search_dirs(), |dir_path, name| {
        let shell_css = util::build_filename(&[dir_path, name, "gnome-shell", "gnome-shell.css"]);
        util::exists(&shell_css).then(|| name.to_string())
    })
}

fn get_icon_search_dirs() -> Vec<String> {
    let home = util::home_dir();
    vec![
        "/usr/share/icons".to_string(),
        util::build_filename(&[&home, ".local", "share", "icons"]),
        util::build_filename(&[&home, ".icons"]),
    ]
}

// The directories libXcursor searches, or XCURSOR_PATH when it is set.
// Plasma's cursor theme tool uses this path only when the variable is set;
// otherwise it leaves out ~/.local/share/icons.
pub fn get_cursor_search_dirs() -> Vec<String> {
    let home = util::home_dir();
    let mut dirs: Vec<String> = match util::getenv("XCURSOR_PATH").filter(|p| !p.is_empty()) {
        Some(path) => util::split(&path, ":")
            .into_iter()
            .map(str::to_string)
            .collect(),
        None => vec![
            util::build_filename(&[&home, ".local", "share", "icons"]),
            util::build_filename(&[&home, ".icons"]),
            "/usr/share/icons".to_string(),
            "/usr/share/pixmaps".to_string(),
            "/usr/X11R6/lib/X11/icons".to_string(),
        ],
    };

    // XCURSOR_PATH expands a leading ~/ to the home folder
    for dir in dirs.iter_mut() {
        if let Some(rest) = dir.strip_prefix("~/") {
            *dir = util::build_filename(&[&home, rest]);
        }
    }
    dirs
}

fn get_theme_search_dirs() -> Vec<String> {
    let home = util::home_dir();
    vec![
        "/usr/share/themes".to_string(),
        util::build_filename(&[&home, ".local", "share", "themes"]),
        util::build_filename(&[&home, ".themes"]),
    ]
}

pub fn get_builtin_title(setting_id: &str) -> String {
    match setting_id {
        "color-scheme" | "kde-color-scheme" => gettext("Color Scheme"),
        "accent-color" => gettext("Accent Color"),
        "icon-theme" | "kde-icon-theme" => gettext("Icon Theme"),
        "gtk-theme" => gettext("GTK Theme"),
        "cursor-theme" | "kde-cursor-theme" => gettext("Cursor Theme"),
        "shell-theme" => gettext("Shell Theme"),
        "wallpaper" | "kde-wallpaper" => gettext("Wallpaper"),
        "night-light" => gettext("Night Light"),
        "kde-global-theme" => gettext("Global Theme"),
        "kde-plasma-style" => gettext("Plasma Style"),
        "kvantum-theme" => gettext("Kvantum Theme"),
        _ => String::new(),
    }
}

// Wallpapers are picked as files instead of from a list
pub fn is_image_setting(setting_id: &str) -> bool {
    setting_id == "wallpaper" || setting_id == "kde-wallpaper"
}

fn regex_fetch(pattern: &str, text: &str) -> Option<String> {
    let regex = glib::Regex::new(
        pattern,
        glib::RegexCompileFlags::empty(),
        glib::RegexMatchFlags::empty(),
    )
    .ok()
    .flatten()?;
    let text = glib::GString::from(text);
    let info = regex
        .match_(text.as_gstr(), glib::RegexMatchFlags::empty())
        .ok()?;
    info.matches()
        .then(|| info.fetch(1).map(|s| s.to_string()).unwrap_or_default())
}

// Why a command cannot run in the theme's list, or None. Commands that
// switch to the other style would run both lists in a loop.
pub fn find_loop_conflict(command: &str, theme: &str) -> Option<String> {
    // GNOME follows its color-scheme key, KDE the window color of its color
    // scheme, which a global theme can also change
    let dark = if let Some(scheme) = regex_fetch(
        r#"color-scheme["']?\s+["']*(prefer-dark|prefer-light|default)\b"#,
        command,
    ) {
        Some(scheme == "prefer-dark")
    } else if let Some(name) = regex_fetch(r#"plasma-apply-colorscheme\s+["']?([^"'\s]+)"#, command)
    {
        kde::get_kde_scheme_dark(&name)
    } else if let Some(id) = regex_fetch(
        r#"plasma-apply-lookandfeel\s+(?:-a|--apply)\s+["']?([^"'\s]+)"#,
        command,
    ) {
        kde::get_kde_global_theme_dark(&id)
    } else {
        None
    };

    match dark {
        Some(false) if theme == "dark" => Some(gettext(
            "Switches to the light style and would loop in Dark mode",
        )),
        Some(true) if theme == "light" => Some(gettext(
            "Switches to the dark style and would loop in Light mode",
        )),
        _ => None,
    }
}

// A command or setting that already exists in this mode. This is a
// warning only, duplicates are allowed.
pub fn find_duplicate(
    commands: &Commands,
    entry: Option<&CommandEntry>,
    command: &str,
    builtin: &str,
    theme: &str,
) -> Option<String> {
    for other in commands.get(theme) {
        if Some(other) == entry {
            continue;
        }
        if !builtin.is_empty() && other.builtin() == builtin {
            let message = i18n_f(
                // xgettext:c-format
                "%s is already set in this mode",
                &[&get_builtin_title(builtin)],
            );
            glib::g_print!("{}\n", message);
            return Some(message);
        }
        if util::strip(&other.command()) == util::strip(command) {
            let message = gettext("This command is already in this mode");
            glib::g_print!("{}\n", message);
            return Some(message);
        }
    }
    None
}
