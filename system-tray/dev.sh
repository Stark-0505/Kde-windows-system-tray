#!/bin/bash
# ───────────────────────────────────────────────────────────────────
#  Windows Modern System Tray — dev cycle
#
#  The ONLY command to build and install this C++ applet.
#  Do NOT copy directories to ~/.local/share/plasma/plasmoids/
#  or /usr/share/plasma/plasmoids/ — that causes the dark rectangle.
#
#  Usage:  ./dev.sh
# ───────────────────────────────────────────────────────────────────
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SRC_DIR/build"
APP_ID="org.kde.windowsmodern.systemtray"
LAYOUT_FILE="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
PLUGIN_SRC="$BUILD_DIR/lib/plasma/applets/${APP_ID}.so"
PLASMASHELL_STOPPED=0
INSTALL_COMPLETE=0

BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"
info()  { echo -e "${GREEN}==>${RESET} ${BOLD}$*${RESET}"; }
warn()  { echo -e "${YELLOW}==>${RESET} $*"; }
err()   { echo -e "${RED}==>${RESET} $*"; }

restart_plasmashell() {
    if [ "$PLASMASHELL_STOPPED" -eq 1 ] && { [ "${WM_BATCH:-0}" != "1" ] || [ "$INSTALL_COMPLETE" -eq 0 ]; }; then
        systemctl --user start plasma-plasmashell.service || true
    fi
}
trap restart_plasmashell EXIT

# ── Detect install paths ───────────────────────────────────────────
detect_paths() {
    if command -v pkg-config &>/dev/null; then
        QT_PLUGIN_DIR=$(pkg-config --variable=plugindir Qt6Core 2>/dev/null || true)
    fi
    if [ -z "${QT_PLUGIN_DIR:-}" ]; then
        if [ -d /usr/lib64/qt6/plugins ]; then
            QT_PLUGIN_DIR=/usr/lib64/qt6/plugins
        elif [ -d /usr/lib/qt6/plugins ]; then
            QT_PLUGIN_DIR=/usr/lib/qt6/plugins
        else
            QT_PLUGIN_DIR=/usr/lib64/qt6/plugins
        fi
    fi
    PLUGIN_DST="$QT_PLUGIN_DIR/plasma/applets"
    KPACKAGE_DIR="/usr/share/plasma/plasmoids/${APP_ID}"
}

# ── Build ─────────────────────────────────────────────────────────
info "Building..."
cmake -S "$SRC_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "$BUILD_DIR" --parallel "${BUILD_JOBS:-$(nproc)}"

if [ ! -f "$PLUGIN_SRC" ]; then
    err "Build did not produce $PLUGIN_SRC"
    exit 1
fi
if command -v ldd &>/dev/null; then
    MISSING_LIBS="$(ldd "$PLUGIN_SRC" 2>&1 | grep "not found" || true)"
    if [ -n "$MISSING_LIBS" ]; then
        err "The built plugin has unresolved runtime libraries:"
        err "$MISSING_LIBS"
        exit 1
    fi
fi

# ── Stop plasmashell ──────────────────────────────────────────────
info "Stopping plasmashell..."
systemctl --user stop plasma-plasmashell.service 2>/dev/null || true
PLASMASHELL_STOPPED=1
sleep 1

# ── Install .so only (no KPackage) ───────────────────────────────
info "Installing..."
detect_paths

pkexec bash -s <<INSTALLEOF
set -e
mkdir -p "$PLUGIN_DST"
cp "$PLUGIN_SRC" "$PLUGIN_DST/"
rm -rf "$KPACKAGE_DIR"
echo "Installed."
INSTALLEOF

# Repair the known bad layout entry only after the plugin install succeeds.
if grep -q "plugin=metadata" "$LAYOUT_FILE" 2>/dev/null; then
    info "Fixing corrupted plugin=metadata in layout (backup: ${LAYOUT_FILE}.bak)..."
    cp -a "$LAYOUT_FILE" "${LAYOUT_FILE}.bak"
    sed -i "/\[Containments\]\[.*\]\[Applets\]/,/\[/s/^plugin=metadata$/plugin=${APP_ID}/" "$LAYOUT_FILE"
fi

# Also prune local copies (stale .so in ~/.local/lib* takes precedence over /usr)
rm -rf "$HOME/.local/share/plasma/plasmoids/${APP_ID}" 2>/dev/null || true
rm -f "$HOME/.local/lib64/qt6/plugins/plasma/applets/${APP_ID}.so" 2>/dev/null || true
rm -f "$HOME/.local/lib/qt6/plugins/plasma/applets/${APP_ID}.so" 2>/dev/null || true
info "Installed."

# ── Start plasmashell ────────────────────────────────────────────
# Set WM_BATCH=1 to skip the restart here, e.g. when this script is one
# step in a larger scripted install that will restart Plasma Shell itself.
if [ "${WM_BATCH:-0}" = "1" ]; then
    INSTALL_COMPLETE=1
    info "Installed (batch mode — skipping plasmashell restart)."
    exit 0
fi

info "Restarting plasmashell..."
systemctl --user start plasma-plasmashell.service
PLASMASHELL_STOPPED=0
INSTALL_COMPLETE=1
sleep 3

# ── Verify ───────────────────────────────────────────────────────
if [ -x "$SRC_DIR/verify.sh" ]; then
    info "Running health check..."
    bash "$SRC_DIR/verify.sh"
fi
