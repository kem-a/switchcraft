project('switchcraft', 'vala', 'c',
  version: '1.0.0',
  meson_version: '>= 0.59.0',
  default_options: [
    'warning_level=2',
    'werror=false',
  ]
)

gnome = import('gnome')

# Application ID
application_id = 'io.github.switchcraft.Switchcraft'

# Dependencies
gtk4_dep = dependency('gtk4', version: '>= 4.0.0')
libadwaita_dep = dependency('libadwaita-1', version: '>= 1.0.0')
gio_dep = dependency('gio-2.0', version: '>= 2.66')
glib_dep = dependency('glib-2.0', version: '>= 2.66')
json_glib_dep = dependency('json-glib-1.0')

# Source files
sources = files(
  'src/main.vala',
  'src/Application.vala',
  'src/MainWindow.vala',
  'src/ConstantsWindow.vala',
  'src/PreferencesWindow.vala',
)

# Vala compiler arguments
vala_args = [
  '--target-glib=2.66',
  '--enable-checking',
]

# Build executable
executable(
  'switchcraft',
  sources,
  dependencies: [
    gtk4_dep,
    libadwaita_dep,
    gio_dep,
    glib_dep,
    json_glib_dep,
  ],
  vala_args: vala_args,
  install: true,
)

# Install desktop file
install_data(
  'switchcraft.desktop',
  install_dir: join_paths(get_option('datadir'), 'applications')
)

# Install application icon
# Install application icons from icons/ directory
# This preserves the hicolor theme structure (e.g. scalable/apps/switchcraft.png)
install_subdir(
  'icons',
  install_dir: join_paths(get_option('datadir'), 'icons'),
  strip_directory: true
)

# Summary
summary({
  'prefix': get_option('prefix'),
  'bindir': get_option('bindir'),
  'datadir': get_option('datadir'),
}, section: 'Directories')

# Create uninstall target
uninstall_script = '''
prefix="@0@"
bindir="@1@"
datadir="@2@"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
autostart_entry="$config_home/autostart/switchcraft-monitor.desktop"
monitor_script="$HOME/.local/bin/switchcraft-monitor.sh"

echo "Uninstalling Switchcraft..."
rm -f "$bindir/switchcraft"
rm -f "$datadir/applications/switchcraft.desktop" 
rm -f "$datadir/icons/hicolor/48x48/apps/switchcraft.png"
rm -f "$datadir/icons/hicolor/96x96/apps/switchcraft.png"
rm -f "$datadir/icons/hicolor/128x128/apps/switchcraft.png"
rm -f "$datadir/icons/hicolor/256x256/apps/switchcraft.png"
rm -f "$datadir/icons/hicolor/512x512/apps/switchcraft.png"
rm -f "$datadir/icons/hicolor/scalable/apps/switchcraft.svg"
rm -f "$datadir/icons/hicolor/scalable/apps/switchcraft_ios.svg"
rm -f "$autostart_entry"
rm -f "$monitor_script"
command -v pkill >/dev/null 2>&1 && pkill -f switchcraft-monitor.sh >/dev/null 2>&1 || true
echo "Uninstallation complete."
'''

run_target('remove',
  command: ['sh', '-c', uninstall_script.format(
    get_option('prefix'),
    join_paths(get_option('prefix'), get_option('bindir')),
    join_paths(get_option('prefix'), get_option('datadir'))
  )]
)
