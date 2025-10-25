/* ThemeMonitor.vala
 * 
 * Monitors GNOME theme changes and executes commands
 * Converted from Python to Vala - preserving all logic
 */

namespace Switchcraft {

    public class ThemeMonitor : Object {
        private Application app;
        private Settings settings;
        
        public ThemeMonitor (Application application) {
            app = application;
            settings = new Settings ("org.gnome.desktop.interface");
            settings.changed["color-scheme"].connect (on_theme_changed);
            // Don't execute commands on startup, only on theme changes
        }
        
        private void on_theme_changed () {
            var color_scheme = settings.get_string ("color-scheme");
            var theme = color_scheme == "prefer-dark" ? "dark" : "light";
            
            // Get user-defined constants for substitution
            var constants = app.get_constants ();
            
            var commands = app.get_commands ();
            unowned List<CommandEntry>? theme_commands = commands.lookup (theme);
            
            if (theme_commands == null) {
                return;
            }
            
            foreach (var entry in theme_commands) {
                if (!entry.enabled) {
                    continue;
                }
                
                // Substitute constants in the command
                var expanded_command = expand_constants (entry.command, constants);
                
                // Build environment with constants
                var env = build_env (constants);
                
                try {
                    string[] argv;
                    Shell.parse_argv (expanded_command, out argv);
                    Process.spawn_async (
                        null,  // working directory
                        argv,
                        env,
                        SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                        null,
                        null
                    );
                } catch (Error e) {
                    warning ("Failed to execute command '%s': %s", expanded_command, e.message);
                }
            }
        }
        
        private string expand_constants (string command, HashTable<string, string> constants) {
            var expanded = command;
            
            constants.foreach ((key, value) => {
                // Support both $VAR and ${VAR} syntax
                expanded = expanded.replace ("$" + key, value);
                expanded = expanded.replace ("${" + key + "}", value);
            });
            
            return expanded;
        }
        
        private string[] build_env (HashTable<string, string> constants) {
            // Get current environment
            var env_list = new List<string> ();
            
            foreach (unowned string env_var in Environment.list_variables ()) {
                env_list.append ("%s=%s".printf (env_var, Environment.get_variable (env_var)));
            }
            
            // Add constants as environment variables
            constants.foreach ((key, value) => {
                env_list.append ("%s=%s".printf (key, value));
            });
            
            // Convert list to array
            string[] env_array = new string[env_list.length ()];
            int i = 0;
            foreach (var env_str in env_list) {
                env_array[i++] = env_str;
            }
            
            return env_array;
        }
    }
}
