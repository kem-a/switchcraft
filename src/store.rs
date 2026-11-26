// Commands, constants and the legacy theme settings on disk

use gtk::gio;
use gtk::gio::prelude::*;
use gtk::glib;
use serde_json::{Map, Value};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::Rc;

use crate::builtins;
use crate::json;
use crate::util::{self, StrTable};

pub const THEME_SETTING_IDS: &[&str] = &[
    // GNOME
    "color-scheme",
    "accent-color",
    "icon-theme",
    "gtk-theme",
    "cursor-theme",
    "shell-theme",
    "wallpaper",
    "night-light",
    // KDE Plasma
    "kde-global-theme",
    "kde-color-scheme",
    "kde-plasma-style",
    "kde-icon-theme",
    "kde-cursor-theme",
    "kde-wallpaper",
    // Any desktop
    "kvantum-theme",
];

pub struct EntryData {
    pub command: RefCell<String>,
    pub enabled: Cell<bool>,
    // Index in the command list, which mixes light and dark
    pub position: Cell<i32>,
    // Set for commands made from a built-in setting, so the dialog can show
    // the setting and its value instead of the gsettings line
    pub builtin: RefCell<String>,
    pub value: RefCell<String>,
}

// Compared by identity, like the Vala objects
#[derive(Clone)]
pub struct CommandEntry(Rc<EntryData>);

impl CommandEntry {
    pub fn new(command: &str, enabled: bool) -> Self {
        CommandEntry(Rc::new(EntryData {
            command: RefCell::new(command.to_string()),
            enabled: Cell::new(enabled),
            position: Cell::new(-1),
            builtin: RefCell::new(String::new()),
            value: RefCell::new(String::new()),
        }))
    }

    pub fn with_builtin(command: &str, builtin: &str, value: &str) -> Self {
        let entry = CommandEntry::new(command, true);
        entry.set_builtin(builtin);
        entry.set_value(value);
        entry
    }

    pub fn command(&self) -> String {
        self.0.command.borrow().clone()
    }
    pub fn set_command(&self, command: &str) {
        *self.0.command.borrow_mut() = command.to_string();
    }
    pub fn enabled(&self) -> bool {
        self.0.enabled.get()
    }
    pub fn set_enabled(&self, enabled: bool) {
        self.0.enabled.set(enabled);
    }
    pub fn position(&self) -> i32 {
        self.0.position.get()
    }
    pub fn set_position(&self, position: i32) {
        self.0.position.set(position);
    }
    pub fn builtin(&self) -> String {
        self.0.builtin.borrow().clone()
    }
    pub fn set_builtin(&self, builtin: &str) {
        *self.0.builtin.borrow_mut() = builtin.to_string();
    }
    pub fn value(&self) -> String {
        self.0.value.borrow().clone()
    }
    pub fn set_value(&self, value: &str) {
        *self.0.value.borrow_mut() = value.to_string();
    }

    // Identity key for matching rows across rebuilds
    pub fn key(&self) -> usize {
        Rc::as_ptr(&self.0) as usize
    }
}

impl PartialEq for CommandEntry {
    fn eq(&self, other: &Self) -> bool {
        Rc::ptr_eq(&self.0, &other.0)
    }
}

// The Vala HashTable<string, List<CommandEntry>> with "light" and "dark"
#[derive(Clone, Default)]
pub struct Commands {
    light: Vec<CommandEntry>,
    dark: Vec<CommandEntry>,
}

impl Commands {
    pub fn get(&self, theme: &str) -> &[CommandEntry] {
        match theme {
            "light" => &self.light,
            "dark" => &self.dark,
            _ => &[],
        }
    }

    pub fn set(&mut self, theme: &str, list: Vec<CommandEntry>) {
        match theme {
            "light" => self.light = list,
            "dark" => self.dark = list,
            _ => {}
        }
    }
}

pub struct ThemeSettingValue {
    pub light: String,
    pub dark: String,
}

impl ThemeSettingValue {
    pub fn get_for_theme(&self, theme: &str) -> &str {
        if theme == "dark" {
            &self.dark
        } else {
            &self.light
        }
    }
}

fn data_dir() -> String {
    util::build_filename(&[&util::user_data_dir(), "switchcraft"])
}

pub fn config_path() -> String {
    util::build_filename(&[&data_dir(), "commands.json"])
}

pub fn constants_path() -> String {
    util::build_filename(&[&data_dir(), "constants.json"])
}

pub fn theme_settings_path() -> String {
    util::build_filename(&[&data_dir(), "theme_settings.json"])
}

