#!/bin/bash
#
# Build AppImage for Switchcraft using appimagetool
#
# Quick local build from an existing meson build dir. It uses the host's
# GTK4/libadwaita at runtime; use make-anyimage.sh for a portable build.
#
# Usage: ./scripts/make-appimage.sh [build_dir]
#
# Requirements:
#   - Compiled build in the build directory
#   - jq
#   - appimagetool (will be downloaded if not found)
#   - desktop-file-utils (optional, for validation)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${1:-$PROJECT_DIR/build}"

# App info
APP_NAME="Switchcraft"
APP_ID="com.github.Switchcraft"
BINARY_NAME="switchcraft"

# Get version from meson introspect or fallback to meson.build
if command -v jq &>/dev/null && [ -f "$BUILD_DIR/meson-info/intro-projectinfo.json" ]; then
    VERSION=$(jq -r '.version' "$BUILD_DIR/meson-info/intro-projectinfo.json")
else
    VERSION=$(grep -oP "version:\s*'\K[^']+" "$PROJECT_DIR/meson.build" | head -1)
fi
ARCH=$(uname -m)

# Output
PACKAGE_DIR="$PROJECT_DIR"
APPIMAGE_NAME="$APP_NAME-${VERSION}-${ARCH}.AppImage"

echo "=== Building AppImage for $APP_NAME v$VERSION ==="
echo "Build directory: $BUILD_DIR"
echo "Output: $PACKAGE_DIR/$APPIMAGE_NAME"

# Verify build exists
if [ ! -f "$BUILD_DIR/$BINARY_NAME" ]; then
    echo "Error: Binary not found at $BUILD_DIR/$BINARY_NAME"
    echo "Please run 'meson compile -C build' first."
    exit 1
fi

# Check/download appimagetool
APPIMAGETOOL=""
if command -v appimagetool &>/dev/null; then
    APPIMAGETOOL="appimagetool"
elif [ -f "$PROJECT_DIR/appimagetool" ]; then
    APPIMAGETOOL="$PROJECT_DIR/appimagetool"
else
    echo "Downloading appimagetool..."
    curl -Lo "$PROJECT_DIR/appimagetool" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH}.AppImage"
    chmod +x "$PROJECT_DIR/appimagetool"
    APPIMAGETOOL="$PROJECT_DIR/appimagetool"
fi

# Create temporary install tree using meson install
DESTDIR=$(mktemp -d)
APPDIR=$(mktemp -d)
trap "rm -rf '$DESTDIR' '$APPDIR'" EXIT
# mktemp creates 0700 dirs; appimagetool requires the AppDir to be world-readable
chmod 755 "$APPDIR"

# Get the prefix from the build configuration
PREFIX=$(meson introspect "$BUILD_DIR" --buildoptions | jq -r '.[] | select(.name == "prefix") | .value')
echo "Build prefix: $PREFIX"

echo "Installing to staging directory..."
meson install -C "$BUILD_DIR" --destdir "$DESTDIR" --quiet 2>/dev/null || \
    meson install -C "$BUILD_DIR" --destdir "$DESTDIR"

# Installed files are at DESTDIR + PREFIX, we need them under APPDIR/usr
INSTALL_ROOT="$DESTDIR$PREFIX"

if [ ! -d "$INSTALL_ROOT" ]; then
    echo "Error: Install root not found at $INSTALL_ROOT"
    echo "Contents of DESTDIR:"
    find "$DESTDIR" -type d | head -20
    exit 1
fi

echo "Creating AppDir structure..."

# Copy installed files to AppDir/usr
mkdir -p "$APPDIR/usr"
cp -a "$INSTALL_ROOT"/* "$APPDIR/usr/"

# meson skips post-install schema compilation with --destdir
glib-compile-schemas "$APPDIR/usr/share/glib-2.0/schemas"

# AppRun: expose the bundled GSettings schema. No LD_LIBRARY_PATH, since
# it would leak into the user commands the app spawns.
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
export GSETTINGS_SCHEMA_DIR="$HERE/usr/share/glib-2.0/schemas${GSETTINGS_SCHEMA_DIR:+:$GSETTINGS_SCHEMA_DIR}"
exec "$HERE/usr/bin/switchcraft" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# Desktop file and icon at AppDir root
install -Dm644 "$APPDIR/usr/share/applications/$APP_ID.desktop" "$APPDIR/$APP_ID.desktop"
install -Dm644 "$APPDIR/usr/share/icons/hicolor/512x512/apps/$APP_ID.png" "$APPDIR/$APP_ID.png"
ln -sf "$APP_ID.png" "$APPDIR/.DirIcon"

# Validate desktop file
if command -v desktop-file-validate &>/dev/null; then
    desktop-file-validate "$APPDIR/$APP_ID.desktop" || true
fi

# Build AppImage
echo "Creating AppImage..."

# Releases ship only the AnyLinux build, so local builds update to it
UPDATE_INFO="gh-releases-zsync|kem-a|switchcraft|latest|*anylinux*${ARCH}.AppImage.zsync"
echo "Update information: $UPDATE_INFO"

# appimagetool also writes the .zsync file when update info is set
ARCH=$ARCH "$APPIMAGETOOL" --updateinformation "$UPDATE_INFO" "$APPDIR" "$PACKAGE_DIR/$APPIMAGE_NAME"

SIZE=$(du -h "$PACKAGE_DIR/$APPIMAGE_NAME" | cut -f1)

echo ""
echo "=== AppImage created successfully ==="
echo "Output: $PACKAGE_DIR/$APPIMAGE_NAME"
echo "Size: $SIZE"
echo ""
echo "To run: ./$APPIMAGE_NAME"
