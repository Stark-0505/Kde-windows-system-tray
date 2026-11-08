#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────
#  Windows Modern System Tray: uninstaller
#
#  Puts the stock KDE System Tray back on your panel, restores the icon theme
#  you used before, and removes the plugin and icon theme this project
#  installed. Nothing else is touched.
#
#  Usage:
#      curl -fsSL https://github.com/Stark-0505/Kde-windows-system-tray/releases/latest/download/uninstall.sh | bash
#
#  Safe to run more than once. If a step fails, the install record is kept so
#  you can run it again.
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

# Must match scripts/install.sh (tests/release_contract.test.sh checks this).
APP_ID="org.kde.windowsmodern.systemtray"
THEME_NAME="WindowsModern-WhiteSurApps"
STOCK_PLUGIN="org.kde.plasma.systemtray"

if [ -t 1 ]; then
    BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
    BOLD=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi
info() { echo "${GREEN}==>${RESET} ${BOLD}$*${RESET}"; }
warn() { echo "${YELLOW}==>${RESET} $*" >&2; }
err()  { echo "${RED}==>${RESET} $*" >&2; }
die()  { err "$*"; exit 1; }

# kv_get FILE KEY: value of the first KEY=value line, without any quotes.
kv_get() {
    [ -f "$1" ] || return 0
    awk -F= -v key="$2" '
        $1 == key { value = $0; sub(/^[^=]*=/, "", value); gsub(/^"|"$/, "", value); print value; exit }
    ' "$1"
}

