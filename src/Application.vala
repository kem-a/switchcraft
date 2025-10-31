/* Application.vala
 * 
 * Main application class with configuration management
 * Converted from Python to Vala - preserving all logic
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
        private string settings_path;
        private string autostart_path;
        private string monitor_script_path;
        private string local_bin_path;
    private string? monitor_script_source_path;
        
        public Application () {
            Object (
                application_id: "io.github.switchcraft.Switchcraft",
                flags: ApplicationFlags.FLAGS_NONE
            );
            
            var home = Environment.get_home_dir ();
            config_path = Path.build_filename (home, ".config", "switchcraft", "commands.json");
            constants_path = Path.build_filename (home, ".config", "switchcraft", "constants.json");
            settings_path = Path.build_filename (home, ".config", "switchcraft", "settings.json");
            autostart_path = Path.build_filename (home, ".config", "autostart", "switchcraft-monitor.desktop");
            local_bin_path = Path.build_filename (home, ".local", "bin");
            monitor_script_path = Path.build_filename (local_bin_path, "switchcraft-monitor.sh");
            monitor_script_source_path = find_monitor_script_source ();
            
            set_resource_base_path ("/io/github/switchcraft/Switchcraft/");
            set_accels_for_action ("win.add-command", {"<Primary>N"});
            set_accels_for_action ("app.quit", {"<Primary>Q"});
            
            // Add quit action
            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (() => {
                quit ();
            });
            add_action (quit_action);
        }
        
        protected override void activate () {
            var win = new MainWindow (this);
            win.present ();
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
        
        public bool get_monitoring_enabled () {
            if (!FileUtils.test (settings_path, FileTest.EXISTS)) {
                return false;
            }
            
            try {
                string contents;
                FileUtils.get_contents (settings_path, out contents);
                
                var parser = new Json.Parser ();
                parser.load_from_data (contents);
                var root = parser.get_root ();
                
                if (root.get_node_type () == Json.NodeType.OBJECT) {
                    var obj = root.get_object ();
                    if (obj.has_member ("monitoring_enabled")) {
                        return obj.get_boolean_member ("monitoring_enabled");
                    }
                }
            } catch (Error e) {
                warning ("Failed to load settings: %s", e.message);
            }
            
            return false;
        }
        
        public void set_monitoring_enabled (bool enabled) {
            var settings = new Json.Object ();
            
            // Load existing settings
            if (FileUtils.test (settings_path, FileTest.EXISTS)) {
                try {
                    string contents;
                    FileUtils.get_contents (settings_path, out contents);
                    
                    var parser = new Json.Parser ();
                    parser.load_from_data (contents);
                    var root = parser.get_root ();
                    
                    if (root.get_node_type () == Json.NodeType.OBJECT) {
                        settings = root.get_object ();
                    }
                } catch (Error e) {
                    // Ignore errors, use empty settings
                }
            }
            
            // Update monitoring_enabled
            settings.set_boolean_member ("monitoring_enabled", enabled);
            
            // Save settings
            try {
                var dir = Path.get_dirname (settings_path);
                DirUtils.create_with_parents (dir, 0755);
                
                var root = new Json.Node (Json.NodeType.OBJECT);
                root.set_object (settings);
                
                var generator = new Json.Generator ();
                generator.set_root (root);
                generator.pretty = true;
                generator.indent = 2;
                
                FileUtils.set_contents (settings_path, generator.to_data (null));
            } catch (Error e) {
                warning ("Failed to save settings: %s", e.message);
            }
            
            // Manage autostart desktop entry and monitor script
            if (enabled) {
                enable_monitoring ();
            } else {
                disable_monitoring ();
            }
        }
        
        private void enable_monitoring () {
            // Ensure ~/.local/bin exists and script is installed
            install_monitor_script ();
            
            // Create autostart desktop entry
            create_autostart_entry ();
            
            // Start monitor script immediately
            try {
                string[] argv = { monitor_script_path };
                Process.spawn_async (
                    null,  // working directory
                    argv,
                    null,  // env
                    SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                    null,
                    null
                );
            } catch (Error e) {
                warning ("Failed to start monitor script: %s", e.message);
            }
        }
        
        private void install_monitor_script () {
            // Ensure ~/.local/bin exists
            try {
                DirUtils.create_with_parents (local_bin_path, 0755);
            } catch (Error e) {
                warning ("Failed to create ~/.local/bin: %s", e.message);
                return;
            }

            var source_path = monitor_script_source_path;
            if (source_path == null || !FileUtils.test (source_path, FileTest.IS_REGULAR)) {
                source_path = find_monitor_script_source ();
                monitor_script_source_path = source_path;
            }

            if (source_path == null) {
                warning ("Monitor script source not found; cannot install monitor script.");
                return;
            }

            var source_file = File.new_for_path (source_path);
            var dest_file = File.new_for_path (monitor_script_path);

            try {
                source_file.copy (dest_file, FileCopyFlags.OVERWRITE, null, null);
            } catch (Error e) {
                warning ("Failed to install monitor script: %s", e.message);
                return;
            }

            try {
                FileUtils.chmod (monitor_script_path, 0755);
            } catch (Error e) {
                warning ("Failed to set monitor script executable: %s", e.message);
            }
        }

        private string? find_monitor_script_source () {
            string? candidate = null;

            var user_data_dir = Environment.get_user_data_dir ();
            if (user_data_dir != null && user_data_dir.length > 0) {
                candidate = Path.build_filename (user_data_dir, "switchcraft", "switchcraft-monitor.sh");
                if (FileUtils.test (candidate, FileTest.IS_REGULAR)) {
                    return candidate;
                }
            }

            foreach (unowned string dir in Environment.get_system_data_dirs ()) {
                candidate = Path.build_filename (dir, "switchcraft", "switchcraft-monitor.sh");
                if (FileUtils.test (candidate, FileTest.IS_REGULAR)) {
                    return candidate;
                }
            }

            var env_source_root = Environment.get_variable ("MESON_SOURCE_ROOT");
            if (env_source_root != null && env_source_root.length > 0) {
                candidate = Path.build_filename (env_source_root, "switchcraft-monitor.sh");
                if (FileUtils.test (candidate, FileTest.IS_REGULAR)) {
                    return candidate;
                }
            }

            var current_dir = Environment.get_current_dir ();
            candidate = Path.build_filename (current_dir, "switchcraft-monitor.sh");
            if (FileUtils.test (candidate, FileTest.IS_REGULAR)) {
                return candidate;
            }

            candidate = Path.build_filename (current_dir, "..", "switchcraft-monitor.sh");
            if (FileUtils.test (candidate, FileTest.IS_REGULAR)) {
                return candidate;
            }

            var prgname = Environment.get_prgname ();
            if (prgname != null && prgname.length > 0) {
                var exec_path = Environment.find_program_in_path (prgname);
                if (exec_path != null && exec_path.length > 0) {
                    var exec_dir = Path.get_dirname (exec_path);

                    candidate = Path.build_filename (exec_dir, "..", "share", "switchcraft", "switchcraft-monitor.sh");
                    if (FileUtils.test (candidate, FileTest.IS_REGULAR)) {
                        return candidate;
                    }

                    candidate = Path.build_filename (exec_dir, "..", "share", "switchcraft-monitor.sh");
                    if (FileUtils.test (candidate, FileTest.IS_REGULAR)) {
                        return candidate;
                    }

                    candidate = Path.build_filename (exec_dir, "switchcraft-monitor.sh");
                    if (FileUtils.test (candidate, FileTest.IS_REGULAR)) {
                        return candidate;
                    }
                }
            }

            return null;
        }
        
        private void disable_monitoring () {
            // Remove autostart entry
            remove_autostart_entry ();
            
            // Kill any running monitor processes
            try {
                Process.spawn_command_line_sync ("pkill -f switchcraft-monitor.sh");
            } catch (Error e) {
                // Ignore errors if no process found
            }

            // Remove installed monitor script
            if (FileUtils.test (monitor_script_path, FileTest.EXISTS)) {
                try {
                    FileUtils.remove (monitor_script_path);
                } catch (Error e) {
                    warning ("Failed to remove monitor script: %s", e.message);
                }
            }
        }
        
        private void create_autostart_entry () {
            string desktop_entry = """[Desktop Entry]
Type=Application
Name=Switchcraft Monitor
Comment=Monitor GNOME theme changes and run commands
Exec=%s
Icon=switchcraft
Terminal=false
Categories=Utility;GNOME;GTK;
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=2
Hidden=false
""".printf (monitor_script_path);
            
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
