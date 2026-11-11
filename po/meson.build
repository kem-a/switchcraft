i18n = import('i18n')
fs = import('fs')

# Wire every language listed in LINGUAS. The existence check keeps the build
# working if a language is added to LINGUAS before its .po file is created.
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
