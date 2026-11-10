project('switchcraft', 'vala', 'c',
  version: '2.0.0',
  meson_version: '>= 0.59.0',
  default_options: [
    'warning_level=2',
    'werror=false',
  ]
)

gnome = import('gnome')

# Translation domain used by gettext in Vala and C
add_project_arguments('-DGETTEXT_PACKAGE="switchcraft"', language: 'c')

# Application ID
application_id = 'com.github.Switchcraft'

# Dependencies
gtk4_dep = dependency('gtk4', version: '>= 4.0.0')
libadwaita_dep = dependency('libadwaita-1', version: '>= 1.8.0')
gio_dep = dependency('gio-2.0', version: '>= 2.66')
glib_dep = dependency('glib-2.0', version: '>= 2.66')
json_glib_dep = dependency('json-glib-1.0')
# Sunrise and sunset math
m_dep = meson.get_compiler('c').find_library('m', required: false)

# Configuration
conf = configuration_data()
conf.set('VERSION', meson.project_version())
conf.set('BINDIR', join_paths(get_option('prefix'), get_option('bindir')))

config_vala = configure_file(
  input: 'src/Config.vala.in',
  output: 'Config.vala',
  configuration: conf
)

# Metainfo file
metainfo = configure_file(
  input: 'data/com.github.Switchcraft.metainfo.xml.in',
  output: 'com.github.Switchcraft.metainfo.xml',
  configuration: conf,
  install: true,
  install_dir: join_paths(get_option('datadir'), 'metainfo')
)

# Resources
resources = gnome.compile_resources('switchcraft-resources',
  'data/resources/switchcraft.gresource.xml',
  dependencies: metainfo,
  source_dir: [
    meson.current_build_dir(),
    meson.current_source_dir(),
    join_paths(meson.current_source_dir(), 'data', 'resources'),
  ]
)

# Source files
sources = files(
  'src/main.vala',
  'src/Application.vala',
  'src/MainWindow.vala',
  'src/AnimatedRows.vala',
  'src/SlidingToggleGroup.vala',
  'src/CommandDialog.vala',
  'src/ConstantsWindow.vala',
  'src/PreferencesWindow.vala',
  'src/ThemeSchedule.vala',
)
sources += config_vala
sources += resources

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
    m_dep,
  ],
  vala_args: vala_args,
  install: true,
)

# Desktop file
configure_file(
  input: 'data/com.github.Switchcraft.desktop.in',
  output: 'com.github.Switchcraft.desktop',
  configuration: conf,
  install: true,
  install_dir: join_paths(get_option('datadir'), 'applications')
)

# Install application icons
install_data(
  'data/icons/com.github.Switchcraft.png',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', '512x512', 'apps')
)
install_data(
  'data/icons/com.github.Switchcraft.svg',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', 'scalable', 'apps')
)

# GSettings schema
install_data(
  'data/com.github.Switchcraft.gschema.xml',
  install_dir: join_paths(get_option('datadir'), 'glib-2.0', 'schemas')
)
subdir('data')
gnome.post_install(glib_compile_schemas: true)

# Summary
summary({
  'prefix': get_option('prefix'),
  'bindir': get_option('bindir'),
  'datadir': get_option('datadir'),
}, section: 'Directories')

# Translations
subdir('po')

# Create uninstall target
uninstall_script = '''
prefix="@0@"
bindir="@1@"
datadir="@2@"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
autostart_entry="$config_home/autostart/switchcraft-monitor.desktop"

echo "Uninstalling Switchcraft..."
rm -f "$bindir/switchcraft"
rm -f "$datadir/applications/com.github.Switchcraft.desktop" 
rm -f "$datadir/icons/hicolor/512x512/apps/com.github.Switchcraft.png"
rm -f "$datadir/icons/hicolor/scalable/apps/com.github.Switchcraft.svg"
rm -f "$autostart_entry"
command -v pkill >/dev/null 2>&1 && pkill -u "$(id -un)" -f '(^|/)switchcraft --background$' >/dev/null 2>&1 || true
echo "Uninstallation complete."
'''

run_target('remove',
  command: ['sh', '-c', uninstall_script.format(
    get_option('prefix'),
    join_paths(get_option('prefix'), get_option('bindir')),
    join_paths(get_option('prefix'), get_option('datadir'))
  )]
)
