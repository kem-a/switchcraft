// Regression tests. The expected values were recorded from the Vala
// version (2.0.0) with the same inputs, so they pin the behaviour the Rust
// port keeps byte for byte. Only cases that do not depend on the machine
// (installed themes, schemas, KDE files) are here.

use crate::util::StrTable;
use crate::{builtins, constants_window, json, schedule, store, util};
use gtk::glib;
use std::ffi::CString;

const FIXTURES: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures");

fn read(path: &str) -> Vec<u8> {
    std::fs::read(format!("{FIXTURES}/{path}")).unwrap()
}

fn text(path: &str) -> String {
    String::from_utf8(read(path)).unwrap()
}

#[test]
fn commands_json_round_trip() {
    for name in [
        "blank",
        "comment",
        "current",
        "dupkeys",
        "empty",
        "legacy",
        "notobject",
        "nul",
        "odd",
        "trailing",
    ] {
        let output = match json::Parser::load(&read(&format!("commands/{name}.json"))) {
            Ok(parser) => store::commands_to_json(&store::normalize_commands(parser.root())),
            Err(e) => format!("ERROR {}", e.message()),
        };
        assert_eq!(output, text(&format!("commands/{name}.expected")), "{name}");
    }
}

// Constants keep the iteration order of GLib's HashTable, like the Vala
// version, through every insert and remove
#[test]
fn constants_order() {
    let mut out = String::new();
    let table = StrTable::new();
    let parser = json::Parser::load(&read("constants/mixed.json")).unwrap();
    let obj = parser.root().unwrap().object();
    for name in obj.members() {
        if let Some(value) = obj.member(&name).and_then(|n| n.string_value()) {
            table.insert(&name, &value);
        }
    }
    out.push_str(&format!("== load\n{}\n", store::constants_to_json(&table)));
    let window = StrTable::new();
    for (key, value) in table.entries() {
        window.insert(&key, &constants_window::normalize_constant_value(&value));
    }
    out.push_str(&format!(
        "== window\n{}\n",
        store::constants_to_json(&window)
    ));
    for op in text("constants/ops.txt").lines() {
        let parts: Vec<&str> = op.splitn(3, ' ').collect();
        if parts[0] == "remove" {
            window.remove(parts[1]);
        } else {
            window.insert(parts[1], parts[2]);
        }
        out.push_str(&format!("== {op}\n{}\n", store::constants_to_json(&window)));
    }
    let sorted: String = window
        .sorted_keys()
        .iter()
        .map(|k| format!("{k},"))
        .collect();
    out.push_str(&format!("== sorted\n{sorted}\n"));
    assert_eq!(out, text("constants/mixed.expected"));
}
#[test]
fn builtin_command_lines() {
    let cases = [
        (
            "color-scheme",
            "prefer-dark",
            "gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'",
        ),
        (
            "accent-color",
            "teal",
            "gsettings set org.gnome.desktop.interface accent-color 'teal'",
        ),
        (
            "icon-theme",
            "Adwaita",
            "gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'",
        ),
        (
            "icon-theme",
            "it's \"quoted\"",
            "gsettings set org.gnome.desktop.interface icon-theme 'it'\\''s \"quoted\"'",
        ),
        (
            "gtk-theme",
            "adw-gtk3-dark",
            "gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'",
        ),
        (
            "cursor-theme",
            "Bibata Modern",
            "gsettings set org.gnome.desktop.interface cursor-theme 'Bibata Modern'",
        ),
        (
            "wallpaper",
            "/home/user/Pictures/my pic #1 100%.png",
            "gsettings set org.gnome.desktop.background picture-uri 'file:///home/user/Pictures/my%20pic%20%231%20100%25.png' && gsettings set org.gnome.desktop.background picture-uri-dark 'file:///home/user/Pictures/my%20pic%20%231%20100%25.png'",
        ),
        (
            "wallpaper",
            "file:///usr/share/backgrounds/a.jpg",
            "gsettings set org.gnome.desktop.background picture-uri 'file:///usr/share/backgrounds/a.jpg' && gsettings set org.gnome.desktop.background picture-uri-dark 'file:///usr/share/backgrounds/a.jpg'",
        ),
        (
            "wallpaper",
            "/tmp/ünïcode ✓.jpg",
            "gsettings set org.gnome.desktop.background picture-uri 'file:///tmp/%C3%BCn%C3%AFcode%20%E2%9C%93.jpg' && gsettings set org.gnome.desktop.background picture-uri-dark 'file:///tmp/%C3%BCn%C3%AFcode%20%E2%9C%93.jpg'",
        ),
        (
            "night-light",
            "true",
            "gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled 'true'",
        ),
        (
            "kde-global-theme",
            "org.kde.breezedark.desktop",
            "plasma-apply-lookandfeel -a 'org.kde.breezedark.desktop'",
        ),
        (
            "kde-color-scheme",
            "BreezeDark",
            "plasma-apply-colorscheme 'BreezeDark'",
        ),
        (
            "kde-plasma-style",
            "default",
            "plasma-apply-desktoptheme 'default'",
        ),
        (
            "kde-cursor-theme",
            "breeze_cursors",
            "plasma-apply-cursortheme 'breeze_cursors'",
        ),
        (
            "kde-wallpaper",
            "/home/u/w p.png",
            "plasma-apply-wallpaperimage '/home/u/w p.png'",
        ),
        ("kvantum-theme", "KvArc", "kvantummanager --set 'KvArc'"),
        (
            "unknown-id",
            "value",
            "gsettings set org.gnome.desktop.interface unknown-id 'value'",
        ),
    ];
    for (setting_id, value, expected) in cases {
        assert_eq!(
            builtins::build_builtin_command(setting_id, value),
            expected,
            "{setting_id} {value}"
        );
    }
}

