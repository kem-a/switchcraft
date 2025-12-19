/* Application.vala
 * Main application class with configuration management
 *
 * Copyright (c) 2021-2025 kem-a
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Switchcraft {

    public class CommandEntry : Object {
        public string command { get; set; }
        public bool enabled { get; set; default = true; }
        
        public CommandEntry (string cmd, bool en = true) {
            command = cmd;
            enabled = en;
        }
    }

    public class Application : Adw.Application {
        private string config_path;
        private string constants_path;
        private string autostart_path;
        private Settings settings;
        private const string DEFAULT_VERSION = Switchcraft.VERSION;
        
        public Application () {
            Object (
                application_id: "com.github.switchcraft.Switchcraft",
                flags: ApplicationFlags.HANDLES_COMMAND_LINE
            );
            
            var data_dir = Environment.get_user_data_dir ();
            var config_home = Environment.get_user_config_dir ();
            
            config_path = Path.build_filename (data_dir, "switchcraft", "commands.json");
            constants_path = Path.build_filename (data_dir, "switchcraft", "constants.json");
            autostart_path = Path.build_filename (config_home, "autostart", "switchcraft-monitor.desktop");
            
            settings = new Settings ("com.github.switchcraft.Switchcraft");

            migrate_config_files ();

            add_main_option ("version", 'v', OptionFlags.NONE, OptionArg.NONE, "Show version information", null);
            add_main_option ("background", 'b', OptionFlags.NONE, OptionArg.NONE, "Run in background for theme monitoring", null);

            set_resource_base_path ("/com/github/switchcraft/Switchcraft/");
            set_accels_for_action ("win.add-command", {"<Primary>N"});
            set_accels_for_action ("app.quit", {"<Primary>Q"});
            set_accels_for_action ("win.show-preferences", {"<Primary>comma"});
            set_accels_for_action ("win.show-shortcuts", {"<Primary>question"});
            
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
            }
        }
        
        protected override void activate () {
            var win = new MainWindow (this);
            win.present ();
        }

        protected override int command_line (ApplicationCommandLine command_line) {
            var options = command_line.get_options_dict ();

            if (options.contains ("version")) {
                print ("Switchcraft %s\n", Switchcraft.VERSION);
                return 0;
            }

            if (options.contains ("background")) {
                this.hold ();
                var style_manager = Adw.StyleManager.get_default ();
                
                style_manager.notify["dark"].connect (() => {
                    if (style_manager.dark) {
                        execute_commands ("dark");
                    } else {
                        execute_commands ("light");
                    }
                });
                
                // Initial execution
                if (style_manager.dark) {
                    execute_commands ("dark");
                } else {
                    execute_commands ("light");
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

        public void execute_commands (string theme) {
            var commands = get_commands ();
            if (!commands.contains (theme)) return;
            
            unowned List<CommandEntry> theme_commands = commands.get (theme);
            var constants = get_constants ();
            
            string[] env = Environ.get ();
            foreach (var key in constants.get_keys ()) {
                env = Environ.set_variable (env, key, constants.get (key));
            }
            
            foreach (var entry in theme_commands) {
                if (entry.enabled) {
                    try {
                        string[] argv = { "/bin/sh", "-c", entry.command };
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

        public HashTable<string, List<CommandEntry>> get_commands () {
            if (!FileUtils.test (config_path, FileTest.EXISTS)) {
                return default_commands ();
            }
            
            try {
                string contents;
                FileUtils.get_contents (config_path, out contents);
                
                var parser = new Json.Parser ();
                parser.load_from_data (contents);
                var root = parser.get_root ();
                
                return normalize_commands (root);
            } catch (Error e) {
                warning ("Failed to load commands: %s", e.message);
                return default_commands ();
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
        
        private HashTable<string, List<CommandEntry>> normalize_commands (Json.Node root_node) {
            var commands = default_commands ();
            
            if (root_node.get_node_type () != Json.NodeType.OBJECT) {
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
                        var cmd = node.get_string ();
                        theme_commands.prepend (new CommandEntry (cmd, true));
                    } else if (node.get_node_type () == Json.NodeType.OBJECT) {
                        // Object format with enabled flag
                        var obj = node.get_object ();
                        if (!obj.has_member ("command")) {
                            return;
                        }
                        
                        var cmd = obj.get_string_member ("command");
                        var enabled = obj.has_member ("enabled") ? 
                            obj.get_boolean_member ("enabled") : true;
                        
                        theme_commands.prepend (new CommandEntry (cmd, enabled));
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
            
            commands.foreach ((theme, cmd_list) => {
                var array = new Json.Array ();
                
                foreach (var entry in cmd_list) {
                    var entry_obj = new Json.Object ();
                    entry_obj.set_string_member ("command", entry.command);
                    entry_obj.set_boolean_member ("enabled", entry.enabled);
                    
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
                
                if (root.get_node_type () == Json.NodeType.OBJECT) {
                    var obj = root.get_object ();
                    obj.foreach_member ((obj, name, node) => {
                        if (node.get_node_type () == Json.NodeType.VALUE) {
                            constants.insert (name, node.get_string ());
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

        public bool export_configuration_bundle (GLib.File file, out string error_message) {
            error_message = "";
            var zip_tool = Environment.find_program_in_path ("zip");
            if (zip_tool == null) {
                error_message = "The 'zip' command is required to export.";
                return false;
            }

            var target_path = file.get_path ();
            if (target_path == null) {
                error_message = "Destination must be a local file.";
                return false;
            }

            try {
                var parent = Path.get_dirname (target_path);
                if (parent != null && parent.length > 0 && parent != ".") {
                    DirUtils.create_with_parents (parent, 0755);
                }
            } catch (Error e) {
                error_message = "Failed to prepare destination: %s".printf (e.message);
                return false;
            }

            string temp_dir;
            try {
                var template = Path.build_filename (Environment.get_tmp_dir (), "switchcraft-export-XXXXXX");
                temp_dir = DirUtils.mkdtemp (template);
            } catch (Error e) {
                error_message = "Failed to create temporary directory: %s".printf (e.message);
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
                    try {
                        FileUtils.remove (target_path);
                    } catch (Error e) {
                        error_message = "Unable to overwrite existing archive: %s".printf (e.message);
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
                    error_message = "Failed to write archive: %s".printf (e.message);
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
                error_message = "The 'unzip' command is required to import.";
                return false;
            }

            var source_path = file.get_path ();
            if (source_path == null) {
                error_message = "Archive must be a local file.";
                return false;
            }

            string temp_dir;
            try {
                var template = Path.build_filename (Environment.get_tmp_dir (), "switchcraft-import-XXXXXX");
                temp_dir = DirUtils.mkdtemp (template);
            } catch (Error e) {
                error_message = "Failed to create temporary directory: %s".printf (e.message);
                return false;
            }

            try {
                try {
                    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
                    string[] argv = { unzip_tool, "-qq", "-o", source_path, "-d", temp_dir };
                    var process = launcher.spawnv (argv);
                    process.wait_check (null);
                } catch (Error e) {
                    error_message = "Failed to unpack archive: %s".printf (e.message);
                    return false;
                }

                var commands_path = Path.build_filename (temp_dir, "commands.json");
                var constants_path = Path.build_filename (temp_dir, "constants.json");

                if (!FileUtils.test (commands_path, FileTest.EXISTS) || !FileUtils.test (constants_path, FileTest.EXISTS)) {
                    error_message = "Archive must contain commands.json and constants.json at the top level.";
                    return false;
                }

                string commands_data;
                FileUtils.get_contents (commands_path, out commands_data);
                var commands_parser = new Json.Parser ();
                commands_parser.load_from_data (commands_data);
                var commands_root = commands_parser.get_root ();
                if (commands_root.get_node_type () != Json.NodeType.OBJECT) {
                    error_message = "commands.json is not a JSON object.";
                    return false;
                }
                var imported_commands = normalize_commands (commands_root);
                save_commands (imported_commands);

                string constants_data;
                FileUtils.get_contents (constants_path, out constants_data);
                var constants_parser = new Json.Parser ();
                constants_parser.load_from_data (constants_data);
                var constants_root = constants_parser.get_root ();
                if (constants_root.get_node_type () != Json.NodeType.OBJECT) {
                    error_message = "constants.json is not a JSON object.";
                    return false;
                }

                var constants_obj = constants_root.get_object ();
                var constants_table = new HashTable<string, string> (str_hash, str_equal);
                bool invalid_value = false;
                constants_obj.foreach_member ((obj, name, node) => {
                    if (node.get_node_type () == Json.NodeType.VALUE && node.get_value_type () == GLib.Type.STRING) {
                        constants_table.insert (name, node.get_string ());
                    } else {
                        invalid_value = true;
                    }
                });

                if (invalid_value) {
                    error_message = "constants.json must only contain string values.";
                    return false;
                }

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

            try {
                if (FileUtils.test (config_path, FileTest.EXISTS)) {
                    FileUtils.remove (config_path);
                }
            } catch (Error e) {
                error_message = "Failed to remove commands.json: %s".printf (e.message);
                return false;
            }

            try {
                if (FileUtils.test (constants_path, FileTest.EXISTS)) {
                    FileUtils.remove (constants_path);
                }
            } catch (Error e) {
                error_message = "Failed to remove constants.json: %s".printf (e.message);
                return false;
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
        
        private void enable_monitoring () {
            // Create autostart desktop entry
            create_autostart_entry ();
            
            // Start app in background immediately
            try {
                string exe_path = "switchcraft";
                try {
                    exe_path = FileUtils.read_link ("/proc/self/exe");
                } catch (Error e) {
                    // Fallback to "switchcraft" if read_link fails
                }

                string[] argv = { exe_path, "--background" };
                Process.spawn_async (
                    null,
                    argv,
                    null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                    null,
                    null
                );
            } catch (Error e) {
                warning ("Failed to start background monitor: %s", e.message);
            }
        }
        
        private void disable_monitoring () {
            // Remove autostart entry
            remove_autostart_entry ();
            
            // Kill any running background processes
            try {
                Process.spawn_command_line_sync ("pkill -f \"switchcraft --background\"");
            } catch (Error e) {
                // Ignore errors if no process found
            }
        }
        
        private void create_autostart_entry () {
            string exe_path = "switchcraft";
            try {
                exe_path = FileUtils.read_link ("/proc/self/exe");
            } catch (Error e) {
                // Fallback to "switchcraft" if read_link fails
            }

            string desktop_entry = """[Desktop Entry]
Type=Application
Name=Switchcraft Monitor
Comment=Monitor GNOME theme changes and run commands
Exec=%s --background
Icon=com.github.switchcraft.Switchcraft
Terminal=false
Categories=Utility;GNOME;GTK;
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=2
Hidden=false
""".printf (exe_path);
            
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
