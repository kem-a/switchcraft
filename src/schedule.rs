// Switches the light/dark style at sunrise and sunset or at set times. Runs
// in the background monitor, which then runs the commands for the new style
// like for any other switch.

use gtk::gio;
use gtk::gio::prelude::*;
use gtk::glib;
use std::cell::{Cell, RefCell};
use std::rc::{Rc, Weak};

use crate::config::APP_ID;
use crate::kde;
use crate::spawn;
use crate::util;

const GEOCLUE_NAME: &str = "org.freedesktop.GeoClue2";
const GEOCLUE_CLIENT: &str = "org.freedesktop.GeoClue2.Client";
const GEOCLUE_LOCATION: &str = "org.freedesktop.GeoClue2.Location";
const GEOCLUE_ACCURACY_CITY: u32 = 4;

pub struct ThemeSchedule {
    settings: gio::Settings,
    interface_settings: RefCell<Option<gio::Settings>>,
    // What the schedule set last. A manual switch stays until the schedule
    // wants another style.
    applied_scheme: RefCell<Option<&'static str>>,
    kde: bool,
    kde_tool: RefCell<Option<String>>,
    geoclue: RefCell<Option<gio::DBusProxy>>,
    geoclue_starting: Cell<bool>,
}

impl ThemeSchedule {
    pub fn new(settings: &gio::Settings) -> Rc<Self> {
        let schedule = Rc::new(ThemeSchedule {
            settings: settings.clone(),
            interface_settings: RefCell::new(None),
            applied_scheme: RefCell::new(None),
            kde: kde::get_desktop() == "kde",
            kde_tool: RefCell::new(None),
            geoclue: RefCell::new(None),
            geoclue_starting: Cell::new(false),
        });

        if schedule.kde {
            let tool = util::find_program("plasma-apply-lookandfeel")
                .or_else(|| util::find_program("lookandfeeltool"));
            if tool.is_none() {
                glib::g_log!(
                    glib::LogLevel::Warning,
                    "No plasma-apply-lookandfeel, the theme schedule is off"
                );
                return schedule;
            }
            *schedule.kde_tool.borrow_mut() = tool;
        } else {
            let schema = gio::SettingsSchemaSource::default()
                .and_then(|source| source.lookup("org.gnome.desktop.interface", true));
            match schema {
                Some(schema) if schema.has_key("color-scheme") => {
                    *schedule.interface_settings.borrow_mut() = Some(gio::Settings::new_full(
                        &schema,
                        None::<&gio::SettingsBackend>,
                        None,
                    ));
                }
                _ => {
                    glib::g_log!(
                        glib::LogLevel::Warning,
                        "No color-scheme setting, the theme schedule is off"
                    );
                    return schedule;
                }
            }
        }

        let weak = Rc::downgrade(&schedule);
        settings.connect_changed(None, move |_, key| {
            if let Some(schedule) = weak.upgrade() {
                schedule.on_settings_changed(key);
            }
        });
        // Polling the clock also catches up after suspend
        let weak = Rc::downgrade(&schedule);
        glib::timeout_add_seconds_local(60, move || {
            if let Some(schedule) = weak.upgrade() {
                schedule.check();
            }
            glib::ControlFlow::Continue
        });
        schedule.update_geoclue();
        schedule.check();
        schedule
    }

    fn on_settings_changed(self: &Rc<Self>, key: &str) {
        if key == "schedule-mode" || key == "light-time" || key == "dark-time" {
            // A changed schedule applies now, even over a manual switch
            *self.applied_scheme.borrow_mut() = None;
        } else if key != "last-coordinates" {
            return;
        }
        self.update_geoclue();
        self.check();
    }

    fn check(&self) {
        let Some(dark) = get_scheduled_dark(&self.settings, &now_local()) else {
            *self.applied_scheme.borrow_mut() = None;
            return;
        };

        if self.kde {
            self.check_kde(dark);
            return;
        }

        let scheme = if dark { "prefer-dark" } else { "default" };
        if *self.applied_scheme.borrow() != Some(scheme) {
            *self.applied_scheme.borrow_mut() = Some(scheme);
            if let Some(interface_settings) = self.interface_settings.borrow().as_ref() {
                let _ = interface_settings.set_string("color-scheme", scheme);
            }
        }
    }

