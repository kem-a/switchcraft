# Translating Switchcraft

## Dependencies

Install the required tools before working with translations:

```bash
# Debian / Ubuntu
sudo apt install gettext python3

# Fedora
sudo dnf install gettext python3
```

The AppStream tooling is optional: if the gettext ITS rules are missing,
`metainfo.xml` strings are skipped.

## Workflow

The helper script at `scripts/translations.sh` regenerates the template,
merges it into the `.po` files and validates the result.

### 1. Regenerate the template only

```bash
./scripts/translations.sh --pot-only
```

This updates `po/switchcraft.pot` and leaves all `.po` files untouched.

### 2. Update all translations

```bash
./scripts/translations.sh
```

This extracts strings, creates missing `.po` files from `po/LINGUAS`, merges
the template into each one and validates every file with `msgfmt`.

### 3. Export untranslated strings

```bash
./scripts/translations.sh --export lv      # -> po/lv.yaml
```

Only untranslated strings are exported. Fuzzy entries are skipped, so fix
those directly in the `.po` file.

### 4. Translate

Open the generated YAML file and fill in the `msgstr` fields:

```yaml
entries:
  - msgid: "Add command"
    msgstr: "Pievienot komandu"
    locations: "src/MainWindow.vala:360"
```

### 5. Import translations

```bash
./scripts/translations.sh --import lv      # reads po/lv.yaml -> po/lv.po
```

The script validates the `.po` file before and after importing.

### 6. Submit

Commit the updated `.po` file and open a pull request.

Useful flags:

- `--check-only` validates every `.po` file without changing anything.
- `--fix` marks broken entries as fuzzy so they can be repaired by hand.
- `--help` prints the full usage text.

## Adding a language

1. Add the language code to `po/LINGUAS` (for example `fr`).
2. Run `./scripts/translations.sh` to create `po/<code>.po` from the template.
3. Use `--export` and `--import` as described above.

## Translation sources

`po/POTFILES` lists every file scanned for translatable strings:

- Vala sources in `src/`
- GtkBuilder UI files in `data/resources/ui/`
- The desktop entry in `data/`
- The GSettings schema
- The AppStream metainfo file

## Translation status

The template currently contains 109 strings. No `.po` files are shipped yet,
so the status table will be added after the first translation round.

## Testing translations locally

```bash
meson setup build --prefix=$HOME/.local
meson compile -C build
meson install -C build
LANGUAGE=de switchcraft
```

For the AppImage, `scripts/make-anyimage.sh` copies the `.mo` files for the
languages in `po/LINGUAS` into the bundle.

## Further Reading

- [GNU gettext Manual](https://www.gnu.org/software/gettext/manual/gettext.html)
- [Meson i18n module](https://mesonbuild.com/i18n-module.html)
- [AppStream metadata](https://www.freedesktop.org/software/appstream/docs/)
