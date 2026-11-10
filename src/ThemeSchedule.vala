/* ThemeSchedule.vala
 * Switches the light/dark style at sunrise and sunset or at set times
 *
 * Copyright (c) 2026 kem-a
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Switchcraft {

    [DBus (name = "org.freedesktop.GeoClue2.Manager")]
    interface GeoClueManager : Object {
        public abstract async ObjectPath get_client () throws Error;
    }

    [DBus (name = "org.freedesktop.GeoClue2.Client")]
    interface GeoClueClient : Object {
        public abstract string desktop_id { owned get; set; }
        public abstract uint requested_accuracy_level { get; set; }
        public abstract uint distance_threshold { get; set; }
        public abstract async void start () throws Error;
        public abstract async void stop () throws Error;
        public signal void location_updated (ObjectPath old, ObjectPath @new);
    }

    [DBus (name = "org.freedesktop.GeoClue2.Location")]
    interface GeoClueLocation : Object {
        public abstract double latitude { get; }
        public abstract double longitude { get; }
    }

    // Runs in the background monitor, which then runs the commands for
    // the new style like for any other switch
    public class ThemeSchedule : Object {
        private const string GEOCLUE_NAME = "org.freedesktop.GeoClue2";
        private const uint GEOCLUE_ACCURACY_CITY = 4;

        private Settings settings;
        private Settings interface_settings;
        // What the schedule set last. A manual switch stays until the
        // schedule wants another style.
        private string? applied_scheme = null;
        private GeoClueClient? geoclue = null;
        private bool geoclue_starting = false;

        public ThemeSchedule (Settings settings) {
            this.settings = settings;

            var source = SettingsSchemaSource.get_default ();
            var schema = source != null ? source.lookup ("org.gnome.desktop.interface", true) : null;
            if (schema == null || !schema.has_key ("color-scheme")) {
                warning ("No color-scheme setting, the theme schedule is off");
                return;
            }
            interface_settings = new Settings.full (schema, null, null);

            settings.changed.connect (on_settings_changed);
            // Polling the clock also catches up after suspend
            Timeout.add_seconds (60, () => {
                check ();
                return Source.CONTINUE;
            });
            update_geoclue ();
            check ();
        }

        private void on_settings_changed (string key) {
            if (key == "schedule-mode" || key == "light-time" || key == "dark-time") {
                // A changed schedule applies now, even over a manual switch
                applied_scheme = null;
            } else if (key != "last-coordinates") {
                return;
            }
            update_geoclue ();
            check ();
        }

        private void check () {
            bool dark;
            if (!get_scheduled_dark (settings, new DateTime.now_local (), out dark)) {
                applied_scheme = null;
                return;
            }
            var scheme = dark ? "prefer-dark" : "default";
            if (scheme != applied_scheme) {
                applied_scheme = scheme;
                interface_settings.set_string ("color-scheme", scheme);
            }
        }

        // Returns false when there is no schedule, or no location for the sun
        public static bool get_scheduled_dark (Settings settings, DateTime time, out bool dark) {
            dark = false;
            switch (settings.get_string ("schedule-mode")) {
                case "custom":
                    int minute = time.get_hour () * 60 + time.get_minute ();
                    int light_from = settings.get_int ("light-time");
                    int dark_from = settings.get_int ("dark-time");
                    // Dark from dark-time until light-time, across midnight
                    // if needed. Equal times mean always light.
                    dark = (minute - dark_from + 1440) % 1440 < (light_from - dark_from + 1440) % 1440;
                    return true;
                case "sun":
                    double latitude, longitude;
                    if (!get_location (settings, out latitude, out longitude)) {
                        return false;
                    }
                    DateTime sunrise, sunset;
                    get_sun_times (latitude, longitude, time, out sunrise, out sunset);
                    dark = time.compare (sunrise) < 0 || time.compare (sunset) >= 0;
                    return true;
                default:
                    return false;
            }
        }

        // GeoClue's last location, else the main city of the system time zone
        public static bool get_location (Settings settings, out double latitude, out double longitude) {
            var coordinates = settings.get_value ("last-coordinates");
            latitude = coordinates.get_child_value (0).get_double ();
            longitude = coordinates.get_child_value (1).get_double ();
            if (latitude.abs () <= 90 && longitude.abs () <= 180) {
                return true;
            }
            return get_time_zone_location (out latitude, out longitude);
        }

        private static bool get_time_zone_location (out double latitude, out double longitude) {
            latitude = 0;
            longitude = 0;
            var zone = new TimeZone.local ().get_identifier ();
            foreach (var name in new string[] { "zone1970.tab", "zone.tab" }) {
                string contents;
                try {
                    FileUtils.get_contents (Path.build_filename ("/usr/share/zoneinfo", name), out contents);
                } catch (FileError e) {
                    continue;
                }
                foreach (var line in contents.split ("\n")) {
                    var fields = line.split ("\t");
                    if (fields.length >= 3 && fields[2] == zone
                        && parse_coordinates (fields[1], out latitude, out longitude)) {
                        return true;
                    }
                }
            }
            return false;
        }

        // ISO 6709 as zone.tab writes it: ±DDMM[SS]±DDDMM[SS]
        private static bool parse_coordinates (string text, out double latitude, out double longitude) {
            latitude = 0;
            longitude = 0;
            MatchInfo match;
            if (!/^([+-])(\d\d)(\d\d)(\d\d)?([+-])(\d\d\d)(\d\d)(\d\d)?$/.match (text, 0, out match)) {
                return false;
            }
            latitude = parse_degrees (match, 1);
            longitude = parse_degrees (match, 5);
            return true;
        }

        // Sign, degrees, minutes and optional seconds, from four groups
        private static double parse_degrees (MatchInfo match, int group) {
            var value = int.parse (match.fetch (group + 1))
                + int.parse (match.fetch (group + 2)) / 60.0
                + int.parse (match.fetch (group + 3) ?? "0") / 3600.0;
            return match.fetch (group) == "-" ? -value : value;
        }

        // Sunrise and sunset around the solar noon nearest to the given time,
        // from the sunrise equation. While the sun stays up they are a day
        // apart, while it stays down they are equal.
        public static void get_sun_times (double latitude, double longitude, DateTime time,
                                          out DateTime sunrise, out DateTime sunset) {
            const double J2000 = 2451545.0;
            const double UNIX_EPOCH = 2440587.5;
            const double RAD = Math.PI / 180;

            double julian_day = time.to_unix () / 86400.0 + UNIX_EPOCH;
            // Days since J2000 of the mean solar noon at this longitude
            double noon = Math.round (julian_day - J2000 + longitude / 360) - longitude / 360;
            double anomaly = (357.5291 + 0.98560028 * noon) * RAD;
            double center = 1.9148 * Math.sin (anomaly) + 0.02 * Math.sin (2 * anomaly)
                + 0.0003 * Math.sin (3 * anomaly);
            double ecliptic = anomaly + (center + 282.9372) * RAD;
            double transit = J2000 + noon + 0.0053 * Math.sin (anomaly) - 0.0069 * Math.sin (2 * ecliptic);
            double declination = Math.asin (Math.sin (ecliptic) * Math.sin (23.4397 * RAD));
            double cos_hour_angle = (Math.sin (-0.833 * RAD) - Math.sin (latitude * RAD) * Math.sin (declination))
                / (Math.cos (latitude * RAD) * Math.cos (declination));
            double half_day = Math.acos (cos_hour_angle.clamp (-1, 1)) / (2 * Math.PI);

            sunrise = new DateTime.from_unix_local ((int64) ((transit - half_day - UNIX_EPOCH) * 86400));
            sunset = new DateTime.from_unix_local ((int64) ((transit + half_day - UNIX_EPOCH) * 86400));
        }

        // GeoClue runs only for the sun schedule
        private void update_geoclue () {
            bool wanted = settings.get_string ("schedule-mode") == "sun";
            if (wanted && geoclue == null && !geoclue_starting) {
                start_geoclue.begin ();
            } else if (!wanted && geoclue != null) {
                geoclue.stop.begin ();
                geoclue = null;
            }
        }

        private async void start_geoclue () {
            geoclue_starting = true;
            try {
                GeoClueManager manager = yield Bus.get_proxy (
                    BusType.SYSTEM, GEOCLUE_NAME, "/org/freedesktop/GeoClue2/Manager");
                var path = yield manager.get_client ();
                GeoClueClient client = yield Bus.get_proxy (BusType.SYSTEM, GEOCLUE_NAME, path);
                client.desktop_id = "com.github.Switchcraft";
                client.requested_accuracy_level = GEOCLUE_ACCURACY_CITY;
                // Sun times move about a minute per 15 km
                client.distance_threshold = 10000;
                client.location_updated.connect ((old_path, new_path) => {
                    save_location.begin (new_path);
                });
                yield client.start ();
                geoclue = client;
            } catch (Error e) {
                message ("GeoClue unavailable, using the time zone location: %s", e.message);
            }
            geoclue_starting = false;
            // Stops it again if the schedule changed meanwhile
            if (geoclue != null) {
                update_geoclue ();
            }
        }

        private async void save_location (ObjectPath path) {
            try {
                GeoClueLocation location = yield Bus.get_proxy (BusType.SYSTEM, GEOCLUE_NAME, path);
                settings.set_value ("last-coordinates",
                    new Variant ("(dd)", location.latitude, location.longitude));
            } catch (Error e) {
                warning ("Failed to read the GeoClue location: %s", e.message);
            }
        }
    }
}
