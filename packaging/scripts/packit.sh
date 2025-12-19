#!/usr/bin/env bash
set -euo pipefail

APP_NAME="switchcraft"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DESKTOP_FILE="$REPO_ROOT/com.github.switchcraft.Switchcraft.desktop"

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
BUILD_DIR="$REPO_ROOT/build"
STAGING_ROOT="$REPO_ROOT/staging"
DESTDIR="$STAGING_ROOT/$APP_NAME-$VERSION"
DIST_DIR="$REPO_ROOT/dist"
APPDIR="$STAGING_ROOT/AppDir"
POST_REMOVE_SCRIPT="$SCRIPT_DIR/after-remove.sh"

rm -rf "$DESTDIR" "$APPDIR" "$DIST_DIR"
mkdir -p "$DESTDIR" "$APPDIR" "$DIST_DIR"

if [[ ! -f "$POST_REMOVE_SCRIPT" ]]; then
    echo "Missing post-remove script at $POST_REMOVE_SCRIPT" >&2
    exit 1
fi

chmod +x "$POST_REMOVE_SCRIPT"

cd "$REPO_ROOT"

meson setup "$BUILD_DIR" --prefix /usr --buildtype release --wipe
meson compile -C "$BUILD_DIR"
meson install -C "$BUILD_DIR" --destdir "$DESTDIR"

fpm -s dir -t rpm  -n "$APP_NAME" -v "$VERSION" --license GPL-3.0-or-later \
    --description "GNOME theme switch command runner" \
    --url "https://github.com/kem-a/switchcraft" \
    --after-remove "$POST_REMOVE_SCRIPT" \
    --chdir "$DESTDIR" --prefix / -p "$DIST_DIR"
fpm -s dir -t deb  -n "$APP_NAME" -v "$VERSION" --license GPL-3.0-or-later \
    --description "GNOME theme switch command runner" \
    --url "https://github.com/kem-a/switchcraft" \
    --after-remove "$POST_REMOVE_SCRIPT" \
    --chdir "$DESTDIR" --prefix / -p "$DIST_DIR"

cp -a "$DESTDIR/usr" "$APPDIR/"
install -Dm755 "$BUILD_DIR/switchcraft" "$APPDIR/usr/bin/$APP_NAME"
install -Dm755 "$BUILD_DIR/switchcraft" "$APPDIR/AppRun"
install -Dm644 "$DESTDIR/usr/share/applications/com.github.switchcraft.Switchcraft.desktop" "$APPDIR/com.github.switchcraft.Switchcraft.desktop"
install -Dm644 "$DESTDIR/usr/share/icons/hicolor/512x512/apps/com.github.switchcraft.Switchcraft.png" "$APPDIR/com.github.switchcraft.Switchcraft.png"

desktop-file-validate "$APPDIR/com.github.switchcraft.Switchcraft.desktop"
chrpath -d "$APPDIR/usr/bin/$APP_NAME" || true
appimagetool "$APPDIR" "$DIST_DIR/${APP_NAME}-${VERSION}.AppImage"