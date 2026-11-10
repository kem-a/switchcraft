/* Application.vala
 * Main application class with configuration management
 *
 * Copyright (c) 2021-2025 kem-a
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Switchcraft {

    public const string GETTEXT_PACKAGE = "switchcraft";

    public void init_i18n () {
        if (Intl.setlocale (LocaleCategory.ALL, "") == null) {
            if (Intl.setlocale (LocaleCategory.ALL, "C.UTF-8") != null) {
                Environment.set_variable ("LC_ALL", "C.UTF-8", true);
                Environment.set_variable ("LANG", "C.UTF-8", true);
            } else {
                Intl.setlocale (LocaleCategory.ALL, "C");
                Environment.set_variable ("LC_ALL", "C", true);
                Environment.set_variable ("LANG", "C", true);
            }
        }

        Intl.bindtextdomain (GETTEXT_PACKAGE, get_locale_dir ());
        Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (GETTEXT_PACKAGE);
    }

    private string get_locale_dir () {
        // Check next to the running binary first. This covers local installs
        // and both AppImage layouts without trusting an inherited APPDIR.
        try {
            var exe_path = FileUtils.read_link ("/proc/self/exe");
            if (exe_path != null) {
                var local_locale = Path.build_filename (
                    Path.get_dirname (exe_path), "..", "share", "locale");
                if (FileUtils.test (local_locale, FileTest.IS_DIR)) {
                    return local_locale;
                }
            }
        } catch (Error e) {
            // Fall through to the bundle and system locale directories
        }

        var appdir = Environment.get_variable ("APPDIR");
        if (appdir != null && appdir != "") {
            var bundled = Path.build_filename (appdir, "share", "locale");
            if (FileUtils.test (bundled, FileTest.IS_DIR)) {
                return bundled;
            }

            var classic = Path.build_filename (appdir, "usr", "share", "locale");
            if (FileUtils.test (classic, FileTest.IS_DIR)) {
                return classic;
            }
        }

        return "/usr/share/locale";
    }

    public class CommandEntry : Object {
        public string command { get; set; }
        public bool enabled { get; set; default = true; }
        // Index in the command list, which mixes light and dark
        public int position { get; set; default = -1; }
        // Set for commands made from a built-in setting, so the dialog can
        // show the setting and its value instead of the gsettings line
        public string builtin { get; set; default = ""; }
        public string value { get; set; default = ""; }

        public CommandEntry (owned string cmd, bool en = true) {
            command = (owned) cmd;
            enabled = en;
        }
    }

    public class ThemeSettingValue : Object {
        public string light { get; set; default = ""; }
        public string dark { get; set; default = ""; }

        public ThemeSettingValue (string light_val = "", string dark_val = "") {
            this.light = light_val;
            this.dark = dark_val;
        }

        public string get_for_theme (string theme) {
            return theme == "dark" ? dark : light;
        }

        public void set_for_theme (string theme, string val) {
            if (theme == "dark") {
                dark = val;
            } else {
                light = val;
            }
        }
    }

    public class Application : Adw.Application {
        private string config_path;
        private string constants_path;
        private string theme_settings_path;
        private string autostart_path;
        private Settings settings;
        private ThemeSchedule? schedule = null;

        public Application () {
            Object (
                application_id: "com.github.Switchcraft",
                flags: ApplicationFlags.HANDLES_COMMAND_LINE
            );
            
            var data_dir = Environment.get_user_data_dir ();
            var config_home = Environment.get_user_config_dir ();
            
            config_path = Path.build_filename (data_dir, "switchcraft", "commands.json");
            constants_path = Path.build_filename (data_dir, "switchcraft", "constants.json");
            theme_settings_path = Path.build_filename (data_dir, "switchcraft", "theme_settings.json");
            autostart_path = Path.build_filename (config_home, "autostart", "switchcraft-monitor.desktop");
            
            settings = new Settings ("com.github.Switchcraft");

            migrate_config_files ();
            migrate_theme_settings ();

            add_main_option ("version", 'v', OptionFlags.NONE, OptionArg.NONE, _("Show version information"), null);
            add_main_option ("background", 'b', OptionFlags.NONE, OptionArg.NONE, _("Run in background for theme monitoring"), null);

            set_resource_base_path ("/com/github/Switchcraft/");
            set_accels_for_action ("win.add-command", new string[] {"<Primary>N"});
            set_accels_for_action ("app.quit", new string[] {"<Primary>Q"});
            set_accels_for_action ("win.show-preferences", new string[] {"<Primary>comma"});

            // Add quit action
            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (() => {
                quit ();
            });
            add_action (quit_action);
        }

        private void migrate_config_files () {
            var config_home = Environment.get_user_config_dir ();
            var old_dir = Path.build_filename (config_home, "switchcraft");
            var new_dir = Path.get_dirname (config_path);

            if (FileUtils.test (old_dir, FileTest.IS_DIR) && !FileUtils.test (new_dir, FileTest.EXISTS)) {
                try {
                    DirUtils.create_with_parents (Path.get_dirname (new_dir), 0755);
                    
                    // Use 'mv' via spawn to handle directory move across filesystems if necessary, 
                    // or just rename if on same filesystem. GLib.File.move is better.
                    var old_file = File.new_for_path (old_dir);
                    var new_file = File.new_for_path (new_dir);
                    
                    if (old_file.query_exists ()) {
                        old_file.move (new_file, FileCopyFlags.NONE, null, null);
                        message ("Migrated configuration from %s to %s", old_dir, new_dir);
                    }
                } catch (Error e) {
                    warning ("Failed to migrate configuration: %s", e.message);
                }
            } else if (FileUtils.test (old_dir, FileTest.IS_DIR)) {
                // Both dirs exist: move only what the new dir lacks. Files
                // present in both stay in the old dir untouched.
                try {
                    var dir = Dir.open (old_dir);
                    string? name;
                    while ((name = dir.read_name ()) != null) {
                        var target = Path.build_filename (new_dir, name);
                        if (!FileUtils.test (target, FileTest.EXISTS)) {
                            File.new_for_path (Path.build_filename (old_dir, name))
                                .move (File.new_for_path (target), FileCopyFlags.NONE, null, null);
                        }
                    }
                } catch (Error e) {
                    warning ("Failed to migrate configuration: %s", e.message);
                }
                // Only succeeds once the old dir is empty
                DirUtils.remove (old_dir);
            }
        }

        protected override void activate () {
            migrate_legacy_monitor ();

            // Repair the autostart path (e.g. a moved AppImage) and make sure
            // the monitor runs when it is enabled
            if (get_monitoring_enabled ()) {
                enable_monitoring ();
            }

            // A second launch shows the open window instead of a new one
            var win = get_active_window ();
            if (win == null) {
                win = new MainWindow (this);
            }
            win.present ();
        }

        // Runs in the calling process, so the output reaches its terminal
        protected override int handle_local_options (VariantDict options) {
            if (options.contains ("version")) {
                print ("Switchcraft %s\n", Switchcraft.VERSION);
                return 0;
            }
            return -1;
        }

        protected override int command_line (ApplicationCommandLine command_line) {
            var options = command_line.get_options_dict ();

            if (options.contains ("background")) {
                this.hold ();
                var style_manager = Adw.StyleManager.get_default ();
                
                style_manager.notify["dark"].connect (() => {
                    execute_monitored_commands (style_manager.dark ? "dark" : "light");
                });
                
                // Initial execution
                execute_monitored_commands (style_manager.dark ? "dark" : "light");

                // Plasma ignores the GNOME setting the schedule changes,
                // and switches between light and dark on its own
                if (get_desktop () != "kde") {
                    schedule = new ThemeSchedule (settings);
                }
                
                return -1; // Keep running
            }

            this.activate ();
            return 0;
        }

        public override bool local_command_line (ref unowned string[] args, out int exit_status) {
            foreach (unowned string arg in args) {
                if (arg == "--background" || arg == "-b") {
                    this.set_flags (this.get_flags () | ApplicationFlags.NON_UNIQUE);
                    break;
                }
            }
            return base.local_command_line (ref args, out exit_status);
        }

        // Commands that switch the style back, like a dark command setting
        // prefer-light, would run the commands of both styles in a loop.
        // Switches closer together than LOOP_GAP count as a loop, and
        // the commands stop after LOOP_MAX_RUNS of them in a row.
        private const int64 LOOP_GAP = 2 * TimeSpan.SECOND;
        private const int LOOP_MAX_RUNS = 4;
        private int64 last_switch_time = 0;
        private int quick_switches = 0;

        private void execute_monitored_commands (string theme) {
            var now = get_monotonic_time ();
            quick_switches = last_switch_time > 0 && now - last_switch_time < LOOP_GAP ? quick_switches + 1 : 0;
            last_switch_time = now;
            if (quick_switches >= LOOP_MAX_RUNS) {
                warning ("The style switched %d times in a row, skipping %s commands to stop a loop",
                         quick_switches + 1, theme);
                return;
            }
            execute_commands (theme);
        }

        public void execute_commands (string theme) {
            var commands = get_commands ();
            if (!commands.contains (theme)) return;
            
            unowned List<CommandEntry> theme_commands = commands.get (theme);
            string prefix;
            var env = build_command_env (out prefix);

            foreach (var entry in theme_commands) {
                if (entry.enabled) {
                    try {
                        string[] argv = { "/bin/sh", "-c", prefix + entry.command };
                        Process.spawn_async (
                            null,
                            argv,
                            env,
                            SpawnFlags.SEARCH_PATH,
                            null,
                            null
                        );
                    } catch (Error e) {
                        warning ("Failed to execute command: %s", e.message);
                    }
                }
            }
        }

        private string[] build_command_env (out string prefix) {
            var constants = get_constants ();

            string[] env = Environ.get ();
            // Constants arrive as plain variables. The prefix expands $VARS
            // in their values, like the old bash monitor's eval did.
            var builder = new StringBuilder ();
            var names = constants.get_keys ();
            names.sort (strcmp);
            foreach (var key in names) {
                env = Environ.set_variable (env, key, constants.get (key));
                if (Regex.match_simple ("^[A-Za-z_][A-Za-z0-9_]*$", key)) {
                    builder.append_printf (
                        "__sc=$(eval \"printf '%%s' \\\"$%s\\\"\" 2>/dev/null) && %s=$__sc\n", key, key);
                }
            }
            if (builder.len > 0) {
                builder.append ("unset __sc\n");
            }
            prefix = builder.str;
            return env;
        }

        // Runs a command the way execute_commands does and waits for it.
        // Returns null on success, else its output and exit status.
        public async string? test_command (string command, Cancellable cancellable) throws Error {
            string prefix;
            var env = build_command_env (out prefix);

            // Output goes to a file, so background jobs that keep
            // it open do not hold up the result
            FileIOStream stream;
            var output_file = File.new_tmp ("switchcraft-test-XXXXXX", out stream);
            stream.close ();
            var output_path = output_file.get_path ();

            try {
                var launcher = new SubprocessLauncher (SubprocessFlags.STDERR_MERGE);
                launcher.set_environ (env);
                launcher.set_stdout_file_path (output_path);
                var process = launcher.spawnv ({ "/bin/sh", "-c", prefix + command });
                try {
                    yield process.wait_async (cancellable);
                } catch (IOError.CANCELLED e) {
                    process.force_exit ();
                    throw e;
                }
                if (process.get_successful ()) {
                    return null;
                }

                var status = process.get_if_exited ()
                    ? _("Exited with code %d").printf (process.get_exit_status ())
                    : _("Killed by signal %d").printf (process.get_term_sig ());
                string output;
                FileUtils.get_contents (output_path, out output);
                output = output.make_valid ().strip ();
                return output.length > 0 ? output + "\n" + status : status;
            } finally {
                FileUtils.remove (output_path);
            }
        }

        public HashTable<string, List<CommandEntry>> get_commands () {
            HashTable<string, List<CommandEntry>> commands;
            load_commands (out commands);
            return commands;
        }

        // Returns false if the file exists but cannot be read
        private bool load_commands (out HashTable<string, List<CommandEntry>> commands) {
            commands = default_commands ();
            if (!FileUtils.test (config_path, FileTest.EXISTS)) {
                return true;
            }
            
            try {
                string contents;
                FileUtils.get_contents (config_path, out contents);
                
                var parser = new Json.Parser ();
                parser.load_from_data (contents);
                commands = normalize_commands (parser.get_root ());
                return true;
            } catch (Error e) {
                warning ("Failed to load commands: %s", e.message);
                return false;
            }
        }
        
        public void save_commands (HashTable<string, List<CommandEntry>> commands) {
            var normalized = normalize_commands_to_json (commands);
            
            try {
                var dir = Path.get_dirname (config_path);
                DirUtils.create_with_parents (dir, 0755);
                
                var generator = new Json.Generator ();
                generator.set_root (normalized);
                generator.pretty = true;
                generator.indent = 2;
                
                FileUtils.set_contents (config_path, generator.to_data (null));
            } catch (Error e) {
                warning ("Failed to save commands: %s", e.message);
            }
        }

        private HashTable<string, List<CommandEntry>> default_commands () {
            var commands = new HashTable<string, List<CommandEntry>> (str_hash, str_equal);
            commands.insert ("dark", new List<CommandEntry> ());
            commands.insert ("light", new List<CommandEntry> ());
            return commands;
        }
        
        // Hand-edited files may hold numbers, bools or null where strings
        // are expected. get_string () on those returns null.
        private static string? string_value (Json.Node? node) {
            if (node == null || node.get_value_type () != typeof (string)) {
                return null;
            }
            return node.get_string ();
        }

        private HashTable<string, List<CommandEntry>> normalize_commands (Json.Node? root_node) {
            var commands = default_commands ();
            
            if (root_node == null || root_node.get_node_type () != Json.NodeType.OBJECT) {
                return commands;
            }
            
            var root = root_node.get_object ();
            
            foreach (unowned string theme in new string[] {"dark", "light"}) {
                if (!root.has_member (theme)) {
                    continue;
                }
                
                var member = root.get_member (theme);
                if (member.get_node_type () != Json.NodeType.ARRAY) {
                    continue;
                }
                
                var array = member.get_array ();
                var theme_commands = new List<CommandEntry> ();
                
                array.foreach_element ((arr, idx, node) => {
                    if (node.get_node_type () == Json.NodeType.VALUE) {
                        // String format
                        var cmd = string_value (node);
                        if (cmd != null) {
                            theme_commands.prepend (new CommandEntry (cmd, true));
                        }
                    } else if (node.get_node_type () == Json.NodeType.OBJECT) {
                        // Object format with enabled flag
                        var obj = node.get_object ();
                        var cmd = string_value (obj.get_member ("command"));
                        if (cmd == null) {
                            return;
                        }
                        
                        var enabled_node = obj.get_member ("enabled");
                        var entry = new CommandEntry (cmd,
                            enabled_node == null || enabled_node.get_value_type () != typeof (bool)
                            || enabled_node.get_boolean ());
                        entry.builtin = string_value (obj.get_member ("builtin")) ?? "";
                        entry.value = string_value (obj.get_member ("value")) ?? "";
                        var position_node = obj.get_member ("position");
                        if (position_node != null && position_node.get_value_type () == typeof (int64)) {
                            entry.position = (int) position_node.get_int ();
                        }
                        
                        theme_commands.prepend (entry);
                    }
                });
                
                theme_commands.reverse ();
                commands.replace (theme, (owned) theme_commands);
            }
            
            return commands;
        }
        
        private Json.Node normalize_commands_to_json (HashTable<string, List<CommandEntry>> commands) {
            var root = new Json.Node (Json.NodeType.OBJECT);
            var obj = new Json.Object ();
            
            commands.foreach ((k, v) => {
                unowned string theme = (string) k;
                unowned List<CommandEntry> cmd_list = (List<CommandEntry>) v;
                var array = new Json.Array ();
                
                foreach (var entry in cmd_list) {
                    var entry_obj = new Json.Object ();
                    entry_obj.set_string_member ("command", entry.command);
                    entry_obj.set_boolean_member ("enabled", entry.enabled);
                    if (entry.position >= 0) {
                        entry_obj.set_int_member ("position", entry.position);
                    }
                    if (entry.builtin.length > 0) {
                        entry_obj.set_string_member ("builtin", entry.builtin);
                        entry_obj.set_string_member ("value", entry.value);
                    }
                    
                    var entry_node = new Json.Node (Json.NodeType.OBJECT);
                    entry_node.set_object (entry_obj);
                    array.add_element (entry_node);
                }
                
                var array_node = new Json.Node (Json.NodeType.ARRAY);
                array_node.set_array (array);
                obj.set_member (theme, array_node);
            });
            
            root.set_object (obj);
            return root;
        }
        
        public HashTable<string, string> get_constants () {
            var constants = new HashTable<string, string> (str_hash, str_equal);
            
            if (!FileUtils.test (constants_path, FileTest.EXISTS)) {
                return constants;
            }
            
            try {
                string contents;
                FileUtils.get_contents (constants_path, out contents);
                
                var parser = new Json.Parser ();
                parser.load_from_data (contents);
                var root = parser.get_root ();
                
                if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                    var obj = root.get_object ();
                    obj.foreach_member ((obj, name, node) => {
                        var value = string_value (node);
                        if (value != null) {
                            constants.insert (name, value);
                        }
                    });
                }
            } catch (Error e) {
                warning ("Failed to load constants: %s", e.message);
            }
            
            return constants;
        }
        
        public void save_constants (HashTable<string, string> constants) {
            try {
                var dir = Path.get_dirname (constants_path);
                DirUtils.create_with_parents (dir, 0755);
                
                var root = new Json.Node (Json.NodeType.OBJECT);
                var obj = new Json.Object ();
                
                constants.foreach ((key, value) => {
                    obj.set_string_member (key, value);
                });
                
                root.set_object (obj);
                
                var generator = new Json.Generator ();
                generator.set_root (root);
                generator.pretty = true;
                generator.indent = 2;
                
                FileUtils.set_contents (constants_path, generator.to_data (null));
            } catch (Error e) {
                warning ("Failed to save constants: %s", e.message);
            }
        }

        // --- Theme settings persistence ---

        private HashTable<string, ThemeSettingValue> get_theme_settings () {
            var result = new HashTable<string, ThemeSettingValue> (str_hash, str_equal);

            if (!FileUtils.test (theme_settings_path, FileTest.EXISTS)) {
                return result;
            }

            try {
                string contents;
                FileUtils.get_contents (theme_settings_path, out contents);
                var parser = new Json.Parser ();
                parser.load_from_data (contents);
                var root = parser.get_root ();

                if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                    result = parse_theme_settings (root.get_object ());
                }
            } catch (Error e) {
                warning ("Failed to load theme settings: %s", e.message);
            }

            return result;
        }

        private HashTable<string, ThemeSettingValue> parse_theme_settings (Json.Object obj) {
            var result = new HashTable<string, ThemeSettingValue> (str_hash, str_equal);
            obj.foreach_member ((o, id, node) => {
                if (node.get_node_type () == Json.NodeType.OBJECT) {
                    var setting = node.get_object ();
                    var light_val = string_value (setting.get_member ("light")) ?? "";
                    var dark_val = string_value (setting.get_member ("dark")) ?? "";
                    result.insert (id, new ThemeSettingValue (light_val, dark_val));
                }
            });
            return result;
        }

        // Versions with a Built-in page kept these settings in
        // theme_settings.json. They are regular commands now.
        private void migrate_theme_settings () {
            if (!FileUtils.test (theme_settings_path, FileTest.EXISTS)) {
                return;
            }

            HashTable<string, List<CommandEntry>> commands;
            if (!load_commands (out commands)) {
                // Saving now would replace a commands file we could not read
                return;
            }
            add_theme_setting_commands (commands, get_theme_settings ());
            save_commands (commands);
            FileUtils.remove (theme_settings_path);
            message ("Converted %s into commands", theme_settings_path);
        }

        private void add_theme_setting_commands (HashTable<string, List<CommandEntry>> commands,
                                                 HashTable<string, ThemeSettingValue> settings_data) {
            foreach (var theme in new string[] { "light", "dark" }) {
                var list = new List<CommandEntry> ();
                foreach (var entry in commands.lookup (theme)) {
                    list.append (entry);
                }
                foreach (var setting_id in THEME_SETTING_IDS) {
                    var val = settings_data.lookup (setting_id);
                    var value = val != null ? val.get_for_theme (theme) : "";
                    if (value.length > 0) {
                        list.append (new CommandEntry (build_builtin_command (setting_id, value), true) {
                            builtin = setting_id,
                            value = value
                        });
                    }
                }
                commands.replace (theme, (owned) list);
            }
        }

        public const string[] THEME_SETTING_IDS = {
            // GNOME
            "color-scheme", "accent-color", "icon-theme", "gtk-theme", "cursor-theme", "shell-theme",
            "wallpaper", "night-light",
            // KDE Plasma
            "kde-global-theme", "kde-color-scheme", "kde-plasma-style", "kde-icon-theme",
            "kde-cursor-theme", "kde-wallpaper",
            // Any desktop
            "kvantum-theme"
        };
        // Stored for the shell theme's empty name, since "" means "not set"
        public const string SHELL_THEME_DEFAULT = "Default";
        private const string USER_THEME_SCHEMA = "org.gnome.shell.extensions.user-theme";
        private const string USER_THEME_EXTENSION = "user-theme@gnome-shell-extensions.gcampax.github.com";

        private void get_setting_key (string setting_id, string theme, out string schema_id, out string key) {
            schema_id = "org.gnome.desktop.interface";
            key = setting_id;
            if (setting_id == "shell-theme") {
                schema_id = USER_THEME_SCHEMA;
                key = "name";
            } else if (setting_id == "wallpaper") {
                schema_id = "org.gnome.desktop.background";
                key = theme == "dark" ? "picture-uri-dark" : "picture-uri";
            } else if (setting_id == "night-light") {
                schema_id = "org.gnome.settings-daemon.plugins.color";
                key = "night-light-enabled";
            }
        }

        // "gnome", "kde", or "" for other desktops
        public static string get_desktop () {
            var desktops = (Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? "").down ().split (":");
            if ("kde" in desktops) {
                return "kde";
            }
            return "gnome" in desktops ? "gnome" : "";
        }

        // Built-ins are offered for the running desktop when their tool is installed
        public bool is_setting_available (string setting_id) {
            if (setting_id == "kvantum-theme") {
                return Environment.find_program_in_path ("kvantummanager") != null;
            }
            if (setting_id.has_prefix ("kde-")) {
                return get_desktop () == "kde" && get_kde_program (setting_id) != null;
            }
            if (get_desktop () != "gnome") {
                return false;
            }
            // The value row explains how to get shell themes
            if (setting_id == "shell-theme") {
                return true;
            }
            string schema_id, key;
            string? schema_dir;
            get_setting_key (setting_id, "light", out schema_id, out key);
            var schema = lookup_schema (schema_id, out schema_dir);
            return schema != null && schema.has_key (key);
        }

        // Full path of the Plasma tool that applies the setting, or null
        private static string? get_kde_program (string setting_id) {
            switch (setting_id) {
                case "kde-global-theme":
                    return Environment.find_program_in_path ("plasma-apply-lookandfeel");
                case "kde-color-scheme":
                    return Environment.find_program_in_path ("plasma-apply-colorscheme");
                case "kde-plasma-style":
                    return Environment.find_program_in_path ("plasma-apply-desktoptheme");
                case "kde-cursor-theme":
                    return Environment.find_program_in_path ("plasma-apply-cursortheme");
                case "kde-wallpaper":
                    return Environment.find_program_in_path ("plasma-apply-wallpaperimage");
                case "kde-icon-theme":
                    // Not on PATH, and each distribution keeps it elsewhere
                    foreach (var dir in new string[] { "/usr/libexec", "/usr/lib", "/usr/lib64/libexec",
                                                       "/usr/lib/x86_64-linux-gnu/libexec",
                                                       "/usr/lib/aarch64-linux-gnu/libexec" }) {
                        var path = Path.build_filename (dir, "plasma-changeicons");
                        if (FileUtils.test (path, FileTest.IS_EXECUTABLE)) {
                            return path;
                        }
                    }
                    return Environment.find_program_in_path ("plasma-changeicons");
                default:
                    return null;
            }
        }

        // Whether KDE reports the dark style for this color scheme. Like
        // its portal, a window background darker than gray 192 is dark.
        // Returns false when the scheme is not found.
        public static bool get_kde_scheme_dark (string name, out bool dark) {
            dark = false;
            foreach (var dir in get_data_dirs ("color-schemes")) {
                var key_file = new KeyFile ();
                key_file.set_list_separator (',');
                try {
                    key_file.load_from_file (Path.build_filename (dir, name + ".colors"), KeyFileFlags.NONE);
                    var rgb = key_file.get_integer_list ("Colors:Window", "BackgroundNormal");
                    if (rgb.length < 3) {
                        return false;
                    }
                    dark = (rgb[0] * 11 + rgb[1] * 16 + rgb[2] * 5) / 32 < 192;
                    return true;
                } catch (Error e) {
                    // Not in this folder
                }
            }
            return false;
        }

        // A global theme applies a color scheme, which decides the style
        public static bool get_kde_global_theme_dark (string id, out bool dark) {
            dark = false;
            foreach (var dir in get_data_dirs (Path.build_filename ("plasma", "look-and-feel"))) {
                string contents;
                try {
                    FileUtils.get_contents (Path.build_filename (dir, id, "contents", "defaults"), out contents);
                } catch (FileError e) {
                    // Not in this folder
                    continue;
                }
                // KeyFile rejects group lines like [kdeglobals][General]
                bool in_general = false;
                foreach (var line in contents.split ("\n")) {
                    line = line.strip ();
                    if (line.has_prefix ("[")) {
                        in_general = line == "[kdeglobals][General]";
                    } else if (in_general && line.has_prefix ("ColorScheme=")) {
                        return get_kde_scheme_dark (line.substring ("ColorScheme=".length), out dark);
                    }
                }
                return false;
            }
            return false;
        }

        // A value from an ini file in the config folder, as KDE keeps them, or ""
        private static string read_config_value (string file_name, string group, string key) {
            var key_file = new KeyFile ();
            try {
                key_file.load_from_file (Path.build_filename (Environment.get_user_config_dir (), file_name),
                                         KeyFileFlags.NONE);
                return key_file.get_string (group, key);
            } catch (Error e) {
                return "";
            }
        }

        // Extensions from extensions.gnome.org keep their schema in their
        // own folder, where the default schema source does not look
        private SettingsSchema? lookup_schema (string schema_id, out string? schema_dir) {
            schema_dir = null;
            var source = SettingsSchemaSource.get_default ();
            var schema = source != null ? source.lookup (schema_id, true) : null;
            if (schema != null || schema_id != USER_THEME_SCHEMA) {
                return schema;
            }

            foreach (var base_dir in new string[] { Environment.get_user_data_dir (), "/usr/share" }) {
                var dir = Path.build_filename (base_dir, "gnome-shell", "extensions", USER_THEME_EXTENSION, "schemas");
                if (!FileUtils.test (Path.build_filename (dir, "gschemas.compiled"), FileTest.EXISTS)) {
                    continue;
                }
                try {
                    var extension_source = new SettingsSchemaSource.from_directory (dir, source, false);
                    schema = extension_source.lookup (schema_id, false);
                    if (schema != null) {
                        schema_dir = dir;
                        return schema;
                    }
                } catch (Error e) {
                    warning ("Failed to load schemas from %s: %s", dir, e.message);
                }
            }
            return null;
        }

        public bool has_shell_theme_support () {
            string? schema_dir;
            return lookup_schema (USER_THEME_SCHEMA, out schema_dir) != null;
        }

        // What GNOME currently uses, shown for settings the user has not set
        public string get_current_theme_value (string setting_id, string theme) {
            switch (setting_id) {
                case "kde-global-theme":
                    return read_config_value ("kdeglobals", "KDE", "LookAndFeelPackage");
                case "kde-color-scheme":
                    return read_config_value ("kdeglobals", "General", "ColorScheme");
                case "kde-plasma-style":
                    return read_config_value ("plasmarc", "Theme", "name");
                case "kde-icon-theme":
                    return read_config_value ("kdeglobals", "Icons", "Theme");
                case "kde-cursor-theme":
                    return read_config_value ("kcminputrc", "Mouse", "cursorTheme");
                case "kvantum-theme":
                    return read_config_value (Path.build_filename ("Kvantum", "kvantum.kvconfig"), "General", "theme");
                case "kde-wallpaper":
                    // Plasma keeps one per desktop
                    return "";
            }

            string schema_id, key;
            string? schema_dir;
            get_setting_key (setting_id, theme, out schema_id, out key);
            var schema = lookup_schema (schema_id, out schema_dir);
            if (schema == null || !schema.has_key (key)) {
                return "";
            }

            var key_settings = new Settings.full (schema, null, null);
            if (setting_id == "night-light") {
                return key_settings.get_boolean (key).to_string ();
            }
            var value = key_settings.get_string (key);
            if (setting_id == "shell-theme" && value == "") {
                return SHELL_THEME_DEFAULT;
            }
            if (setting_id == "wallpaper" && value != "") {
                return File.new_for_uri (value).get_path () ?? value;
            }
            return value;
        }

        // The gsettings line a built-in command runs. The wallpaper sets both
        // keys, so it shows whichever style GNOME is in.
        public string build_builtin_command (string setting_id, string value) {
            switch (setting_id) {
                case "kde-global-theme":
                    return "plasma-apply-lookandfeel -a %s".printf (Shell.quote (value));
                case "kde-color-scheme":
                    return "plasma-apply-colorscheme %s".printf (Shell.quote (value));
                case "kde-plasma-style":
                    return "plasma-apply-desktoptheme %s".printf (Shell.quote (value));
                case "kde-icon-theme":
                    return "%s %s".printf (Shell.quote (get_kde_program (setting_id) ?? "plasma-changeicons"),
                                           Shell.quote (value));
                case "kde-cursor-theme":
                    return "plasma-apply-cursortheme %s".printf (Shell.quote (value));
                case "kde-wallpaper":
                    return "plasma-apply-wallpaperimage %s".printf (Shell.quote (value));
                case "kvantum-theme":
                    return "kvantummanager --set %s".printf (Shell.quote (value));
            }

            string schema_id, key;
            string? schema_dir;
            get_setting_key (setting_id, "light", out schema_id, out key);
            lookup_schema (schema_id, out schema_dir);
            var gsettings = schema_dir != null
                ? "gsettings --schemadir %s".printf (Shell.quote (schema_dir))
                : "gsettings";

            if (setting_id == "wallpaper") {
                // Escapes characters like # and % in the path
                var uri = Shell.quote (value.contains ("://") ? value : File.new_for_path (value).get_uri ());
                return "%s set %s picture-uri %s && %s set %s picture-uri-dark %s".printf (
                    gsettings, schema_id, uri, gsettings, schema_id, uri);
            }

            var name = setting_id == "shell-theme" && value == SHELL_THEME_DEFAULT ? "" : value;
            return "%s set %s %s %s".printf (gsettings, schema_id, key, Shell.quote (name));
        }

        public GenericArray<string> scan_setting_values (string setting_id) {
            switch (setting_id) {
                case "color-scheme":
                    return string_array ({ "prefer-light", "prefer-dark", "default" });
                case "accent-color":
                    return string_array ({ "blue", "teal", "green", "yellow", "orange", "red", "pink", "purple", "slate" });
                case "night-light":
                    return string_array ({ "true", "false" });
                case "kde-global-theme":
                    return scan_names (get_data_dirs (Path.build_filename ("plasma", "look-and-feel")), match_kde_package);
                case "kde-color-scheme":
                    return scan_names (get_data_dirs ("color-schemes"), (dir_path, name) => {
                        return name.has_suffix (".colors") ? name.substring (0, name.length - ".colors".length) : null;
                    });
                case "kde-plasma-style":
                    return scan_names (get_data_dirs (Path.build_filename ("plasma", "desktoptheme")), match_kde_package);
                case "kvantum-theme":
                    string[] kvantum_dirs = get_data_dirs ("Kvantum");
                    kvantum_dirs += Path.build_filename (Environment.get_user_config_dir (), "Kvantum");
                    return scan_names (kvantum_dirs, (dir_path, name) => {
                        var config = Path.build_filename (dir_path, name, name + ".kvconfig");
                        return FileUtils.test (config, FileTest.EXISTS) ? name : null;
                    });
                case "icon-theme":
                case "kde-icon-theme":
                    return scan_icon_themes ();
                case "gtk-theme":
                    return scan_gtk_themes ();
                case "cursor-theme":
                case "kde-cursor-theme":
                    return scan_cursor_themes ();
                case "shell-theme":
                    var themes = scan_shell_themes ();
                    themes.insert (0, SHELL_THEME_DEFAULT);
                    return themes;
                default:
                    return new GenericArray<string> ();
            }
        }

        // --- Theme discovery ---

        private static GenericArray<string> string_array (string[] values) {
            var array = new GenericArray<string> ();
            foreach (var value in values) {
                array.add (value);
            }
            return array;
        }

        // The subfolder in the user's and the system's data folders
        private static string[] get_data_dirs (string subdir) {
            string[] dirs = { Path.build_filename (Environment.get_user_data_dir (), subdir) };
            foreach (unowned string dir in Environment.get_system_data_dirs ()) {
                dirs += Path.build_filename (dir, subdir);
            }
            return dirs;
        }

        // The name to list for a folder entry, or null to skip it
        private delegate string? NameMatcher (string dir_path, string name);

        // Sorted names matched in any of the folders, without duplicates
        private GenericArray<string> scan_names (string[] dirs, NameMatcher match) {
            var names = new GenericArray<string> ();
            foreach (var dir_path in dirs) {
                try {
                    var dir = Dir.open (dir_path, 0);
                    string? file_name;
                    while ((file_name = dir.read_name ()) != null) {
                        var name = file_name.has_prefix (".") ? null : match (dir_path, file_name);
                        if (name != null && !array_has_string (names, name)) {
                            names.add (name);
                        }
                    }
                } catch (FileError e) {}
            }
            names.sort (strcmp);
            return names;
        }

        // Plasma packages, like global themes and Plasma styles
        private static string? match_kde_package (string dir_path, string name) {
            var json = Path.build_filename (dir_path, name, "metadata.json");
            var desktop = Path.build_filename (dir_path, name, "metadata.desktop");
            return FileUtils.test (json, FileTest.EXISTS) || FileUtils.test (desktop, FileTest.EXISTS) ? name : null;
        }

        public GenericArray<string> scan_icon_themes () {
            var themes = new GenericArray<string> ();
            foreach (var dir_path in get_icon_search_dirs ()) {
                try {
                    var dir = Dir.open (dir_path, 0);
                    string? name;
                    while ((name = dir.read_name ()) != null) {
                        if (name.has_prefix (".")) continue;
                        var index_path = Path.build_filename (dir_path, name, "index.theme");
                        if (FileUtils.test (index_path, FileTest.EXISTS) && !array_has_string (themes, name)) {
                            themes.add (name);
                        }
                    }
                } catch (FileError e) {}
            }
            themes.sort (strcmp);
            return themes;
        }

        public GenericArray<string> scan_gtk_themes () {
            var themes = new GenericArray<string> ();
            foreach (var dir_path in get_theme_search_dirs ()) {
                try {
                    var dir = Dir.open (dir_path, 0);
                    string? name;
                    while ((name = dir.read_name ()) != null) {
                        if (name.has_prefix (".")) continue;
                        var gtk4 = Path.build_filename (dir_path, name, "gtk-4.0");
                        var gtk3 = Path.build_filename (dir_path, name, "gtk-3.0");
                        if ((FileUtils.test (gtk4, FileTest.IS_DIR) || FileUtils.test (gtk3, FileTest.IS_DIR))
                            && !array_has_string (themes, name)) {
                            themes.add (name);
                        }
                    }
                } catch (FileError e) {}
            }
            themes.sort (strcmp);
            return themes;
        }

        public GenericArray<string> scan_cursor_themes () {
            var themes = new GenericArray<string> ();
            foreach (var dir_path in get_icon_search_dirs ()) {
                try {
                    var dir = Dir.open (dir_path, 0);
                    string? name;
                    while ((name = dir.read_name ()) != null) {
                        if (name.has_prefix (".")) continue;
                        var cursors_path = Path.build_filename (dir_path, name, "cursors");
                        if (FileUtils.test (cursors_path, FileTest.IS_DIR) && !array_has_string (themes, name)) {
                            themes.add (name);
                        }
                    }
                } catch (FileError e) {}
            }
            themes.sort (strcmp);
            return themes;
        }

        public GenericArray<string> scan_shell_themes () {
            var themes = new GenericArray<string> ();
            foreach (var dir_path in get_theme_search_dirs ()) {
                try {
                    var dir = Dir.open (dir_path, 0);
                    string? name;
                    while ((name = dir.read_name ()) != null) {
                        if (name.has_prefix (".")) continue;
                        var shell_css = Path.build_filename (dir_path, name, "gnome-shell", "gnome-shell.css");
                        if (FileUtils.test (shell_css, FileTest.EXISTS) && !array_has_string (themes, name)) {
                            themes.add (name);
                        }
                    }
                } catch (FileError e) {}
            }
            themes.sort (strcmp);
            return themes;
        }

        private bool array_has_string (GenericArray<string> arr, string s) {
            for (uint i = 0; i < arr.length; i++) {
                if (arr[i] == s) return true;
            }
            return false;
        }

        private string[] get_icon_search_dirs () {
            return {
                "/usr/share/icons",
                Path.build_filename (Environment.get_home_dir (), ".local", "share", "icons"),
                Path.build_filename (Environment.get_home_dir (), ".icons")
            };
        }

        private string[] get_theme_search_dirs () {
            return {
                "/usr/share/themes",
                Path.build_filename (Environment.get_home_dir (), ".local", "share", "themes"),
                Path.build_filename (Environment.get_home_dir (), ".themes")
            };
        }

        public bool export_configuration_bundle (GLib.File file, out string error_message) {
            error_message = "";
            var zip_tool = Environment.find_program_in_path ("zip");
            if (zip_tool == null) {
                error_message = _("The 'zip' command is required to export.");
                return false;
            }

            var target_path = file.get_path ();
            if (target_path == null) {
                error_message = _("Destination must be a local file.");
                return false;
            }

            var parent = Path.get_dirname (target_path);
            if (parent != null && parent.length > 0 && parent != ".") {
                if (DirUtils.create_with_parents (parent, 0755) != 0) {
                    error_message = _("Failed to prepare destination directory.");
                    return false;
                }
            }

            var template = Path.build_filename (Environment.get_tmp_dir (), "switchcraft-export-XXXXXX");
            string? temp_dir = DirUtils.mkdtemp (template);
            if (temp_dir == null) {
                error_message = _("Failed to create temporary directory.");
                return false;
            }

            try {
                var commands_node = normalize_commands_to_json (get_commands ());
                var commands_generator = new Json.Generator ();
                commands_generator.set_root (commands_node);
                commands_generator.pretty = true;
                commands_generator.indent = 2;
                var commands_data = commands_generator.to_data (null);
                var commands_path = Path.build_filename (temp_dir, "commands.json");
                FileUtils.set_contents (commands_path, commands_data);

                var constants = get_constants ();
                var constants_root = new Json.Node (Json.NodeType.OBJECT);
                var constants_obj = new Json.Object ();
                constants.foreach ((key, value) => {
                    constants_obj.set_string_member (key, value);
                });
                constants_root.set_object (constants_obj);
                var constants_generator = new Json.Generator ();
                constants_generator.set_root (constants_root);
                constants_generator.pretty = true;
                constants_generator.indent = 2;
                var constants_data = constants_generator.to_data (null);
                var constants_path = Path.build_filename (temp_dir, "constants.json");
                FileUtils.set_contents (constants_path, constants_data);

                if (FileUtils.test (target_path, FileTest.EXISTS)) {
                    if (FileUtils.remove (target_path) != 0) {
                        error_message = _("Unable to overwrite existing archive.");
                        return false;
                    }
                }

                try {
                    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
                    launcher.set_cwd (temp_dir);
                    string[] argv = { zip_tool, "-q", target_path, "commands.json", "constants.json" };
                    var process = launcher.spawnv (argv);
                    process.wait_check (null);
                } catch (Error e) {
                    error_message = _("Failed to write archive: %s").printf (e.message);
                    return false;
                }

                return true;
            } catch (Error e) {
                error_message = e.message;
                return false;
            } finally {
                cleanup_temp_dir (temp_dir);
            }
        }

        public bool import_configuration_bundle (GLib.File file, out string error_message) {
            error_message = "";
            var unzip_tool = Environment.find_program_in_path ("unzip");
            if (unzip_tool == null) {
                error_message = _("The 'unzip' command is required to import.");
                return false;
            }

            var source_path = file.get_path ();
            if (source_path == null) {
                error_message = _("Archive must be a local file.");
                return false;
            }

            var template = Path.build_filename (Environment.get_tmp_dir (), "switchcraft-import-XXXXXX");
            string? temp_dir = DirUtils.mkdtemp (template);
            if (temp_dir == null) {
                error_message = _("Failed to create temporary directory.");
                return false;
            }

            try {
                try {
                    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
                    string[] argv = { unzip_tool, "-qq", "-o", source_path, "-d", temp_dir };
                    var process = launcher.spawnv (argv);
                    process.wait_check (null);
                } catch (Error e) {
                    error_message = _("Failed to unpack archive: %s").printf (e.message);
                    return false;
                }

                var commands_path = Path.build_filename (temp_dir, "commands.json");
                var constants_path = Path.build_filename (temp_dir, "constants.json");

                if (!FileUtils.test (commands_path, FileTest.EXISTS) || !FileUtils.test (constants_path, FileTest.EXISTS)) {
                    error_message = _("Archive must contain commands.json and constants.json at the top level.");
                    return false;
                }

                // Parse and check every file before saving, so a bad archive
                // changes nothing
                string commands_data;
                FileUtils.get_contents (commands_path, out commands_data);
                var commands_parser = new Json.Parser ();
                commands_parser.load_from_data (commands_data);
                var commands_root = commands_parser.get_root ();
                if (commands_root == null || commands_root.get_node_type () != Json.NodeType.OBJECT) {
                    error_message = _("commands.json is not a JSON object.");
                    return false;
                }
                var imported_commands = normalize_commands (commands_root);

                string constants_data;
                FileUtils.get_contents (constants_path, out constants_data);
                var constants_parser = new Json.Parser ();
                constants_parser.load_from_data (constants_data);
                var constants_root = constants_parser.get_root ();
                if (constants_root == null || constants_root.get_node_type () != Json.NodeType.OBJECT) {
                    error_message = _("constants.json is not a JSON object.");
                    return false;
                }

                var constants_obj = constants_root.get_object ();
                var constants_table = new HashTable<string, string> (str_hash, str_equal);
                bool invalid_value = false;
                constants_obj.foreach_member ((obj, name, node) => {
                    var value = string_value (node);
                    if (value != null) {
                        constants_table.insert (name, value);
                    } else {
                        invalid_value = true;
                    }
                });

                if (invalid_value) {
                    error_message = _("constants.json must only contain string values.");
                    return false;
                }

                // Older exports have theme_settings.json. It becomes commands.
                var ts_import_path = Path.build_filename (temp_dir, "theme_settings.json");
                if (FileUtils.test (ts_import_path, FileTest.EXISTS)) {
                    string ts_data;
                    FileUtils.get_contents (ts_import_path, out ts_data);
                    var ts_parser = new Json.Parser ();
                    ts_parser.load_from_data (ts_data);
                    var ts_root = ts_parser.get_root ();
                    if (ts_root == null || ts_root.get_node_type () != Json.NodeType.OBJECT) {
                        error_message = _("theme_settings.json is not a JSON object.");
                        return false;
                    }
                    add_theme_setting_commands (imported_commands, parse_theme_settings (ts_root.get_object ()));
                }

                save_commands (imported_commands);
                save_constants (constants_table);

                return true;
            } catch (Error e) {
                error_message = e.message;
                return false;
            } finally {
                cleanup_temp_dir (temp_dir);
            }
        }

        public bool delete_configuration_files (out string error_message) {
            error_message = "";

            if (FileUtils.test (config_path, FileTest.EXISTS)) {
                if (FileUtils.remove (config_path) != 0) {
                    error_message = _("Failed to remove commands.json.");
                    return false;
                }
            }

            if (FileUtils.test (constants_path, FileTest.EXISTS)) {
                if (FileUtils.remove (constants_path) != 0) {
                    error_message = _("Failed to remove constants.json.");
                    return false;
                }
            }

            if (FileUtils.test (theme_settings_path, FileTest.EXISTS)) {
                if (FileUtils.remove (theme_settings_path) != 0) {
                    error_message = _("Failed to remove theme_settings.json.");
                    return false;
                }
            }

            settings.reset ("monitoring-enabled");

            return true;
        }

        private void cleanup_temp_dir (string dir) {
            try {
                var root = File.new_for_path (dir);
                delete_file_recursive (root);
            } catch (Error e) {
                warning ("Failed to clean temporary directory %s: %s", dir, e.message);
            }
        }

        private void delete_file_recursive (GLib.File file) throws Error {
            GLib.FileInfo info;
            try {
                info = file.query_info (FileAttribute.STANDARD_TYPE, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            } catch (Error e) {
                // If the file vanished, nothing to do
                if (e.code == IOError.NOT_FOUND) {
                    return;
                }
                throw e;
            }

            if (info.get_file_type () == FileType.DIRECTORY) {
                var enumerator = file.enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
                GLib.FileInfo? child_info;
                while ((child_info = enumerator.next_file (null)) != null) {
                    var child = file.get_child (child_info.get_name ());
                    delete_file_recursive (child);
                }
            }

            try {
                file.delete (null);
            } catch (Error e) {
                if (e.code != IOError.NOT_FOUND) {
                    throw e;
                }
            }
        }
        
        public bool get_monitoring_enabled () {
            return settings.get_boolean ("monitoring-enabled");
        }
        
        public void set_monitoring_enabled (bool enabled) {
            settings.set_boolean ("monitoring-enabled", enabled);
            
            // Manage autostart desktop entry
            if (enabled) {
                enable_monitoring ();
            } else {
                disable_monitoring ();
            }
        }
        
        // Matches the monitor binary in native and AppImage installs, but not
        // the AppImage runtime, the GUI or other apps' --background-* options
        private const string MONITOR_PATTERN = "(^|/)switchcraft --background$";
        private const string LEGACY_MONITOR_SCRIPT = "switchcraft-monitor.sh";
        // Only the bash process running the script, not editors or shells
        // that mention its path
        private const string LEGACY_MONITOR_PATTERN = "(^|/)bash .*/switchcraft-monitor\\.sh$";

        private void enable_monitoring () {
            create_autostart_entry ();
            start_monitor ();
        }

        private void disable_monitoring () {
            remove_autostart_entry ();
            // SIGTERM, so an AppImage runtime can unmount cleanly
            run_process ({ "pkill", "-u", Environment.get_user_name (), "-f", MONITOR_PATTERN });
        }

        private void start_monitor () {
            if (run_process ({ "pgrep", "-u", Environment.get_user_name (), "-f", MONITOR_PATTERN }) == 0) {
                return;
            }

            try {
                string[] argv = { get_exec_path (), "--background" };
                Pid pid;
                Process.spawn_async (null, argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD, null, out pid);
                // Reap it if it exits while the GUI is still open
                ChildWatch.add (pid, (child_pid, status) => {
                    Process.close_pid (child_pid);
                });
            } catch (SpawnError e) {
                warning ("Failed to start background monitor: %s", e.message);
            }
        }

        // Returns the exit status, or -1 if the process could not run
        private int run_process (string[] argv) {
            try {
                int wait_status;
                Process.spawn_sync (null, argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL,
                    null, null, null, out wait_status);
                return Process.if_exited (wait_status) ? Process.exit_status (wait_status) : -1;
            } catch (SpawnError e) {
                warning ("Failed to run %s: %s", argv[0], e.message);
                return -1;
            }
        }

        // Inside an AppImage /proc/self/exe points into a temporary mount
        // that is gone once the app exits, so use $APPIMAGE there. It is only
        // trusted when this binary runs from $APPDIR, because both variables
        // leak into processes started from other AppImages (e.g. a terminal).
        private string get_exec_path () {
            string exe_path = "switchcraft";
            try {
                exe_path = FileUtils.read_link ("/proc/self/exe");
            } catch (FileError e) {
                warning ("Failed to resolve executable path: %s", e.message);
            }

            var appimage = Environment.get_variable ("APPIMAGE");
            var appdir = Environment.get_variable ("APPDIR");
            if (appimage != null && appimage != "" && appdir != null && appdir != ""
                && exe_path.has_prefix (appdir + "/")) {
                return appimage;
            }
            return exe_path;
        }

        // Versions before 2.0 ran ~/.local/bin/switchcraft-monitor.sh from
        // the same autostart file. Stop it, delete it and keep the user's
        // choice by switching the built-in monitor on.
        private void migrate_legacy_monitor () {
            var script = Path.build_filename (Environment.get_home_dir (), ".local", "bin", LEGACY_MONITOR_SCRIPT);
            bool legacy_autostart = false;
            if (FileUtils.test (autostart_path, FileTest.EXISTS)) {
                try {
                    string contents;
                    FileUtils.get_contents (autostart_path, out contents);
                    legacy_autostart = contents.contains (LEGACY_MONITOR_SCRIPT);
                } catch (FileError e) {
                    warning ("Failed to read autostart entry: %s", e.message);
                }
            }

            if (!legacy_autostart && !FileUtils.test (script, FileTest.EXISTS)) {
                return;
            }

            run_process ({ "pkill", "-u", Environment.get_user_name (), "-f", LEGACY_MONITOR_PATTERN });
            FileUtils.remove (script);
            // activate () then rewrites the autostart file for the new monitor
            if (legacy_autostart) {
                settings.set_boolean ("monitoring-enabled", true);
            }
            message ("Replaced legacy %s with the built-in monitor", LEGACY_MONITOR_SCRIPT);
        }

        private void create_autostart_entry () {
            string exe_path = get_exec_path ();
            if (exe_path.contains (" ") || exe_path.contains ("\t")) {
                exe_path = "\"%s\"".printf (exe_path);
            }

            string desktop_entry =
                "[Desktop Entry]\n" +
                "Type=Application\n" +
                "Name=%s\n" +
                "Comment=%s\n" +
                "Exec=%s --background\n" +
                "Icon=com.github.Switchcraft\n" +
                "Terminal=false\n" +
                "Categories=Utility;GNOME;GTK;\n" +
                "StartupNotify=false\n" +
                "X-GNOME-Autostart-enabled=true\n" +
                "X-GNOME-Autostart-Delay=2\n" +
                "Hidden=false\n";
            desktop_entry = desktop_entry.printf (
                _("Switchcraft Monitor"),
                _("Monitor GNOME theme changes and run commands"),
                exe_path);
            
            try {
                var dir = Path.get_dirname (autostart_path);
                DirUtils.create_with_parents (dir, 0755);
                FileUtils.set_contents (autostart_path, desktop_entry);
            } catch (Error e) {
                warning ("Failed to create autostart entry: %s", e.message);
            }
        }
        
        private void remove_autostart_entry () {
            if (FileUtils.test (autostart_path, FileTest.EXISTS)) {
                FileUtils.remove (autostart_path);
            }
        }
    }
}