    // Plasma has its own automatic switch, which takes precedence. When it
    // is off, apply the user's default light or dark global theme.
    fn check_kde(&self, dark: bool) {
        if kde::is_kde_auto_switch_enabled() {
            // Start over with a fresh theme once KDE's switch is off
            *self.applied_scheme.borrow_mut() = None;
            return;
        }

        let target = kde::get_kde_default_look_and_feel(dark);
        let Some(kde_tool) = self.kde_tool.borrow().clone() else {
            return;
        };
        if target.is_empty() {
            return;
        }
        let scheme = if dark { "prefer-dark" } else { "default" };
        if target == kde::get_kde_current_look_and_feel() {
            // Already there, for example after a restart
            *self.applied_scheme.borrow_mut() = Some(scheme);
            return;
        }
        // A manual switch stays until the schedule wants another style
        if *self.applied_scheme.borrow() == Some(scheme) {
            return;
        }
        *self.applied_scheme.borrow_mut() = Some(scheme);

        match spawn::spawn_async(
            &[&kde_tool, "-a", &target],
            None,
            glib::SpawnFlags::SEARCH_PATH,
        ) {
            Ok(_) => glib::g_log!(
                glib::LogLevel::Message,
                "Applying KDE global theme {}",
                target
            ),
            Err(e) => glib::g_log!(
                glib::LogLevel::Warning,
                "Failed to apply KDE global theme {}: {}",
                target,
                e.message()
            ),
        }
    }

    // GeoClue runs only for the sun schedule
    fn update_geoclue(self: &Rc<Self>) {
        let wanted = self.settings.string("schedule-mode") == "sun";
        if wanted && self.geoclue.borrow().is_none() && !self.geoclue_starting.get() {
            let schedule = self.clone();
            glib::spawn_future_local(async move { schedule.start_geoclue().await });
        } else if !wanted && let Some(client) = self.geoclue.borrow_mut().take() {
            // Sent like the Vala proxy's stop.begin (): no reply expected,
            // and the proxy goes right away. When it held the last reference
            // to the system bus, the queued Stop goes with the connection and
            // GeoClue drops the client as its peer disconnects.
            let message = gio::DBusMessage::new_method_call(
                client.name().as_deref(),
                &client.object_path(),
                Some(GEOCLUE_CLIENT),
                "Stop",
            );
            message.set_body(&().to_variant());
            message.set_flags(gio::DBusMessageFlags::NO_REPLY_EXPECTED);
            let _ = client
                .connection()
                .send_message(&message, gio::DBusSendMessageFlags::NONE);
        }
    }

    async fn start_geoclue(self: Rc<Self>) {
        self.geoclue_starting.set(true);
        match self.connect_geoclue().await {
            Ok(client) => *self.geoclue.borrow_mut() = Some(client),
            Err(e) => glib::g_log!(
                glib::LogLevel::Message,
                "GeoClue unavailable, using the time zone location: {}",
                e.message()
            ),
        }
        self.geoclue_starting.set(false);
        // Stops it again if the schedule changed meanwhile
        if self.geoclue.borrow().is_some() {
            self.update_geoclue();
        }
    }

