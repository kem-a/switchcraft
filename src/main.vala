/* main.vala
 * 
 * Application entrypoint for Switchcraft
 * Converted from Python to Vala - preserving all logic
 */

namespace Switchcraft {

    public static int main (string[] args) {
        var app = new Application ();
        new ThemeMonitor (app);
        
        // Background mode: keep app alive without showing window
        bool background_mode = false;
        foreach (var arg in args) {
            if (arg == "--background") {
                background_mode = true;
                break;
            }
        }
        
        if (background_mode) {
            app.hold (); // Prevent app from exiting when no windows are open
            
            // Remove --background from args so GApplication doesn't complain
            string[] filtered_args = {};
            foreach (var arg in args) {
                if (arg != "--background") {
                    filtered_args += arg;
                }
            }
            return app.run (filtered_args);
        }
        
        return app.run (args);
    }
}
