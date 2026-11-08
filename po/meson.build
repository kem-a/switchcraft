i18n = import('i18n')
fs = import('fs')

# Wire only languages that already have a .po file. This keeps the build
# working while po/LINGUAS lists languages whose .po files are not created yet.
# Use scripts/translations.sh --pot-only for the template: Meson's own pot
# target does not extract the AppStream metainfo strings.
languages = []
foreach lang : fs.read('LINGUAS').strip().split('\n')
  lang = lang.strip()
  if lang != '' and not lang.startswith('#') and fs.exists(lang + '.po')
    languages += lang
  endif
endforeach

if languages.length() > 0
  i18n.gettext(
    meson.project_name(),
    preset: 'glib',
    languages: languages
  )
else
  run_target(
    'switchcraft-pot',
    command: [
      find_program('translations.sh', dirs: [meson.project_source_root() / 'scripts']),
      '--pot-only'
    ]
  )
endif