pub fn get_commands() -> Commands {
    load_commands().1
}

// The flag is false if the file exists but cannot be read
pub fn load_commands() -> (bool, Commands) {
    let path = config_path();
    if !util::exists(&path) {
        return (true, Commands::default());
    }

    let parsed = util::get_contents(&path)
        .map_err(|e| e.message().to_string())
        .and_then(|contents| json::parse(&contents));
    match parsed {
        Ok(root) => (true, normalize_commands(root.as_ref())),
        Err(e) => {
            glib::g_log!(glib::LogLevel::Warning, "Failed to load commands: {}", e);
            (false, Commands::default())
        }
    }
}

pub fn save_commands(commands: &Commands) {
    let path = config_path();
    util::mkdir_with_parents(&util::dirname(&path), 0o755);
    let data = commands_to_json(commands);
    if let Err(e) = util::set_contents(&path, &data) {
        glib::g_log!(
            glib::LogLevel::Warning,
            "Failed to save commands: {}",
            e.message()
        );
    }
}

pub fn normalize_commands(root: Option<&Value>) -> Commands {
    let mut commands = Commands::default();

    let Some(root) = root.and_then(Value::as_object) else {
        return commands;
    };

    for theme in ["dark", "light"] {
        let Some(member) = root.get(theme).and_then(Value::as_array) else {
            continue;
        };

        let mut theme_commands = Vec::new();
        for node in member {
            match node {
                // String format
                Value::String(_) => {
                    if let Some(command) = json::string(node) {
                        theme_commands.push(CommandEntry::new(&command, true));
                    }
                }
                // Object format with enabled flag
                Value::Object(obj) => {
                    let Some(command) = obj.get("command").and_then(json::string) else {
                        continue;
                    };

                    let enabled = obj.get("enabled").and_then(Value::as_bool).unwrap_or(true);
                    let entry = CommandEntry::new(&command, enabled);
                    entry.set_builtin(
                        &obj.get("builtin")
                            .and_then(json::string)
                            .unwrap_or_default(),
                    );
                    entry.set_value(&obj.get("value").and_then(json::string).unwrap_or_default());
                    if let Some(position) = obj.get("position").and_then(Value::as_i64) {
                        entry.set_position(position as i32);
                    }
                    theme_commands.push(entry);
                }
                _ => {}
            }
        }
        commands.set(theme, theme_commands);
    }

    commands
}

// Members follow the order the Vala HashTable iterated "dark" and "light" in
pub fn commands_to_json(commands: &Commands) -> String {
    let mut obj = Map::new();
    for theme in util::hash_order(&["dark", "light"]) {
        let mut array = Vec::new();
        for entry in commands.get(&theme) {
            let mut entry_obj = Map::new();
            entry_obj.insert("command".into(), entry.command().into());
            entry_obj.insert("enabled".into(), entry.enabled().into());
            if entry.position() >= 0 {
                entry_obj.insert("position".into(), entry.position().into());
            }
            if !entry.builtin().is_empty() {
                entry_obj.insert("builtin".into(), entry.builtin().into());
                entry_obj.insert("value".into(), entry.value().into());
            }
            array.push(Value::Object(entry_obj));
        }
        obj.insert(theme, Value::Array(array));
    }
    json::pretty(obj)
}

pub fn get_constants() -> StrTable {
    let constants = StrTable::new();
    let path = constants_path();
    if !util::exists(&path) {
        return constants;
    }

    let parsed = util::get_contents(&path)
        .map_err(|e| e.message().to_string())
        .and_then(|contents| json::parse(&contents));
    match parsed {
        Ok(root) => {
            if let Some(obj) = root.as_ref().and_then(Value::as_object) {
                for (name, value) in obj {
                    if let Some(value) = json::string(value) {
                        constants.insert(name, &value);
                    }
                }
            }
        }
        Err(e) => glib::g_log!(glib::LogLevel::Warning, "Failed to load constants: {}", e),
    }
    constants
}

pub fn constants_to_json(constants: &StrTable) -> String {
    let mut obj = Map::new();
    for (key, value) in constants.entries() {
        obj.insert(key, value.into());
    }
    json::pretty(obj)
}

pub fn save_constants(constants: &StrTable) {
    let path = constants_path();
    util::mkdir_with_parents(&util::dirname(&path), 0o755);
    if let Err(e) = util::set_contents(&path, &constants_to_json(constants)) {
        glib::g_log!(
            glib::LogLevel::Warning,
            "Failed to save constants: {}",
            e.message()
        );
    }
}