detect_paths() {
    QT_PLUGIN_DIR=""
    if command -v pkg-config >/dev/null 2>&1; then
        QT_PLUGIN_DIR="$(pkg-config --variable=plugindir Qt6Core 2>/dev/null || true)"
    fi
    if [ -z "$QT_PLUGIN_DIR" ]; then
        if [ -d /usr/lib64/qt6/plugins ]; then QT_PLUGIN_DIR=/usr/lib64/qt6/plugins
        elif [ -d /usr/lib/qt6/plugins ]; then QT_PLUGIN_DIR=/usr/lib/qt6/plugins
        else QT_PLUGIN_DIR=/usr/lib64/qt6/plugins
        fi
    fi
    [[ "$QT_PLUGIN_DIR" == /* ]] || die "Unexpected Qt plugin directory: ${QT_PLUGIN_DIR}"
    PLUGIN_DST="$QT_PLUGIN_DIR/plasma/applets/${APP_ID}.so"
    KPACKAGE_DIR="/usr/share/plasma/plasmoids/${APP_ID}"

    DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
    ICON_DEST="$DATA_HOME/icons/${THEME_NAME}"
    STATE_DIR="$DATA_HOME/windowsmodern-systemtray"
    STATE_FILE="$STATE_DIR/state"
    USER_COPIES=("$DATA_HOME/plasma/plasmoids/${APP_ID}"
                 "$HOME/.local/lib64/qt6/plugins/plasma/applets/${APP_ID}.so"
                 "$HOME/.local/lib/qt6/plugins/plasma/applets/${APP_ID}.so")
}

# plasma_eval SCRIPT: run a Plasma Desktop Scripting snippet in the live shell,
# so Plasma writes its own config. print() output becomes our stdout.
plasma_eval() {
    "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1"
}

plasma_running() {
    [ -n "$QDBUS" ] && "$QDBUS" org.kde.plasmashell >/dev/null 2>&1
}

restart_plasmashell() {
    info "Restarting plasmashell..."
    if systemctl --user is-active plasma-plasmashell.service >/dev/null 2>&1; then
        systemctl --user restart plasma-plasmashell.service
    else
        kquitapp6 plasmashell 2>/dev/null || true
        sleep 1
        nohup plasmashell --replace >/dev/null 2>&1 </dev/null &
        disown
    fi
}

# restore_panel: stock System Tray back where ours is, same position.
# Sets PANEL_STATUS. Returns 1 only when Plasma refused and ours is still there.
restore_panel() {
    local script result
    script=$(cat <<JS
var stockId = "${STOCK_PLUGIN}";
var newId = "${APP_ID}";
var allPanels = panels();
var restored = 0;
var failed = 0;
for (var i = 0; i < allPanels.length; i++) {
    var panel = allPanels[i];
    var ours = panel.widgets(newId);
    for (var j = 0; j < ours.length; j++) {
        var oldIndex = ours[j].index;
        ours[j].remove();
        var w = panel.addWidget(stockId);
        if (w) {
            w.index = oldIndex;
            restored++;
        } else {
            // Don't leave the panel without a tray: put ours back.
            var r = panel.addWidget(newId);
            if (r) { r.index = oldIndex; }
            failed++;
        }
    }
}
if (failed > 0) {
    print("RESTORE_FAILED:" + failed);
} else if (restored > 0) {
    print("RESTORED:" + restored);
} else {
    var stockPresent = false;
    for (var i = 0; i < allPanels.length; i++) {
        if (allPanels[i].widgets(stockId).length > 0) { stockPresent = true; }
    }
    print(stockPresent ? "ALREADY_STOCK" : "NOT_FOUND");
}
JS
)
    result="$(plasma_eval "$script" 2>&1)" || result="EVAL_FAILED:$result"
    case "$result" in
        RESTORED:*)
            PANEL_STATUS="restored"
            info "Restored the stock System Tray on your panel (same position)." ;;
        RESTORE_FAILED:*)
            PANEL_STATUS="restore-failed"
            err "Plasma refused to add the stock System Tray; the Windows Modern one was left in place."
            err "Add the stock System Tray yourself (right-click the panel, Add or Manage Widgets), then run this again."
            return 1 ;;
        ALREADY_STOCK)
            PANEL_STATUS="already-stock"
            info "The stock System Tray is already on your panel." ;;
        NOT_FOUND)
            PANEL_STATUS="not-found"
            warn "Neither System Tray variant was found on any panel; the layout was left alone." ;;
        *)
            PANEL_STATUS="script-failed"
            warn "The Plasma scripting call did not finish as expected: ${result}"
            warn "Add the stock System Tray to your panel yourself if it is missing." ;;
    esac
}

# restore_icon_theme: only when ours is still the active one. If you picked
# another theme since, that choice stays.
restore_icon_theme() {
    local current previous recorded
    previous="$(kv_get "$STATE_FILE" PREVIOUS_ICON_THEME)"
    recorded="$(kv_get "$STATE_FILE" ICON_THEME_RECORDED)"
    current="$(kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null || true)"

    if [ "$current" != "$THEME_NAME" ]; then
        [ -z "$current" ] || info "Icon theme is ${current}, not ours; leaving it as it is."
        return 0
    fi
    # Either the theme from before the install, or (nothing recorded, or the
    # default was in use) Breeze, so the theme being deleted isn't left active.
    if [ "$recorded" != "1" ] || [ -z "$previous" ]; then
        previous="breeze"
    fi
    if command -v plasma-changeicons >/dev/null 2>&1; then
        plasma-changeicons "$previous" || { warn "Could not restore the icon theme. Pick ${previous} in System Settings, Colors & Themes, Icons."; return 0; }
    else
        kwriteconfig6 --file kdeglobals --group Icons --key Theme "$previous" \
            || { warn "Could not restore the icon theme. Pick ${previous} in System Settings, Colors & Themes, Icons."; return 0; }
    fi
    info "Restored the icon theme: ${previous}."
}

remove_plugin() {
    local path
    if [ -e "$PLUGIN_DST" ] || [ -e "$KPACKAGE_DIR" ]; then
        info "Removing the plugin (this asks for your password)..."
        # Fixed commands with the paths as arguments, so nothing root runs
        # lives in a place you can write to.
        # shellcheck disable=SC2016  # the script is meant to be expanded by root's bash, not ours
        if ! pkexec bash -c 'set -euo pipefail
            case "${1:?}" in */plasma/applets/*.so) ;; *) exit 1 ;; esac
            case "${2:?}" in /usr/share/plasma/plasmoids/?*) ;; *) exit 1 ;; esac
            rm -f -- "$1"; rm -rf -- "$2"' _ "$PLUGIN_DST" "$KPACKAGE_DIR"; then
            err "The plugin was not removed (password prompt cancelled?). Run this again to finish."
            return 1
        fi
        REMOVED_SOMETHING=1
    fi
    for path in "${USER_COPIES[@]}"; do
        if [ -e "$path" ]; then rm -rf -- "$path"; REMOVED_SOMETHING=1; fi
    done
}

# anything_installed: any trace of this project on disk or in the settings.
anything_installed() {
    local path
    for path in "$PLUGIN_DST" "$KPACKAGE_DIR" "$ICON_DEST" "${USER_COPIES[@]}"; do
        [ ! -e "$path" ] || return 0
    done
    [ "$(kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null || true)" = "$THEME_NAME" ]
}

main() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        die "Don't run this as root. It asks for your password (pkexec) only for the step that needs it."
    fi
    command -v pkexec >/dev/null 2>&1 || die "pkexec (polkit) not found. It's needed to remove the system-installed plugin."
    command -v kreadconfig6 >/dev/null 2>&1 || die "'kreadconfig6' is required but not found."

    QDBUS=""
    local cmd
    for cmd in qdbus6 qdbus; do
        if command -v "$cmd" >/dev/null 2>&1; then QDBUS="$cmd"; break; fi
    done

    detect_paths
    PANEL_STATUS="unchanged"
    REMOVED_SOMETHING=0
    local failed=0 had_state=0 backup
    [ ! -f "$STATE_FILE" ] || had_state=1

    # Panel first, while the plugin still exists: a panel that points at a
    # missing plugin shows an error widget.
    if plasma_running; then
        restore_panel || die "Nothing was removed."
    else
        PANEL_STATUS="plasma-not-running"
        warn "Plasma isn't running here, so the panel can't be restored automatically."
    fi

    # Nothing of ours anywhere: say so, and don't prompt or restart anything.
    if [ "$had_state" -eq 0 ] && [ "$PANEL_STATUS" != "restored" ] && ! anything_installed; then
        info "Windows Modern System Tray is not installed. Nothing to do."
        return 0
    fi

    if [ "$had_state" -eq 1 ]; then
        backup="$(kv_get "$STATE_FILE" APPLETSRC_BACKUP)"
        if [ -n "$backup" ] && [ -f "$backup" ]; then
            info "A panel layout backup from before the install is at: ${backup}"
        fi
    else
        warn "No install record found. Removing what is there; your previous icon theme can't be looked up."
    fi

    restore_icon_theme
    remove_plugin || failed=1
    if [ -d "$ICON_DEST" ]; then
        rm -rf -- "$ICON_DEST"
        REMOVED_SOMETHING=1
        info "Removed the icon theme at ${ICON_DEST}."
    fi

    if [ "$REMOVED_SOMETHING" -eq 1 ] || [ "$PANEL_STATUS" = "restored" ]; then
        if plasma_running; then restart_plasmashell; fi
    fi

    info "Verifying the removal..."
    if [ -e "$PLUGIN_DST" ]; then
        echo "  ${RED}✗${RESET} Plugin still present at ${PLUGIN_DST}"; failed=1
    else
        echo "  ${GREEN}✓${RESET} Plugin removed"
    fi
    if [ -e "$ICON_DEST" ]; then
        echo "  ${RED}✗${RESET} Icon theme still present at ${ICON_DEST}"; failed=1
    else
        echo "  ${GREEN}✓${RESET} Icon theme removed"
    fi
    case "$PANEL_STATUS" in
        restored|already-stock) echo "  ${GREEN}✓${RESET} Stock System Tray is on your panel" ;;
        *) echo "  ${YELLOW}!${RESET} Panel not confirmed, add the stock System Tray yourself if needed" ;;
    esac

    echo ""
    if [ "$failed" -ne 0 ]; then
        err "The uninstall did not finish. The install record was kept; run this again."
        exit 1
    fi
    rm -rf -- "$STATE_DIR"
    info "Done. Windows Modern System Tray has been uninstalled."
}

# Called last, so a truncated download never runs a half-read script.
main "$@"
