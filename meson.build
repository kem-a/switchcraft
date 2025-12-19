project('switchcraft', 'vala', 'c',
  version: '1.3.0',
  meson_version: '>= 0.59.0',
  default_options: [
    'warning_level=2',
    'werror=false',
  ]
)

i18n = import('i18n')
gnome = import('gnome')

# Application ID
application_id = 'io.github.switchcraft.Switchcraft'

# Dependencies
gtk4_dep = dependency('gtk4', version: '>= 4.0.0')
libadwaita_dep = dependency('libadwaita-1', version: '>= 1.0.0')
gio_dep = dependency('gio-2.0', version: '>= 2.66')
glib_dep = dependency('glib-2.0', version: '>= 2.66')
json_glib_dep = dependency('json-glib-1.0')

# Configuration
conf = configuration_data()
conf.set('VERSION', meson.project_version())

config_vala = configure_file(
  input: 'src/Config.vala.in',
  output: 'Config.vala',
  configuration: conf
)

# Source files
sources = files(
  'src/main.vala',
  'src/Application.vala',
  'src/MainWindow.vala',
  'src/ConstantsWindow.vala',
  'src/PreferencesWindow.vala',
)
sources += config_vala

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

# Desktop file
configure_file(
  input: 'io.github.switchcraft.Switchcraft.desktop.in',
  output: 'io.github.switchcraft.Switchcraft.desktop',
  configuration: conf,
  install: true,
  install_dir: join_paths(get_option('datadir'), 'applications')
)

# Metainfo file
configure_file(
  input: 'io.github.switchcraft.Switchcraft.metainfo.xml.in',
  output: 'io.github.switchcraft.Switchcraft.metainfo.xml',
  configuration: conf,
  install: true,
  install_dir: join_paths(get_option('datadir'), 'metainfo')
)

# Install application icons
install_data(
  'icons/io.github.switchcraft.Switchcraft.png',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', '512x512', 'apps')
)
install_data(
  'icons/io.github.switchcraft.Switchcraft.svg',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', 'scalable', 'apps')
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
rm -f "$datadir/applications/io.github.switchcraft.Switchcraft.desktop" 
rm -f "$datadir/icons/hicolor/512x512/apps/io.github.switchcraft.Switchcraft.png"
rm -f "$datadir/icons/hicolor/scalable/apps/io.github.switchcraft.Switchcraft.svg"
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
