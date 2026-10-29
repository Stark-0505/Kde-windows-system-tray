#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────
#  Windows Modern System Tray — one-click installer
#
#  Downloads the prebuilt plugin + icon theme from the latest GitHub
#  Release, verifies them against SHA256SUMS, installs both, activates
#  the icon theme, and swaps the stock KDE System Tray for the Windows
#  Modern one on your panel — in place, no manual panel editing.
#
#  Usage:
#      curl -fsSL https://github.com/KaizennGIT/Kde-windows-system-tray/releases/latest/download/install.sh | bash
#
#  Optional environment variables:
#      WM_REPO=owner/repo   GitHub repo to download release assets from
#      WM_VERSION=v1.2.3    Release tag to install (default: latest)
#
#  Safe to run more than once: repeat runs verify/repair the existing
#  installation instead of duplicating anything.
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="${WM_REPO:-KaizennGIT/Kde-windows-system-tray}"
WM_VERSION="${WM_VERSION:-latest}"
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { echo "Invalid WM_REPO: $REPO" >&2; exit 1; }
[[ "$WM_VERSION" =~ ^[A-Za-z0-9._-]+$ ]]            || { echo "Invalid WM_VERSION: $WM_VERSION" >&2; exit 1; }
# HTTPS only (also for redirects), modern TLS, and fail on HTTP errors.
CURL_OPTS=(--proto '=https' --tlsv1.2 -fsSL)
NO_RELEASE_HINT="Does https://github.com/${REPO}/releases have a release? To build from source instead: git clone https://github.com/${REPO}.git && cd Kde-windows-system-tray/system-tray && ./dev.sh"
if [ "$WM_VERSION" = "latest" ]; then
    RELEASE_BASE="https://github.com/${REPO}/releases/latest/download"
else
    RELEASE_BASE="https://github.com/${REPO}/releases/download/${WM_VERSION}"
fi
APP_ID="org.kde.windowsmodern.systemtray"
THEME_NAME="WindowsModern-WhiteSurApps"
STOCK_PLUGIN="org.kde.plasma.systemtray"

SO_ASSET="${APP_ID}-fedora-x86_64.so"
THEME_ASSET="${THEME_NAME}.tar.gz"
SUMS_ASSET="SHA256SUMS"

STATE_DIR="$HOME/.local/share/windowsmodern-systemtray"
STATE_FILE="$STATE_DIR/state"
LAYOUT_FILE="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
ICON_DEST="$HOME/.local/share/icons/${THEME_NAME}"

BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"
info()  { echo -e "${GREEN}==>${RESET} ${BOLD}$*${RESET}"; }
warn()  { echo -e "${YELLOW}==>${RESET} $*"; }
err()   { echo -e "${RED}==>${RESET} $*"; }
die()   { err "$*"; exit 1; }

