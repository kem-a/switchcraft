#!/usr/bin/env bash
set -euo pipefail

APP_NAME="switchcraft"
BUILD_ROOT="$(pwd)"
DESKTOP_FILE="$BUILD_ROOT/switchcraft.desktop"

if [[ -z "${VERSION:-}" ]]; then
    if [[ -f "$DESKTOP_FILE" ]]; then
        VERSION="$(sed -n 's/^X-AppImage-Version=//p' "$DESKTOP_FILE" | head -n1 | tr -d '[:space:]')"
    else
        VERSION=""
    fi
fi

if [[ -z "${VERSION:-}" ]]; then
    echo "Unable to determine app version (set VERSION env or ensure X-AppImage-Version is present in $DESKTOP_FILE)" >&2
    exit 1
fi
BUILD_DIR="$BUILD_ROOT/builddir"
STAGING_ROOT="$BUILD_ROOT/staging"
DESTDIR="$STAGING_ROOT/$APP_NAME-$VERSION"
DIST_DIR="$BUILD_ROOT/dist"
APPDIR="$STAGING_ROOT/AppDir"

rm -rf "$DESTDIR" "$APPDIR" "$DIST_DIR"
mkdir -p "$DESTDIR" "$APPDIR" "$DIST_DIR"

meson setup "$BUILD_DIR" --prefix /usr --buildtype release --wipe
meson compile -C "$BUILD_DIR"
meson install -C "$BUILD_DIR" --destdir "$DESTDIR"

fpm -s dir -t rpm  -n "$APP_NAME" -v "$VERSION" --license GPL-3.0-or-later \
    --description "GNOME theme switch command runner" \
    --url "https://github.com/kem-a/switchcraft" \
    --chdir "$DESTDIR" --prefix / -p "$DIST_DIR"
fpm -s dir -t deb  -n "$APP_NAME" -v "$VERSION" --license GPL-3.0-or-later \
    --description "GNOME theme switch command runner" \
    --url "https://github.com/kem-a/switchcraft" \
    --chdir "$DESTDIR" --prefix / -p "$DIST_DIR"

cp -a "$DESTDIR/usr" "$APPDIR/"
install -Dm755 "$BUILD_DIR/switchcraft" "$APPDIR/usr/bin/$APP_NAME"
install -Dm755 "$BUILD_DIR/switchcraft" "$APPDIR/AppRun"
install -Dm644 "$DESTDIR/usr/share/applications/switchcraft.desktop" "$APPDIR/switchcraft.desktop"
install -Dm644 "$DESTDIR/usr/share/icons/hicolor/256x256/apps/switchcraft.png" "$APPDIR/switchcraft.png"

desktop-file-validate "$APPDIR/switchcraft.desktop"
chrpath -d "$APPDIR/usr/bin/$APP_NAME" || true
appimagetool "$APPDIR" "$DIST_DIR/${APP_NAME}-${VERSION}.AppImage"