fn get_theme_settings() -> HashMap<String, ThemeSettingValue> {
    let path = theme_settings_path();
    if !util::exists(&path) {
        return HashMap::new();
    }

    let parsed = util::get_contents(&path)
        .map_err(|e| e.message().to_string())
        .and_then(|contents| json::parse(&contents));
    match parsed {
        Ok(root) => match root.as_ref().and_then(Value::as_object) {
            Some(obj) => parse_theme_settings(obj),
            None => HashMap::new(),
        },
        Err(e) => {
            glib::g_log!(
                glib::LogLevel::Warning,
                "Failed to load theme settings: {}",
                e
            );
            HashMap::new()
        }
    }
}

pub fn parse_theme_settings(obj: &Map<String, Value>) -> HashMap<String, ThemeSettingValue> {
    let mut result = HashMap::new();
    for (id, node) in obj {
        if let Some(setting) = node.as_object() {
            let light = setting
                .get("light")
                .and_then(json::string)
                .unwrap_or_default();
            let dark = setting
                .get("dark")
                .and_then(json::string)
                .unwrap_or_default();
            result.insert(id.clone(), ThemeSettingValue { light, dark });
        }
    }
    result
}

// Versions with a Built-in page kept these settings in theme_settings.json.
// They are regular commands now.
pub fn migrate_theme_settings() {
    let path = theme_settings_path();
    if !util::exists(&path) {
        return;
    }

    let (ok, mut commands) = load_commands();
    if !ok {
        // Saving now would replace a commands file we could not read
        return;
    }
    add_theme_setting_commands(&mut commands, &get_theme_settings());
    save_commands(&commands);
    util::remove(&path);
    glib::g_log!(glib::LogLevel::Message, "Converted {} into commands", path);
}

pub fn add_theme_setting_commands(
    commands: &mut Commands,
    settings_data: &HashMap<String, ThemeSettingValue>,
) {
    for theme in ["light", "dark"] {
        let mut list: Vec<CommandEntry> = commands.get(theme).to_vec();
        for setting_id in THEME_SETTING_IDS {
            let value = settings_data
                .get(*setting_id)
                .map(|v| v.get_for_theme(theme))
                .unwrap_or("");
            if !value.is_empty() {
                list.push(CommandEntry::with_builtin(
                    &builtins::build_builtin_command(setting_id, value),
                    setting_id,
                    value,
                ));
            }
        }
        commands.set(theme, list);
    }
}

pub fn migrate_config_files() {
    let old_dir = util::build_filename(&[&util::user_config_dir(), "switchcraft"]);
    let new_dir = util::dirname(&config_path());

    if util::is_dir(&old_dir) && !util::exists(&new_dir) {
        util::mkdir_with_parents(&util::dirname(&new_dir), 0o755);
        let old_file = gio::File::for_path(&old_dir);
        let new_file = gio::File::for_path(&new_dir);
        if old_file.query_exists(gio::Cancellable::NONE) {
            match old_file.move_(
                &new_file,
                gio::FileCopyFlags::NONE,
                gio::Cancellable::NONE,
                None,
            ) {
                Ok(()) => glib::g_log!(
                    glib::LogLevel::Message,
                    "Migrated configuration from {} to {}",
                    old_dir,
                    new_dir
                ),
                Err(e) => glib::g_log!(
                    glib::LogLevel::Warning,
                    "Failed to migrate configuration: {}",
                    e.message()
                ),
            }
        }
    } else if util::is_dir(&old_dir) {
        // Both dirs exist: move only what the new dir lacks. Files present
        // in both stay in the old dir untouched.
        let result = std::fs::read_dir(&old_dir)
            .map_err(|e| e.to_string())
            .and_then(|dir| {
                for entry in dir.flatten() {
                    let name = entry.file_name().to_string_lossy().into_owned();
                    let target = util::build_filename(&[&new_dir, &name]);
                    if !util::exists(&target) {
                        gio::File::for_path(util::build_filename(&[&old_dir, &name]))
                            .move_(
                                &gio::File::for_path(&target),
                                gio::FileCopyFlags::NONE,
                                gio::Cancellable::NONE,
                                None,
                            )
                            .map_err(|e| e.message().to_string())?;
                    }
                }
                Ok(())
            });
        if let Err(message) = result {
            glib::g_log!(
                glib::LogLevel::Warning,
                "Failed to migrate configuration: {}",
                message
            );
        }
        // Only succeeds once the old dir is empty
        util::rmdir(&old_dir);
    }
}
