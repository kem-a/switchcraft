#!/bin/sh
#
# Build AnyLinux AppImage for Switchcraft using quick-sharun + sharun
#
# Produces a truly portable AppImage that works on any Linux distro,
# including old glibc, musl-based, and non-FHS systems.
#
# The script auto-detects whether it's running inside Arch Linux.
# If not, it will use podman to run itself inside a container.
#
# Usage:  ./packaging/scripts/make-anyimage.sh
# Output: ./build-anyimage/dist/Switchcraft-<version>-anylinux-<arch>.AppImage
#

set -eu

CONTAINER_IMAGE="ghcr.io/pkgforge-dev/archlinux:latest"
CONTAINER_NAME="switchcraft-anylinux-build"

# ── Container bootstrap ─────────────────────────────────────────────
# If not running inside the Arch container, re-exec inside one.
_inside_arch() {
    [ -f /etc/arch-release ] 2>/dev/null
}

if ! _inside_arch; then
    if ! command -v podman >/dev/null 2>&1; then
        echo "Error: podman is required to build outside of Arch Linux."
        echo "Install it with your package manager, e.g.:"
        echo "  sudo dnf install podman   # Fedora"
        echo "  sudo apt install podman   # Debian/Ubuntu"
        exit 1
    fi

    # Check if image is available locally
    if ! podman image exists "$CONTAINER_IMAGE" 2>/dev/null; then
        printf "Arch container image not found locally.\n"
        printf "Pull %s? [Y/n] " "$CONTAINER_IMAGE"
        read -r answer </dev/tty || answer=""
        case "$answer" in
            [nN]*) echo "Aborted."; exit 1 ;;
        esac
        podman pull "$CONTAINER_IMAGE"
    fi

    # Reuse an existing container if available, otherwise create one.
    # This avoids re-downloading packages on every build.
    if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "=== Reusing existing Arch container ($CONTAINER_NAME) ==="
        exec podman start -ai "$CONTAINER_NAME"
    else
        echo "=== Creating Arch Linux container ($CONTAINER_NAME) ==="
        exec podman run \
            -v "$PWD":/src:Z \
            -w /src \
            --name "$CONTAINER_NAME" \
            "$CONTAINER_IMAGE" \
            sh packaging/scripts/make-anyimage.sh
    fi
fi

# ── From here on we are inside Arch Linux ────────────────────────────

ARCH=$(uname -m)
SHARUN_URL="https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/quick-sharun.sh"
DEBLOATED_URL="https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/get-debloated-pkgs.sh"

# ── Install build dependencies ──────────────────────────────────────
echo "Installing build dependencies..."
echo "---------------------------------------------------------------"
pacman -Syu --noconfirm \
    base-devel \
    meson \
    vala \
    glib2 \
    gtk4 \
    libadwaita \
    json-glib \
    jq \
    zsync \
    desktop-file-utils \
    wget \
    xorg-server-xvfb

# ── Install debloated packages ──────────────────────────────────────
echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
if command -v get-debloated-pkgs >/dev/null 2>&1; then
    get-debloated-pkgs --add-common --prefer-nano
else
    wget --retry-connrefused --tries=30 "$DEBLOATED_URL" -O /tmp/get-debloated-pkgs.sh
    chmod +x /tmp/get-debloated-pkgs.sh
    /tmp/get-debloated-pkgs.sh --add-common --prefer-nano
fi

# ── Build and install switchcraft ────────────────────────────────────
echo "Building switchcraft..."
echo "---------------------------------------------------------------"
# Use a separate build dir to avoid conflicts with the host build/
rm -rf build-anyimage
meson setup build-anyimage --prefix=/usr
meson compile -C build-anyimage
meson install -C build-anyimage

# ── Get version ──────────────────────────────────────────────────────
VERSION=$(meson introspect build-anyimage --projectinfo 2>/dev/null \
    | awk -F'"' '/"version"/{print $4}')

# ── Configure AppImage ───────────────────────────────────────────────
export ARCH VERSION
export APPDIR=./build-anyimage/AppDir
export OUTPATH=./build-anyimage/dist
export OUTNAME="Switchcraft-${VERSION}-anylinux-${ARCH}.AppImage"
export UPINFO="gh-releases-zsync|kem-a|switchcraft|latest|*anylinux*${ARCH}.AppImage.zsync"
export ICON=/usr/share/icons/hicolor/scalable/apps/com.github.Switchcraft.svg
export DESKTOP=/usr/share/applications/com.github.Switchcraft.desktop

# ── Download quick-sharun if not already available ───────────────────
if command -v quick-sharun >/dev/null 2>&1; then
    QS=quick-sharun
else
    wget --retry-connrefused --tries=30 "$SHARUN_URL" -O /tmp/quick-sharun
    chmod +x /tmp/quick-sharun
    QS=/tmp/quick-sharun
fi

# ── Bundle with quick-sharun ────────────────────────────────────────
echo "Bundling AppImage..."
echo "---------------------------------------------------------------"

# Bundle main binary + helper tools invoked as subprocesses.
# quick-sharun will auto-detect GTK4, libadwaita, and all their deps.
# jq is needed for the monitor script
# /usr/share/vala is needed for Vala runtime data
# GIO modules for TLS and proxy are needed since the app uses gio
"$QS" \
    /usr/bin/switchcraft \
    /usr/bin/jq \
    /usr/share/vala \
    /usr/lib/gio/modules/libgiognomeproxy.so \
    /usr/lib/gio/modules/libgiognutls.so \
    /usr/lib/gio/modules/libgiolibproxy.so

# ── Create AppImage ─────────────────────────────────────────────────
"$QS" --make-appimage

# ── Clean up intermediate artifacts ─────────────────────────────────
rm -rf "$APPDIR"
rm -f "$OUTPATH"/appinfo

echo ""
echo "=== AnyLinux AppImage created ==="
echo "Output: $OUTPATH/$OUTNAME"