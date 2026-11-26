// Import, export and deletion of the configuration. Archives are read and
// written with the zip crate, so the host's zip and unzip are not needed.

use gtk::gio;
use gtk::gio::prelude::*;
use gtk::glib;
use serde_json::Value;
use std::io::{Read, Write};

use crate::i18n::{gettext, i18n_f};
use crate::json;
use crate::store;
use crate::util::{self, StrTable};

pub fn export_configuration_bundle(file: &gio::File) -> Result<(), String> {
    let Some(target_path) = file.path().map(|p| p.to_string_lossy().into_owned()) else {
        return Err(gettext("Destination must be a local file."));
    };

    let parent = util::dirname(&target_path);
    if !parent.is_empty() && parent != "." && util::mkdir_with_parents(&parent, 0o755) != 0 {
        return Err(gettext("Failed to prepare destination directory."));
    }

    let commands_data = store::commands_to_json(&store::get_commands());
    let constants_data = store::constants_to_json(&store::get_constants());

    if util::exists(&target_path) && util::remove(&target_path) != 0 {
        return Err(gettext("Unable to overwrite existing archive."));
    }

    write_archive(
        &target_path,
        &[
            ("commands.json", &commands_data),
            ("constants.json", &constants_data),
        ],
    )
    .map_err(|e| {
        i18n_f(
            // xgettext:c-format
            "Failed to write archive: %s",
            &[&e],
        )
    })
}

fn write_archive(path: &str, files: &[(&str, &str)]) -> Result<(), String> {
    let now = glib::DateTime::now_local().map_err(|e| e.to_string())?;
    let modified = zip::DateTime::from_date_and_time(
        now.year() as u16,
        now.month() as u8,
        now.day_of_month() as u8,
        now.hour() as u8,
        now.minute() as u8,
        now.second() as u8,
    )
    .unwrap_or_default();
    let options = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated)
        .last_modified_time(modified)
        .unix_permissions(0o644);

    let output = std::fs::File::create(path).map_err(|e| e.to_string())?;
    let mut archive = zip::ZipWriter::new(output);
    for (name, data) in files {
        archive
            .start_file(*name, options)
            .map_err(|e| e.to_string())?;
        archive
            .write_all(data.as_bytes())
            .map_err(|e| e.to_string())?;
    }
    archive.finish().map_err(|e| e.to_string())?;
    Ok(())
}

// The file at the top level of the archive, or None
fn read_entry(
    archive: &mut zip::ZipArchive<std::fs::File>,
    name: &str,
) -> Result<Option<Vec<u8>>, String> {
    let mut entry = match archive.by_name(name) {
        Ok(entry) => entry,
        Err(zip::result::ZipError::FileNotFound) => return Ok(None),
        Err(e) => return Err(e.to_string()),
    };
    if entry.is_dir() {
        return Ok(None);
    }
    let mut data = Vec::new();
    entry.read_to_end(&mut data).map_err(|e| e.to_string())?;
    Ok(Some(data))
}

pub fn import_configuration_bundle(file: &gio::File) -> Result<(), String> {
    let Some(source_path) = file.path() else {
        return Err(gettext("Archive must be a local file."));
    };

    let unpack_error = |e: String| {
        i18n_f(
            // xgettext:c-format
            "Failed to unpack archive: %s",
            &[&e],
        )
    };
    let mut archive = std::fs::File::open(&source_path)
        .map_err(|e| e.to_string())
        .and_then(|f| zip::ZipArchive::new(f).map_err(|e| e.to_string()))
        .map_err(unpack_error)?;
    let commands_data = read_entry(&mut archive, "commands.json").map_err(unpack_error)?;
    let constants_data = read_entry(&mut archive, "constants.json").map_err(unpack_error)?;
    let theme_settings_data =
        read_entry(&mut archive, "theme_settings.json").map_err(unpack_error)?;

    let (Some(commands_data), Some(constants_data)) = (commands_data, constants_data) else {
        return Err(gettext(
            "Archive must contain commands.json and constants.json at the top level.",
        ));
    };

    // Parse and check every file before saving, so a bad archive changes
    // nothing
    let commands_root = json::parse(&commands_data)?;
    if !commands_root.as_ref().is_some_and(Value::is_object) {
        return Err(gettext("commands.json is not a JSON object."));
    }
    let mut imported_commands = store::normalize_commands(commands_root.as_ref());

    let constants_root = json::parse(&constants_data)?;
    let Some(constants_obj) = constants_root.as_ref().and_then(Value::as_object) else {
        return Err(gettext("constants.json is not a JSON object."));
    };

    let constants_table = StrTable::new();
    let mut invalid_value = false;
    for (name, value) in constants_obj {
        match json::string(value) {
            Some(value) => constants_table.insert(name, &value),
            None => invalid_value = true,
        }
    }

    if invalid_value {
        return Err(gettext("constants.json must only contain string values."));
    }

    // Older exports have theme_settings.json. It becomes commands.
    if let Some(ts_data) = theme_settings_data {
        let ts_root = json::parse(&ts_data)?;
        let Some(ts_obj) = ts_root.as_ref().and_then(Value::as_object) else {
            return Err(gettext("theme_settings.json is not a JSON object."));
        };
        store::add_theme_setting_commands(
            &mut imported_commands,
            &store::parse_theme_settings(ts_obj),
        );
    }

    store::save_commands(&imported_commands);
    store::save_constants(&constants_table);

    Ok(())
}

pub fn delete_configuration_files(settings: &gio::Settings) -> Result<(), String> {
    let config_path = store::config_path();
    if util::exists(&config_path) && util::remove(&config_path) != 0 {
        return Err(gettext("Failed to remove commands.json."));
    }

    let constants_path = store::constants_path();
    if util::exists(&constants_path) && util::remove(&constants_path) != 0 {
        return Err(gettext("Failed to remove constants.json."));
    }

    let theme_settings_path = store::theme_settings_path();
    if util::exists(&theme_settings_path) && util::remove(&theme_settings_path) != 0 {
        return Err(gettext("Failed to remove theme_settings.json."));
    }

    settings.reset("monitoring-enabled");

    Ok(())
}
