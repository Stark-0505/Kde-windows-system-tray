#!/bin/bash
# ───────────────────────────────────────────────────────────────────
#  verify.sh — check system tray is installed and working correctly
# ───────────────────────────────────────────────────────────────────
set -euo pipefail

APP_ID="org.kde.windowsmodern.systemtray"

# Same Qt plugin-dir detection as dev.sh (Fedora: /usr/lib64, Arch/Debian: /usr/lib...)
if command -v pkg-config &>/dev/null; then
    QT_PLUGIN_DIR="$(pkg-config --variable=plugindir Qt6Core 2>/dev/null || true)"
fi
if [ -z "${QT_PLUGIN_DIR:-}" ]; then
    if [ -d /usr/lib64/qt6/plugins ]; then QT_PLUGIN_DIR=/usr/lib64/qt6/plugins
    elif [ -d /usr/lib/qt6/plugins ]; then QT_PLUGIN_DIR=/usr/lib/qt6/plugins
    else QT_PLUGIN_DIR=/usr/lib64/qt6/plugins; fi
fi
SO_PATH="$QT_PLUGIN_DIR/plasma/applets/${APP_ID}.so"
KPACKAGE_PATH="/usr/share/plasma/plasmoids/${APP_ID}"
LOCAL_KPACKAGE="$HOME/.local/share/plasma/plasmoids/${APP_ID}"
LAYOUT_FILE="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

RED="\033[31m"; GREEN="\033[32m"; RESET="\033[0m"
FAILURES=0
pass() { echo -e "  ${GREEN}✓${RESET} $1"; }
fail() { echo -e "  ${RED}✗${RESET} $1"; FAILURES=$((FAILURES + 1)); }

echo ""
echo "System Tray — health check"
echo "=========================="
echo ""

# 1. .so file
if [ -f "$SO_PATH" ]; then
    pass ".so installed at $SO_PATH"
else
    fail ".so NOT FOUND at $SO_PATH — run ./dev.sh"
fi

# 2. No stale user-local plugin (it can shadow the system build).
for local_plugin in \
    "$HOME/.local/lib64/qt6/plugins/plasma/applets/${APP_ID}.so" \
    "$HOME/.local/lib/qt6/plugins/plasma/applets/${APP_ID}.so"; do
    if [ -f "$local_plugin" ]; then
        fail "Stale user-local plugin found at $local_plugin"
    else
        pass "No stale plugin at $local_plugin"
    fi
done

# 3. No KPackage (critical: prevents dark rectangle)
if [ -d "$KPACKAGE_PATH" ] || [ -d "$LOCAL_KPACKAGE" ]; then
    fail "KPackage EXISTS — will cause dark rectangle popup"
    echo "       Remove: sudo rm -rf $KPACKAGE_PATH $LOCAL_KPACKAGE"
else
    pass "No KPackage (dark rectangle prevented)"
fi

# 4. Layout config
if grep -q "plugin=${APP_ID}" "$LAYOUT_FILE" 2>/dev/null; then
    pass "Panel layout includes ${APP_ID}"
else
    fail "${APP_ID} not in panel layout"
fi

if grep -q "plugin=metadata" "$LAYOUT_FILE" 2>/dev/null; then
    fail "Corrupted plugin=metadata entry in layout — will cause loading error"
else
    pass "No corrupted plugin=metadata"
fi

# 5. Symbols
if [ -f "$SO_PATH" ] && ! command -v nm >/dev/null 2>&1; then
    # binutils is not installed by default on Fedora KDE. Without nm both
    # symbols would be reported as undefined, which is a false failure.
    echo "  (skipping the symbol check: 'nm' from binutils is not installed)"
elif [ -f "$SO_PATH" ]; then
    # Capture first, then grep: `nm | grep -q` under pipefail gives false
    # negatives (grep exits early, nm gets SIGPIPE, pipeline reports failure).
    SO_SYMBOLS="$(nm -D "$SO_PATH" 2>/dev/null || true)"
    for sym in SYSTEM_TRAY DBUSMENUQT; do
        if grep -q "_Z.*${sym}v" <<<"$SO_SYMBOLS"; then
            pass "Symbol ${sym} defined"
        else
            fail "Symbol ${sym} UNDEFINED — .so won't load"
        fi
    done
fi

# 6. Recent errors
errors=$(journalctl --user -u plasma-plasmashell.service --since "1 minute ago" --no-pager 2>&1 | grep -c "error.*${APP_ID}\|Cannot load.*${APP_ID}\|undefined symbol.*${APP_ID}" || true)
if [ "$errors" -eq 0 ]; then
    pass "No recent loading errors in plasmashell"
else
    fail "$errors recent loading errors in plasmashell"
fi

echo ""
if [ "$FAILURES" -gt 0 ]; then
    echo "${FAILURES} check(s) failed. To fix: cd system-tray && ./dev.sh"
    exit 1
fi
echo "All checks passed."