    async fn connect_geoclue(self: &Rc<Self>) -> Result<gio::DBusProxy, glib::Error> {
        let manager = gio::DBusProxy::for_bus_future(
            gio::BusType::System,
            gio::DBusProxyFlags::NONE,
            None,
            GEOCLUE_NAME,
            "/org/freedesktop/GeoClue2/Manager",
            "org.freedesktop.GeoClue2.Manager",
        )
        .await?;
        let reply = manager
            .call_future("GetClient", None, gio::DBusCallFlags::NONE, -1)
            .await?;
        let path = reply.child_value(0).str().unwrap_or_default().to_string();
        let client = gio::DBusProxy::for_bus_future(
            gio::BusType::System,
            gio::DBusProxyFlags::NONE,
            None,
            GEOCLUE_NAME,
            &path,
            GEOCLUE_CLIENT,
        )
        .await?;
        set_property(&client, "DesktopId", &APP_ID.to_variant());
        set_property(
            &client,
            "RequestedAccuracyLevel",
            &GEOCLUE_ACCURACY_CITY.to_variant(),
        );
        // Sun times move about a minute per 15 km
        set_property(&client, "DistanceThreshold", &10000u32.to_variant());
        let weak: Weak<Self> = Rc::downgrade(self);
        client.connect_local("g-signal::LocationUpdated", false, move |args| {
            let schedule = weak.upgrade()?;
            let parameters = args.get(3)?.get::<glib::Variant>().ok()?;
            let new_path = parameters
                .child_value(1)
                .str()
                .unwrap_or_default()
                .to_string();
            glib::spawn_future_local(async move { schedule.save_location(&new_path).await });
            None
        });
        client
            .call_future("Start", None, gio::DBusCallFlags::NONE, -1)
            .await?;
        Ok(client)
    }

    async fn save_location(&self, path: &str) {
        let location = gio::DBusProxy::for_bus_future(
            gio::BusType::System,
            gio::DBusProxyFlags::NONE,
            None,
            GEOCLUE_NAME,
            path,
            GEOCLUE_LOCATION,
        )
        .await;
        match location {
            Ok(location) => {
                let latitude = get_double_property(&location, "Latitude");
                let longitude = get_double_property(&location, "Longitude");
                let _ = self
                    .settings
                    .set_value("last-coordinates", &(latitude, longitude).to_variant());
            }
            Err(e) => glib::g_log!(
                glib::LogLevel::Warning,
                "Failed to read the GeoClue location: {}",
                e.message()
            ),
        }
    }
}

// Property writes go through Properties.Set and wait for it, like the
// Vala D-Bus proxies. Errors are ignored there too.
fn set_property(proxy: &gio::DBusProxy, name: &str, value: &glib::Variant) {
    let interface = proxy.interface_name();
    let arguments = (interface.as_str(), name, value).to_variant();
    let _ = proxy.connection().call_sync(
        proxy.name().as_deref(),
        proxy.object_path().as_str(),
        "org.freedesktop.DBus.Properties",
        "Set",
        Some(&arguments),
        None,
        gio::DBusCallFlags::NONE,
        -1,
        gio::Cancellable::NONE,
    );
}

// The cached value, else a Properties.Get call, else 0
fn get_double_property(proxy: &gio::DBusProxy, name: &str) -> f64 {
    let value = proxy.cached_property(name).or_else(|| {
        let arguments = (proxy.interface_name().as_str(), name).to_variant();
        proxy
            .call_sync(
                "org.freedesktop.DBus.Properties.Get",
                Some(&arguments),
                gio::DBusCallFlags::NONE,
                -1,
                gio::Cancellable::NONE,
            )
            .ok()
            .and_then(|reply| reply.child_value(0).as_variant())
    });
    value.and_then(|v| v.get::<f64>()).unwrap_or(0.0)
}

fn now_local() -> glib::DateTime {
    glib::DateTime::now_local().expect("local time")
}

// None when there is no schedule, or no location for the sun
pub fn get_scheduled_dark(settings: &gio::Settings, time: &glib::DateTime) -> Option<bool> {
    match settings.string("schedule-mode").as_str() {
        "custom" => {
            let minute = time.hour() * 60 + time.minute();
            let light_from = settings.int("light-time");
            let dark_from = settings.int("dark-time");
            // Dark from dark-time until light-time, across midnight if
            // needed. Equal times mean always light.
            Some((minute - dark_from + 1440) % 1440 < (light_from - dark_from + 1440) % 1440)
        }
        "sun" => {
            let (latitude, longitude) = get_location(settings)?;
            let (sunrise, sunset) = get_sun_times(latitude, longitude, time);
            Some(time < &sunrise || time >= &sunset)
        }
        _ => None,
    }
}

// GeoClue's last location, else the main city of the system time zone
pub fn get_location(settings: &gio::Settings) -> Option<(f64, f64)> {
    let coordinates = settings.value("last-coordinates");
    let latitude = coordinates.child_value(0).get::<f64>().unwrap_or_default();
    let longitude = coordinates.child_value(1).get::<f64>().unwrap_or_default();
    if latitude.abs() <= 90.0 && longitude.abs() <= 180.0 {
        return Some((latitude, longitude));
    }
    get_time_zone_location()
}

