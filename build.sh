#!/bin/bash
# Quick build script for Switchcraft

set -e

echo "==> Setting up build directory..."
if [ -d "builddir" ]; then
    echo "Build directory exists, reconfiguring..."
    meson setup builddir --reconfigure
else
    meson setup builddir
fi

echo ""
echo "==> Compiling..."
meson compile -C builddir

echo ""
echo "==> Build complete!"
echo "Run with: ./builddir/switchcraft"
echo "Or install with: sudo meson install -C builddir"