TMP_DIR=""
cleanup() { [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# ── Preflight ───────────────────────────────────────────────────────────
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    die "Don't run this as root. It will ask for your password (via pkexec) only for the one step that needs it."
fi

for cmd in curl sha256sum tar mktemp; do
    command -v "$cmd" &>/dev/null || die "'$cmd' is required but not found. Install it and try again."
done
command -v pkexec &>/dev/null || die "pkexec not found (part of polkit). It's required to install the plugin into the system Qt plugin directory."

QDBUS=""
for _c in qdbus6 qdbus; do
    if command -v "$_c" &>/dev/null; then QDBUS="$_c"; break; fi
done
[ -n "$QDBUS" ] || die "Neither qdbus6 nor qdbus found. Required to talk to Plasma Shell (org.kde.PlasmaShell.evaluateScript) for the panel swap."

# Runs a Plasma Desktop Scripting snippet against the live Plasma Shell via
# org.kde.PlasmaShell.evaluateScript, instead of editing
# plasma-org.kde.plasma.desktop-appletsrc directly while plasmashell has it
# open. print() calls inside the script become this function's stdout.
plasma_eval() {
    "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1"
}

if ! command -v plasmashell &>/dev/null; then
    die "plasmashell not found. This installer requires KDE Plasma 6."
fi
PLASMA_VERSION="$(plasmashell --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
PLASMA_MAJOR="${PLASMA_VERSION%%.*}"
if [ "${PLASMA_MAJOR:-0}" -ne 6 ]; then
    die "KDE Plasma 6 is required (detected: ${PLASMA_VERSION:-unknown}). See README.md for other versions."
fi

ARCH="$(uname -m)"
DISTRO_ID="unknown"; DISTRO_LIKE=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"
fi
if [ "$ARCH" != "x86_64" ] || { [ "$DISTRO_ID" != "fedora" ] && [[ "$DISTRO_LIKE" != *fedora* ]]; }; then
    err "The prebuilt release currently only supports Fedora KDE Plasma 6 on x86_64."
    err "Detected: ${DISTRO_ID} / ${ARCH}."
    err "Please use the manual (source build) installation instead — see README.md."
    exit 1
fi

info "Preflight checks passed (Plasma ${PLASMA_VERSION}, ${DISTRO_ID}, ${ARCH})."

# ── Detect install paths (same logic as system-tray/dev.sh) ──────────────
if command -v pkg-config &>/dev/null; then
    QT_PLUGIN_DIR="$(pkg-config --variable=plugindir Qt6Core 2>/dev/null || true)"
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
PLUGIN_DST_DIR="$QT_PLUGIN_DIR/plasma/applets"
PLUGIN_DST="$PLUGIN_DST_DIR/${APP_ID}.so"
KPACKAGE_DIR="/usr/share/plasma/plasmoids/${APP_ID}"

mkdir -p "$STATE_DIR"

# ── Download + verify ──────────────────────────────────────────────────
TMP_DIR="$(mktemp -d)"
info "Downloading release artifacts from github.com/${REPO} (${WM_VERSION})..."
curl "${CURL_OPTS[@]}" "$RELEASE_BASE/$SUMS_ASSET"  -o "$TMP_DIR/$SUMS_ASSET"  || die "Failed to download $SUMS_ASSET. ${NO_RELEASE_HINT}"
curl "${CURL_OPTS[@]}" "$RELEASE_BASE/$SO_ASSET"    -o "$TMP_DIR/$SO_ASSET"    || die "Failed to download $SO_ASSET. ${NO_RELEASE_HINT}"
curl "${CURL_OPTS[@]}" "$RELEASE_BASE/$THEME_ASSET" -o "$TMP_DIR/$THEME_ASSET" || die "Failed to download $THEME_ASSET. ${NO_RELEASE_HINT}"

info "Verifying checksums..."
(
    cd "$TMP_DIR"
    grep -E "  (${SO_ASSET}|${THEME_ASSET})\$" "$SUMS_ASSET" > subset.sums \
        || die "SHA256SUMS does not list the expected assets."
    sha256sum -c subset.sums || die "Checksum verification FAILED. Aborting — nothing was installed or changed."
)
info "Checksums verified."

# ── Icon theme: install + remember previous theme ─────────────────────
CURRENT_THEME="$(kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null || true)"
if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
fi
if [ -z "${PREVIOUS_ICON_THEME:-}" ] && [ -n "$CURRENT_THEME" ] && [ "$CURRENT_THEME" != "$THEME_NAME" ]; then
    PREVIOUS_ICON_THEME="$CURRENT_THEME"
fi

info "Installing icon theme to ${ICON_DEST}..."
# Validate the archive BEFORE touching the existing theme: every entry must live
# under the theme directory, with no '..' path components.
THEME_LISTING="$(tar -tzf "$TMP_DIR/$THEME_ASSET")" || die "Could not read ${THEME_ASSET}."
if grep -Eqv "^(\./)?${THEME_NAME}(/|\$)" <<<"$THEME_LISTING" \
   || grep -Eq '(^|/)\.\.(/|$)' <<<"$THEME_LISTING"; then
    die "${THEME_ASSET} contains unexpected paths. Aborting — nothing was installed."
fi
STAGE_DIR="$TMP_DIR/icons-stage"
mkdir -p "$STAGE_DIR"
tar -xzf "$TMP_DIR/$THEME_ASSET" -C "$STAGE_DIR" --no-same-owner
[ -f "$STAGE_DIR/$THEME_NAME/index.theme" ] || die "${THEME_ASSET} has no ${THEME_NAME}/index.theme. Aborting."
mkdir -p "$HOME/.local/share/icons"
rm -rf "$ICON_DEST"
mv "$STAGE_DIR/$THEME_NAME" "$ICON_DEST"

if command -v plasma-changeicons &>/dev/null; then
    plasma-changeicons "$THEME_NAME" || warn "plasma-changeicons failed; theme installed but may need manual activation."
else
    kwriteconfig6 --file kdeglobals --group Icons --key Theme "$THEME_NAME" 2>/dev/null \
        || warn "Could not activate the icon theme automatically. Set it via System Settings → Colors & Themes → Icons."
fi
if command -v kbuildsycoca6 &>/dev/null; then
    kbuildsycoca6 --noincremental &>/dev/null || true
fi
info "Icon theme installed and activated."

# ── Plugin: install compiled .so, remove conflicting KPackage ─────────
info "Installing plugin (requires your password)..."
EXPECTED_SO_SHA="$(awk -v f="$SO_ASSET" '($2==f || $2=="*"f) {print $1; exit}' "$TMP_DIR/$SUMS_ASSET")"
[[ "$EXPECTED_SO_SHA" =~ ^[0-9a-f]{64}$ ]] || die "Could not read a valid SHA-256 for ${SO_ASSET} from ${SUMS_ASSET}."

# The root step copies the .so into a root-owned temp file and re-verifies the
# hash THERE, so nothing running as your user can swap the file between the
# check and the install (the download dir is writable by you).
PRIV_SCRIPT=$(cat <<'EOS'
set -euo pipefail
src="${1:?}"; dst_dir="${2:?}"; dst="${3:?}"; kpkg="${4:?}"; sha="${5:?}"
staged="$(mktemp)"
trap 'rm -f -- "$staged"' EXIT
cp -- "$src" "$staged"
echo "$sha  $staged" | sha256sum -c --quiet - || { echo "Checksum mismatch — refusing to install." >&2; exit 1; }
install -d -m 0755 "$dst_dir"
install -m 0755 "$staged" "$dst"
rm -rf -- "$kpkg"
EOS
)
pkexec bash -c "$PRIV_SCRIPT" _ "$TMP_DIR/$SO_ASSET" "$PLUGIN_DST_DIR" "$PLUGIN_DST" "$KPACKAGE_DIR" "$EXPECTED_SO_SHA" \
    || die "Plugin installation failed (pkexec or checksum)."

# Prune stale local copies that would otherwise shadow the system plugin
rm -rf "$HOME/.local/share/plasma/plasmoids/${APP_ID}" 2>/dev/null || true
rm -f "$HOME/.local/lib64/qt6/plugins/plasma/applets/${APP_ID}.so" 2>/dev/null || true
rm -f "$HOME/.local/lib/qt6/plugins/plasma/applets/${APP_ID}.so" 2>/dev/null || true
info "Plugin installed at ${PLUGIN_DST}."

# ── Restart plasmashell ────────────────────────────────────────────────
# Done here, before the panel swap: Plasma Shell has to already know about
# org.kde.windowsmodern.systemtray (just installed above) for the
# addWidget() call in the panel script below to work.
info "Restarting plasmashell..."
if systemctl --user is-active plasma-plasmashell.service &>/dev/null; then
    systemctl --user restart plasma-plasmashell.service
else
    kquitapp6 plasmashell 2>/dev/null || killall plasmashell 2>/dev/null || true
    sleep 1
    nohup plasmashell --replace >/dev/null 2>&1 &
    disown
fi
sleep 3

# Snapshot the panel layout file purely as a manual-recovery reference
# before making any change. This script never writes to the file itself —
# Plasma Shell persists its own config independently once the live swap
# below runs.
if [ -f "$LAYOUT_FILE" ] && [ -z "${APPLETSRC_BACKUP:-}" ]; then
    APPLETSRC_BACKUP="$STATE_DIR/appletsrc.backup"
    cp "$LAYOUT_FILE" "$APPLETSRC_BACKUP" 2>/dev/null || APPLETSRC_BACKUP=""
fi

# ── Panel: replace stock System Tray in place, live, via Plasma's own ──
#    scripting API (org.kde.PlasmaShell.evaluateScript). This talks to the
#    running Plasma Shell and lets it write its own config — it does NOT
#    edit plasma-org.kde.plasma.desktop-appletsrc directly, which is unsafe
#    while plasmashell has it open. Widget.index preserves panel position.
PANEL_STATUS="unchanged"
PANEL_SCRIPT=$(cat <<JS
var stockId = "${STOCK_PLUGIN}";
var newId = "${APP_ID}";
if (!knownWidgetTypes.includes(newId)) {
    print("ERROR:PLUGIN_NOT_KNOWN");
} else {
    var allPanels = panels();
    var already = false;
    for (var i = 0; i < allPanels.length; i++) {
        if (allPanels[i].widgets(newId).length > 0) { already = true; }
    }
    if (already) {
        print("ALREADY_PRESENT");
    } else {
        var swapped = 0;
        var failed = 0;
        for (var i = 0; i < allPanels.length; i++) {
            var panel = allPanels[i];
            var trays = panel.widgets(stockId);
            for (var j = 0; j < trays.length; j++) {
                var oldIndex = trays[j].index;
                trays[j].remove();
                var w = panel.addWidget(newId);
                if (w) {
                    w.index = oldIndex;
                    swapped++;
                } else {
                    // Don't leave the panel without a tray: put the stock one back.
                    var r = panel.addWidget(stockId);
                    if (r) { r.index = oldIndex; }
                    failed++;
                }
            }
        }
        if (failed > 0) {
            print("ADD_FAILED:" + failed);
        } else {
            print(swapped > 0 ? "SWAPPED:" + swapped : "NOT_FOUND");
        }
    }
}
JS
)
PANEL_RESULT="$(plasma_eval "$PANEL_SCRIPT" 2>&1)" || PANEL_RESULT="EVAL_FAILED:$PANEL_RESULT"

case "$PANEL_RESULT" in
    ALREADY_PRESENT)
        PANEL_STATUS="already-migrated"
        info "Windows Modern System Tray is already on your panel." ;;
    SWAPPED:*)
        PANEL_STATUS="migrated"
        info "Replaced the stock System Tray with the Windows Modern one (same panel position)." ;;
    ADD_FAILED:*)
        PANEL_STATUS="add-failed"
        warn "Plasma refused to add the Windows Modern tray; the stock System Tray was put back."
        warn "Add \"System Tray (Windows Modern)\" manually: right-click panel → Add or Manage Widgets…" ;;
    NOT_FOUND)
        PANEL_STATUS="not-found"
        warn "Could not find the stock System Tray on any panel."
        warn "The plugin and icon theme are installed — add \"System Tray (Windows Modern)\""
        warn "to a panel manually: right-click panel → Add or Manage Widgets…" ;;
    ERROR:PLUGIN_NOT_KNOWN)
        PANEL_STATUS="plugin-not-known"
        warn "Plasma Shell doesn't recognize ${APP_ID} yet, even after restarting."
        warn "Log out and back in, then add \"System Tray (Windows Modern)\" to a panel manually." ;;
    *)
        PANEL_STATUS="script-failed"
        warn "Plasma scripting call did not complete as expected: ${PANEL_RESULT}"
        warn "The plugin and icon theme are installed — add \"System Tray (Windows Modern)\""
        warn "to a panel manually if it isn't there: right-click panel → Add or Manage Widgets…" ;;