fn get_time_zone_location() -> Option<(f64, f64)> {
    let zone = glib::TimeZone::local().identifier().to_string();
    for name in ["zone1970.tab", "zone.tab"] {
        let Some(contents) = kde::read_text(&util::build_filename(&["/usr/share/zoneinfo", name]))
        else {
            continue;
        };
        for line in util::split(&contents, "\n") {
            let fields = util::split(line, "\t");
            if fields.len() >= 3
                && fields[2] == zone
                && let Some(location) = parse_coordinates(fields[1])
            {
                return Some(location);
            }
        }
    }
    None
}

// ISO 6709 as zone.tab writes it: ±DDMM[SS]±DDDMM[SS]
pub(crate) fn parse_coordinates(text: &str) -> Option<(f64, f64)> {
    let regex = glib::Regex::new(
        r"^([+-])(\d\d)(\d\d)(\d\d)?([+-])(\d\d\d)(\d\d)(\d\d)?$",
        glib::RegexCompileFlags::empty(),
        glib::RegexMatchFlags::empty(),
    )
    .ok()
    .flatten()?;
    let text = glib::GString::from(text);
    let info = regex
        .match_(text.as_gstr(), glib::RegexMatchFlags::empty())
        .ok()?;
    if !info.matches() {
        return None;
    }
    Some((parse_degrees(&info, 1), parse_degrees(&info, 5)))
}

// Sign, degrees, minutes and optional seconds, from four groups
fn parse_degrees(info: &glib::MatchInfo, group: i32) -> f64 {
    let fetch = |n: i32| info.fetch(n).map(|s| s.to_string());
    let value = util::atoi(&fetch(group + 1).unwrap_or_default()) as f64
        + util::atoi(&fetch(group + 2).unwrap_or_default()) as f64 / 60.0
        + util::atoi(&fetch(group + 3).unwrap_or_else(|| "0".to_string())) as f64 / 3600.0;
    if fetch(group).as_deref() == Some("-") {
        -value
    } else {
        value
    }
}

// Sunrise and sunset around the solar noon nearest to the given time, from
// the sunrise equation. While the sun stays up they are a day apart, while
// it stays down they are equal.
pub fn get_sun_times(
    latitude: f64,
    longitude: f64,
    time: &glib::DateTime,
) -> (glib::DateTime, glib::DateTime) {
    const J2000: f64 = 2451545.0;
    const UNIX_EPOCH: f64 = 2440587.5;
    const RAD: f64 = std::f64::consts::PI / 180.0;

    let julian_day = time.to_unix() as f64 / 86400.0 + UNIX_EPOCH;
    // Days since J2000 of the mean solar noon at this longitude
    let noon = (julian_day - J2000 + longitude / 360.0).round() - longitude / 360.0;
    let anomaly = (357.5291 + 0.98560028 * noon) * RAD;
    let center =
        1.9148 * anomaly.sin() + 0.02 * (2.0 * anomaly).sin() + 0.0003 * (3.0 * anomaly).sin();
    let ecliptic = anomaly + (center + 282.9372) * RAD;
    let transit = J2000 + noon + 0.0053 * anomaly.sin() - 0.0069 * (2.0 * ecliptic).sin();
    let declination = (ecliptic.sin() * (23.4397 * RAD).sin()).asin();
    let cos_hour_angle = ((-0.833 * RAD).sin() - (latitude * RAD).sin() * declination.sin())
        / ((latitude * RAD).cos() * declination.cos());
    let half_day = cos_hour_angle.clamp(-1.0, 1.0).acos() / (2.0 * std::f64::consts::PI);

    let sunrise =
        glib::DateTime::from_unix_local(((transit - half_day - UNIX_EPOCH) * 86400.0) as i64);
    let sunset =
        glib::DateTime::from_unix_local(((transit + half_day - UNIX_EPOCH) * 86400.0) as i64);
    (sunrise.expect("sunrise time"), sunset.expect("sunset time"))
}