#[test]
fn loop_conflicts() {
    let cases = [
        (
            "dark",
            "gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'",
            Some("Switches to the light style and would loop in Dark mode"),
        ),
        (
            "light",
            "gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'",
            Some("Switches to the dark style and would loop in Light mode"),
        ),
        (
            "dark",
            "gsettings set org.gnome.desktop.interface color-scheme \"default\"",
            Some("Switches to the light style and would loop in Dark mode"),
        ),
        (
            "dark",
            "gsettings set org.gnome.desktop.interface color-scheme prefer-dark",
            None,
        ),
        (
            "light",
            "gsettings set org.gnome.desktop.interface color-scheme default",
            None,
        ),
        (
            "light",
            "gsettings set org.gnome.desktop.interface color-scheme 'defaults'",
            None,
        ),
        (
            "dark",
            "color-scheme\"  ''prefer-light",
            Some("Switches to the light style and would loop in Dark mode"),
        ),
        ("light", "echo nothing", None),
    ];
    for (theme, command, expected) in cases {
        assert_eq!(
            builtins::find_loop_conflict(command, theme).as_deref(),
            expected,
            "{theme} {command}"
        );
    }
}

#[test]
fn duplicates() {
    let parser = json::Parser::load(&read("commands/current.json")).unwrap();
    let commands = store::normalize_commands(parser.root());
    let first = commands.get("light")[0].clone();
    let second = commands.get("light")[1].clone();
    let light_command = "notify-send \"light\" & echo <b>";
    let cases = [
        (
            (None, " notify-send \"light\" & echo <b> ", "", "light"),
            Some("This command is already in this mode"),
        ),
        ((Some(&first), light_command, "", "light"), None),
        (
            (None, "other", "icon-theme", "light"),
            Some("Icon Theme is already set in this mode"),
        ),
        ((Some(&second), "other", "icon-theme", "light"), None),
        ((None, light_command, "", "dark"), None),
        ((None, "x", "", "other"), None),
    ];
    for ((entry, command, builtin, theme), expected) in cases {
        assert_eq!(
            builtins::find_duplicate(&commands, entry, command, builtin, theme).as_deref(),
            expected
        );
    }
}