esac

# ── Save state ──────────────────────────────────────────────────────────
{
    echo "INSTALLED_VERSION=1.0.0"
    echo "INSTALL_DATE=$(date -Iseconds)"
    echo "PREVIOUS_ICON_THEME=${PREVIOUS_ICON_THEME:-}"
    echo "APPLETSRC_BACKUP=${APPLETSRC_BACKUP:-}"
} > "$STATE_FILE"

# ── Verify ──────────────────────────────────────────────────────────────
info "Verifying installation..."
OK=1
if [ -f "$PLUGIN_DST" ]; then
    echo -e "  ${GREEN}✓${RESET} Plugin installed at ${PLUGIN_DST}"
else
    echo -e "  ${RED}✗${RESET} Plugin missing at ${PLUGIN_DST}"; OK=0
fi
if [ -d "$ICON_DEST" ] && [ -f "$ICON_DEST/index.theme" ]; then
    echo -e "  ${GREEN}✓${RESET} Icon theme installed at ${ICON_DEST}"
else
    echo -e "  ${RED}✗${RESET} Icon theme missing at ${ICON_DEST}"; OK=0
fi
ACTIVE_THEME="$(kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null || true)"
if [ "$ACTIVE_THEME" = "$THEME_NAME" ]; then
    echo -e "  ${GREEN}✓${RESET} Icon theme active"
else
    echo -e "  ${YELLOW}!${RESET} Icon theme not confirmed active (found: ${ACTIVE_THEME:-none})"
fi
case "$PANEL_STATUS" in
    migrated|already-migrated)
        echo -e "  ${GREEN}✓${RESET} Windows Modern System Tray is on your panel" ;;
    *)
        echo -e "  ${YELLOW}!${RESET} System Tray not confirmed on panel — add it manually if needed" ;;
esac

echo ""
if [ "$OK" -eq 1 ]; then
    info "Done. Windows Modern System Tray is installed."
else
    err "Installation finished with problems — see above."
    exit 1
fi