#[test]
fn int_try_parse_like_vala() {
    let cases = [
        ("239", Some(239)),
        (" 12", Some(12)),
        ("0x1F", Some(31)),
        ("017", Some(15)),
        ("08", None),
        ("", Some(0)),
        ("-", None),
        ("+5", Some(5)),
        ("99999999999", None),
        ("2147483647", Some(2147483647)),
        ("-2147483648", Some(-2147483648)),
        ("2147483648", None),
        ("12abc", None),
        ("abc", None),
        ("  ", None),
        ("1e3", None),
    ];
    for (input, expected) in cases {
        assert_eq!(util::int_try_parse(input), expected, "{input:?}");
    }
}

// %.17g, as the reference values were printed
fn g17(x: f64) -> String {
    let mut buf = [0u8; 64];
    let fmt = CString::new("%.17g").unwrap();
    let n = unsafe { libc::snprintf(buf.as_mut_ptr().cast(), 64, fmt.as_ptr(), x) };
    String::from_utf8_lossy(&buf[..n as usize]).into_owned()
}

#[test]
fn zone_tab_coordinates() {
    let cases = [
        ("+5657+02406", "56.950000000000003 24.100000000000001"),
        ("-3352+15113", "-33.866666666666667 151.21666666666667"),
        ("+4043-07400", "40.716666666666669 -74"),
        ("+411716-0813415", "41.287777777777777 -81.570833333333326"),
        ("+0000+00000", "0 0"),
        ("-33+151", "fail"),
        ("+5657+0240600", "56.950000000000003 24.100000000000001"),
        ("5657+02406", "fail"),
        ("+56a7+02406", "fail"),
    ];
    for (input, expected) in cases {
        let output = schedule::parse_coordinates(input).map_or("fail".to_string(), |(a, b)| {
            format!("{} {}", g17(a), g17(b))
        });
        assert_eq!(output, expected, "{input}");
    }
}

#[test]
fn sun_times() {
    let cases = [
        (
            56.95_f64,
            24.1_f64,
            1774051200_i64,
            1774067030_i64,
            1774111073_i64,
        ),
        (
            56.95_f64,
            24.1_f64,
            1782000000_i64,
            1782005343_i64,
            1782069691_i64,
        ),
        (
            56.95_f64,
            24.1_f64,
            1797638400_i64,
            1797663516_i64,
            1797687750_i64,
        ),
        (
            69.65_f64,
            18.96_f64,
            1782000000_i64,
            1781995550_i64,
            1782081950_i64,
        ),
        (
            69.65_f64,
            18.96_f64,
            1797638400_i64,
            1797676867_i64,
            1797676867_i64,
        ),
        (
            -0.18_f64,
            -78.47_f64,
            1774051200_i64,
            1774005481_i64,
            1774049081_i64,
        ),
        (
            -33.87_f64,
            151.21_f64,
            1782000000_i64,
            1781989193_i64,
            1782024819_i64,
        ),
        (
            -36.85_f64,
            174.76_f64,
            1774572000_i64,
            1774549760_i64,
            1774592615_i64,
        ),
        (
            78.22_f64,
            15.65_f64,
            1766880000_i64,
            1766919528_i64,
            1766919528_i64,
        ),
        (
            -77.85_f64,
            166.67_f64,
            1766880000_i64,
            1766840072_i64,
            1766926472_i64,
        ),
        (0_f64, 0_f64, 0_i64, -64831_i64, -21196_i64),
        (
            90_f64,
            0_f64,
            1782000000_i64,
            1782000101_i64,
            1782086501_i64,
        ),
        (
            -90_f64,
            180_f64,
            1782000000_i64,
            1782000095_i64,
            1782000095_i64,
        ),
    ];
    for (latitude, longitude, time, sunrise, sunset) in cases {
        let time = glib::DateTime::from_unix_local(time).unwrap();
        let (rise, set) = schedule::get_sun_times(latitude, longitude, &time);
        assert_eq!(
            (rise.to_unix(), set.to_unix()),
            (sunrise, sunset),
            "{latitude} {longitude}"
        );
    }
}
