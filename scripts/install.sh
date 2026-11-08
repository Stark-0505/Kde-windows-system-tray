#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────
#  Windows Modern System Tray: one-command installer
#
#  Downloads the prebuilt plugin and icon theme from the latest GitHub
#  release, verifies them against the release's SHA256SUMS, installs both,
#  activates the icon theme and swaps the stock KDE System Tray for this one
#  on your panel, in place.
#
#  Usage:
#      curl -fsSL https://github.com/Stark-0505/Kde-windows-system-tray/releases/latest/download/install.sh | bash
#
#  Optional environment variables:
#      WM_REPO=owner/repo   repository to download release assets from
#      WM_VERSION=v1.2.3    release to install (default: latest)
#
#  Safe to run again: a repeat run checks the installation and repairs it
#  instead of duplicating anything.
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

# BEGIN RELEASE ASSET CONTRACT
# The one place that names what a release contains. The release workflow, the
# tests and the docs check all read this block through
# scripts/release-contract.sh. Keep it to plain NAME="value" assignments.
DEFAULT_REPO="Stark-0505/Kde-windows-system-tray"
APP_ID="org.kde.windowsmodern.systemtray"
THEME_NAME="WindowsModern-WhiteSurApps"
SO_ASSET="${APP_ID}-fedora-x86_64.so"
THEME_ASSET="${THEME_NAME}.tar.gz"
SUMS_ASSET="SHA256SUMS"
INFO_ASSET="build-info.txt"
# shellcheck disable=SC2034  # read by scripts/release-contract.sh
INSTALL_ASSET="install.sh"
# shellcheck disable=SC2034
UNINSTALL_ASSET="uninstall.sh"
# END RELEASE ASSET CONTRACT

STOCK_PLUGIN="org.kde.plasma.systemtray"
TAG_PATTERN='^v[0-9]+\.[0-9]+\.[0-9]+$'

# WM_ROOT only exists so the tests can point the two system files read below
# at a fixture. Leave it unset.
ROOT_PREFIX="${WM_ROOT:-}"

if [ -t 1 ]; then
    BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
    BOLD=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi
info() { echo "${GREEN}==>${RESET} ${BOLD}$*${RESET}"; }
warn() { echo "${YELLOW}==>${RESET} $*" >&2; }
err()  { echo "${RED}==>${RESET} $*" >&2; }
die()  { err "$*"; exit 1; }

TMP_DIR=""
THEME_STAGE=""
cleanup() {
    [ -z "$THEME_STAGE" ] || rm -rf -- "$THEME_STAGE"
    [ -z "$TMP_DIR" ] || rm -rf -- "$TMP_DIR"
}

# ── Small helpers ────────────────────────────────────────────────────────

# kv_get FILE KEY: value of the first KEY=value line, without any quotes.
kv_get() {
    [ -f "$1" ] || return 0
    awk -F= -v key="$2" '
        $1 == key { value = $0; sub(/^[^=]*=/, "", value); gsub(/^"|"$/, "", value); print value; exit }
    ' "$1"
}

sha_of() {
    sha256sum -- "$1" | awk '{print $1}'
}

version_at_least() {
    local IFS=.
    # shellcheck disable=SC2206
    local have=($1) want=($2)
    (( have[0] > want[0] ||
       (have[0] == want[0] && have[1] > want[1]) ||
       (have[0] == want[0] && have[1] == want[1] && have[2] >= want[2]) ))
}

# manifest_sha ASSET: the SHA-256 SHA256SUMS lists for ASSET. It must be listed
# exactly once, with a well-formed hash, or the release is rejected.
manifest_sha() {
    local sha
    sha="$(awk -v name="$1" '
        NF == 2 && $2 == name { count++; sha = $1 }
        END { if (count == 1 && sha ~ /^[0-9a-f]{64}$/) print sha; else exit 1 }
    ' "$TMP_DIR/$SUMS_ASSET")" || die "${SUMS_ASSET} must list ${1} exactly once. This release is unusable; nothing was changed."
    echo "$sha"
}

# fetch ASSET: download into TMP_DIR. The file only gets its real name once the
# whole download finished, so an interrupted transfer is never mistaken for it.
fetch() {
    curl "${CURL_OPTS[@]}" -o "$TMP_DIR/$1.part" "$RELEASE_BASE/$1" \
        || die "Could not download ${1} from ${RELEASE_BASE}/. ${NO_RELEASE_HINT} Nothing was changed."
    [ -s "$TMP_DIR/$1.part" ] || die "The downloaded ${1} is empty. Nothing was changed."
    mv -f -- "$TMP_DIR/$1.part" "$TMP_DIR/$1"
}

# verify_asset ASSET: check a downloaded asset against SHA256SUMS.
verify_asset() {
    local expected actual
    expected="$(manifest_sha "$1")"
    actual="$(sha_of "$TMP_DIR/$1")"
    [ "$expected" = "$actual" ] || die "Checksum mismatch for ${1}. Aborting; nothing was installed or changed."
}

os_value() {
    kv_get "${ROOT_PREFIX}/etc/os-release" "$1"
}

# ── Release lookup ───────────────────────────────────────────────────────

resolve_tag() {
    local requested="${WM_VERSION:-latest}" url
    if [ "$requested" != "latest" ]; then
        [[ "$requested" =~ $TAG_PATTERN ]] || die "Invalid WM_VERSION: ${requested} (expected latest or something like v1.2.3)."
        TAG="$requested"
        return
    fi
    # Resolve "latest" to a tag once. Every asset then comes from that one
    # release, even if a newer one is published while this script runs.
    url="$(curl "${CURL_OPTS[@]}" -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")" \
        || die "Could not look up the latest release of ${REPO}. ${NO_RELEASE_HINT}"
    TAG="${url##*/}"
    [[ "$TAG" =~ $TAG_PATTERN ]] || die "Could not determine the latest release of ${REPO} (got: ${url}). ${NO_RELEASE_HINT}"
}

# ── Checks ───────────────────────────────────────────────────────────────

check_host() {
    local arch
    arch="$(uname -m)"
    HOST_DISTRO="$(os_value ID)"
    HOST_DISTRO_VERSION="$(os_value VERSION_ID)"
    HOST_ARCH="$arch"

    if [ "$arch" != "x86_64" ] || [ "$HOST_DISTRO" != "fedora" ]; then
        err "The prebuilt release only supports Fedora KDE Plasma 6 on x86_64."
        err "Detected: ${HOST_DISTRO:-unknown} / ${arch}."
        die "Please build from source instead, see README.md."
    fi
    if [ -e "${ROOT_PREFIX}/run/ostree-booted" ]; then
        die "This is an image-based Fedora (Kinoite/Atomic): /usr is read-only, so the plugin can't be installed. Build from source into a toolbox instead, see README.md."
    fi
}

plasma_version() {
    command -v plasmashell >/dev/null 2>&1 || die "plasmashell not found. This needs KDE Plasma 6."
    PLASMA_VERSION="$(plasmashell --version 2>/dev/null | sed -nE 's/.* ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | sed -n '1p')"
    [[ "$PLASMA_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Could not detect the KDE Plasma version."
}

# check_release: the build info (checked against SHA256SUMS first) says what
# this release was built for. Refuse anything that is not this machine.
check_release() {
    local info="$TMP_DIR/$INFO_ASSET" min_plasma
    VERSION="$(kv_get "$info" version)"
    min_plasma="$(kv_get "$info" min_plasma)"

    [ "$(kv_get "$info" tag)" = "$TAG" ]               || die "${INFO_ASSET} does not belong to ${TAG}. Aborting."
    [ "$VERSION" = "${TAG#v}" ]                        || die "${INFO_ASSET} has an unexpected version. Aborting."
    [ "$(kv_get "$info" plugin_id)" = "$APP_ID" ]      || die "This release is not the ${APP_ID} plugin. Aborting."
    [ "$(kv_get "$info" plugin_asset)" = "$SO_ASSET" ] || die "${INFO_ASSET} names a different plugin file. Aborting."
    [[ "$min_plasma" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]    || die "${INFO_ASSET} has no valid minimum Plasma version. Aborting."

    local target_distro target_version target_arch
    target_distro="$(kv_get "$info" target_distro)"
    target_version="$(kv_get "$info" target_distro_version)"
    target_arch="$(kv_get "$info" target_arch)"
    if [ "$target_distro" != "$HOST_DISTRO" ] || [ "$target_version" != "$HOST_DISTRO_VERSION" ] || [ "$target_arch" != "$HOST_ARCH" ]; then
        err "${TAG} was built for ${target_distro} ${target_version} (${target_arch}); this machine is ${HOST_DISTRO} ${HOST_DISTRO_VERSION} (${HOST_ARCH})."
        die "A plugin has to match the Plasma libraries it was built against. Build from source instead, see README.md."
    fi
    if ! version_at_least "$PLASMA_VERSION" "$min_plasma"; then
        die "KDE Plasma ${min_plasma} or newer is required (detected: ${PLASMA_VERSION}). Build from source against your Plasma instead."
    fi
}

# check_plugin FILE: is this an x86-64 shared object whose libraries resolve here?
check_plugin() {
    local header
    header="$(od -An -v -tx1 -N20 -- "$1" | tr -d ' \n')"
    # ELF magic, 64-bit, little endian, shared object (ET_DYN), x86-64.
    if [ "${header:0:8}" != "7f454c46" ] || [ "${header:8:2}" != "02" ] || [ "${header:10:2}" != "01" ] \
       || [ "${header:32:4}" != "0300" ] || [ "${header:36:4}" != "3e00" ]; then
        die "${SO_ASSET} is not an x86-64 shared library. Nothing was installed."
    fi
    if command -v ldd >/dev/null 2>&1; then
        local dependencies
        dependencies="$(ldd "$1" 2>&1 || true)"
        if grep -q "not found" <<<"$dependencies"; then
            err "$dependencies"
            die "The plugin needs libraries this system doesn't have. Build from source instead."
        fi
    fi
}

# stage_theme: validate the archive, then unpack it next to its destination so
# the final move is an atomic rename on the same filesystem.
stage_theme() {
    local archive="$TMP_DIR/$THEME_ASSET" names types
    names="$(tar -tzf "$archive")" || die "Could not read ${THEME_ASSET}. Nothing was installed."
    types="$(tar -tvzf "$archive" | cut -c1)" || die "Could not read ${THEME_ASSET}. Nothing was installed."

    # Everything must live under the theme directory, with no '..' parts, and
    # be a plain file or directory (an icon theme needs no links or devices).
    if grep -Eqv "^${THEME_NAME}(/|\$)" <<<"$names" \
       || grep -Eq '(^|/)\.\.(/|$)' <<<"$names" \
       || grep -Eqv '^[-d]$' <<<"$types"; then
        die "${THEME_ASSET} contains unexpected entries. Nothing was installed."
    fi

    mkdir -p -- "$ICONS_DIR"
    THEME_STAGE="$(mktemp -d "$ICONS_DIR/.${THEME_NAME}.new.XXXXXX")"
    tar -xzf "$archive" -C "$THEME_STAGE" --no-same-owner --no-same-permissions
    grep -q '^\[Icon Theme\]' "$THEME_STAGE/$THEME_NAME/index.theme" 2>/dev/null \
        || die "${THEME_ASSET} has no valid ${THEME_NAME}/index.theme. Nothing was installed."
}

# ── Paths ────────────────────────────────────────────────────────────────

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
    PLUGIN_DST_DIR="$QT_PLUGIN_DIR/plasma/applets"
    PLUGIN_DST="$PLUGIN_DST_DIR/${APP_ID}.so"
    KPACKAGE_DIR="/usr/share/plasma/plasmoids/${APP_ID}"

    DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
    ICONS_DIR="$DATA_HOME/icons"
    ICON_DEST="$ICONS_DIR/${THEME_NAME}"
    STATE_DIR="$DATA_HOME/windowsmodern-systemtray"
    STATE_FILE="$STATE_DIR/state"
    LAYOUT_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
}

# ── Plasma ───────────────────────────────────────────────────────────────

# plasma_eval SCRIPT: run a Plasma Desktop Scripting snippet in the live shell.
# This lets Plasma write its own config instead of us editing the appletsrc
# file while plasmashell has it open. print() output becomes our stdout.
plasma_eval() {
    "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1"
}

plasma_running() {
    [ -n "$QDBUS" ] && "$QDBUS" org.kde.plasmashell >/dev/null 2>&1
}

# wait_for_plasma: after a restart the D-Bus service takes a moment to return.
wait_for_plasma() {
    for _ in $(seq 1 "${WM_PLASMA_WAIT:-30}"); do
        if [ "$(plasma_eval 'print("ready")' 2>/dev/null || true)" = "ready" ]; then
            return 0
        fi
        sleep 1
    done
    return 1
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

swap_panel() {
    local script result
    script=$(cat <<JS
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
    result="$(plasma_eval "$script" 2>&1)" || result="EVAL_FAILED:$result"
    case "$result" in
        ALREADY_PRESENT)
            PANEL_STATUS="already-migrated"
            info "Windows Modern System Tray is already on your panel." ;;
        SWAPPED:*)
            PANEL_STATUS="migrated"
            info "Replaced the stock System Tray with the Windows Modern one (same panel position)." ;;
        ADD_FAILED:*)
            PANEL_STATUS="add-failed"
            warn "Plasma refused to add the Windows Modern tray; the stock System Tray was put back."
            warn "Add \"System Tray (Windows Modern)\" yourself: right-click the panel, then Add or Manage Widgets." ;;
        NOT_FOUND)
            PANEL_STATUS="not-found"
            warn "Could not find the stock System Tray on any panel."
            warn "The plugin and icon theme are installed. Add \"System Tray (Windows Modern)\" to a panel yourself." ;;
        ERROR:PLUGIN_NOT_KNOWN)
            PANEL_STATUS="plugin-not-known" ;;
        *)
            PANEL_STATUS="script-failed"
            warn "The Plasma scripting call did not finish as expected: ${result}"
            warn "The plugin and icon theme are installed. Add \"System Tray (Windows Modern)\" to a panel yourself if it isn't there." ;;
    esac
}

# ── State ────────────────────────────────────────────────────────────────
# KEY=value lines. Never sourced; the uninstaller reads them with kv_get too.

write_state() {
    local tmp
    mkdir -p -- "$STATE_DIR"
    tmp="$(mktemp "$STATE_DIR/.state.XXXXXX")"
    {
        echo "INSTALLED_VERSION=$1"
        echo "INSTALL_DATE=$(date -Iseconds)"
        echo "PREVIOUS_ICON_THEME=${PREVIOUS_ICON_THEME}"
        echo "ICON_THEME_RECORDED=${ICON_THEME_RECORDED}"
        echo "APPLETSRC_BACKUP=${APPLETSRC_BACKUP}"
    } > "$tmp"
    mv -f -- "$tmp" "$STATE_FILE"
}

# remember_user_settings: what the uninstaller needs to put things back. Only
# reads; nothing is written until the plugin install has succeeded.
remember_user_settings() {
    local unset_marker="__wm_unset__" current
    PREVIOUS_ICON_THEME="$(kv_get "$STATE_FILE" PREVIOUS_ICON_THEME)"
    ICON_THEME_RECORDED="$(kv_get "$STATE_FILE" ICON_THEME_RECORDED)"; ICON_THEME_RECORDED="${ICON_THEME_RECORDED:-0}"
    APPLETSRC_BACKUP="$(kv_get "$STATE_FILE" APPLETSRC_BACKUP)"
    OLD_VERSION="$(kv_get "$STATE_FILE" INSTALLED_VERSION)"

    current="$(kreadconfig6 --file kdeglobals --group Icons --key Theme --default "$unset_marker" 2>/dev/null || echo "$unset_marker")"
    # Whatever is active when we take over is what to give back. If ours is
    # already active, keep what an earlier run recorded.
    if [ "$current" != "$THEME_NAME" ]; then
        if [ "$current" = "$unset_marker" ]; then PREVIOUS_ICON_THEME=""; else PREVIOUS_ICON_THEME="$current"; fi
        ICON_THEME_RECORDED=1
    fi
    ACTIVE_ICON_THEME="$current"
}

# backup_layout: a manual-recovery copy of the panel layout. Only the first one
# is kept, since a later copy would already contain our tray. We never write to
# the layout file ourselves.
backup_layout() {
    if [ -n "$APPLETSRC_BACKUP" ] && [ -f "$APPLETSRC_BACKUP" ]; then
        return
    fi
    APPLETSRC_BACKUP=""
    if [ -f "$LAYOUT_FILE" ]; then
        mkdir -p -- "$STATE_DIR"
        if cp -- "$LAYOUT_FILE" "$STATE_DIR/appletsrc.backup" 2>/dev/null; then
            APPLETSRC_BACKUP="$STATE_DIR/appletsrc.backup"
        fi
    fi
}

# ── Install steps ────────────────────────────────────────────────────────

install_plugin() {
    local installed="" target_sha="$EXPECTED_SO_SHA"
    [ ! -f "$PLUGIN_DST" ] || installed="$(sha_of "$PLUGIN_DST")"
    if [ "$installed" = "$target_sha" ] && [ ! -e "$KPACKAGE_DIR" ]; then
        PLUGIN_CHANGED=0
        info "The plugin is already installed and up to date."
        return
    fi

    info "Installing the plugin (this asks for your password)..."
    # The root step copies the file into a root-owned temp file and checks the
    # hash THERE, so nothing running as you can swap it between check and
    # install. The final rename is atomic, so a running plasmashell never sees
    # a half-written library. A KPackage copy of this applet would give the
    # dark-rectangle popup bug, so it is removed.
    local priv
    priv=$(cat <<'EOS'
set -euo pipefail
src="${1:?}"; dst_dir="${2:?}"; dst="${3:?}"; kpkg="${4:?}"; sha="${5:?}"
case "$dst" in "$dst_dir"/*.so) ;; *) echo "Refusing an unexpected destination." >&2; exit 1 ;; esac
case "$kpkg" in /usr/share/plasma/plasmoids/?*) ;; *) echo "Refusing an unexpected package path." >&2; exit 1 ;; esac
staged="$(mktemp)"
tmp="$dst_dir/.$(basename "$dst").new"
trap 'rm -f -- "$staged" "$tmp"' EXIT
cp -- "$src" "$staged"
echo "$sha  $staged" | sha256sum -c --quiet - || { echo "Checksum mismatch, refusing to install." >&2; exit 1; }
install -d -m 0755 "$dst_dir"
install -m 0755 "$staged" "$tmp"
mv -f -- "$tmp" "$dst"
rm -rf -- "$kpkg"
EOS
)
    pkexec bash -c "$priv" _ "$TMP_DIR/$SO_ASSET" "$PLUGIN_DST_DIR" "$PLUGIN_DST" "$KPACKAGE_DIR" "$target_sha" \
        || die "The plugin was not installed (password prompt cancelled, or the checksum check failed). Nothing was changed."
    PLUGIN_CHANGED=1

    # Old local copies would shadow the system plugin.
    rm -rf -- "$DATA_HOME/plasma/plasmoids/${APP_ID}"
    rm -f -- "$HOME/.local/lib64/qt6/plugins/plasma/applets/${APP_ID}.so" \
             "$HOME/.local/lib/qt6/plugins/plasma/applets/${APP_ID}.so"
    info "Plugin installed at ${PLUGIN_DST}."
}

install_theme() {
    info "Installing the icon theme to ${ICON_DEST}..."
    local old=""
    if [ -e "$ICON_DEST" ]; then
        old="$ICONS_DIR/.${THEME_NAME}.old.$$"
        mv -- "$ICON_DEST" "$old"
    fi
    if ! mv -- "$THEME_STAGE/$THEME_NAME" "$ICON_DEST"; then
        [ -z "$old" ] || mv -- "$old" "$ICON_DEST"
        die "Could not put the icon theme in place."
    fi
    [ -z "$old" ] || rm -rf -- "$old"

    if [ "$ACTIVE_ICON_THEME" != "$THEME_NAME" ]; then
        if command -v plasma-changeicons >/dev/null 2>&1; then
            plasma-changeicons "$THEME_NAME" || warn "plasma-changeicons failed. Pick the theme in System Settings, Colors & Themes, Icons."
        else
            kwriteconfig6 --file kdeglobals --group Icons --key Theme "$THEME_NAME" \
                || warn "Could not activate the icon theme. Pick it in System Settings, Colors & Themes, Icons."
        fi
    fi
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
        kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    fi
}

install_panel() {
    PANEL_STATUS="unchanged"
    if ! plasma_running; then
        PANEL_STATUS="plasma-not-running"
        warn "Plasma isn't running here, so the panel was not touched."
        warn "Log in to Plasma and add \"System Tray (Windows Modern)\" to a panel."
        return
    fi
    # Plasma only learns about a new plugin file after a restart.
    local restarted=0
    if [ "$PLUGIN_CHANGED" -eq 1 ]; then
        restart_plasmashell
        restarted=1
    fi
    wait_for_plasma || warn "plasmashell did not answer in time; trying anyway."
    swap_panel
    if [ "$PANEL_STATUS" = "plugin-not-known" ] && [ "$restarted" -eq 0 ]; then
        restart_plasmashell
        wait_for_plasma || true
        swap_panel
    fi
    if [ "$PANEL_STATUS" = "plugin-not-known" ]; then
        warn "Plasma doesn't recognize ${APP_ID} yet, even after a restart."
        warn "Log out and back in, then add \"System Tray (Windows Modern)\" to a panel."
    fi
}

verify_install() {
    info "Verifying the installation..."
    local ok=1 active
    if [ -f "$PLUGIN_DST" ] && [ "$(sha_of "$PLUGIN_DST")" = "$EXPECTED_SO_SHA" ]; then
        echo "  ${GREEN}✓${RESET} Plugin installed at ${PLUGIN_DST}"
    else
        echo "  ${RED}✗${RESET} Plugin missing or different at ${PLUGIN_DST}"; ok=0
    fi
    if [ -f "$ICON_DEST/index.theme" ]; then
        echo "  ${GREEN}✓${RESET} Icon theme installed at ${ICON_DEST}"
    else
        echo "  ${RED}✗${RESET} Icon theme missing at ${ICON_DEST}"; ok=0
    fi
    active="$(kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null || true)"
    if [ "$active" = "$THEME_NAME" ]; then
        echo "  ${GREEN}✓${RESET} Icon theme active"
    else
        echo "  ${YELLOW}!${RESET} Icon theme not confirmed active (found: ${active:-none})"
    fi
    case "$PANEL_STATUS" in
        migrated|already-migrated) echo "  ${GREEN}✓${RESET} Windows Modern System Tray is on your panel" ;;
        *) echo "  ${YELLOW}!${RESET} System Tray not confirmed on a panel, add it yourself if needed" ;;
    esac
    echo ""
    if [ "$ok" -eq 1 ]; then
        info "Done. Windows Modern System Tray ${VERSION} is installed."
    else
        err "The installation finished with problems, see above."
        exit 1
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────
# Everything runs from main(), called on the very last line. If a piped
# download is cut short, bash never reaches that line and nothing executes.

main() {
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    REPO="${WM_REPO:-$DEFAULT_REPO}"
    [[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "Invalid WM_REPO: ${REPO}"
    # HTTPS only (also across redirects), modern TLS, fail on HTTP errors, retry hiccups.
    CURL_OPTS=(--proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL
               --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 900)
    NO_RELEASE_HINT="Is there a release at https://github.com/${REPO}/releases ? To build from source instead: git clone https://github.com/${REPO}.git && cd $(basename "$REPO")/system-tray && ./dev.sh"

    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        die "Don't run this as root. It asks for your password (pkexec) only for the one step that needs it."
    fi
    local cmd
    for cmd in curl sha256sum tar mktemp awk sed od cut kreadconfig6 kwriteconfig6; do
        command -v "$cmd" >/dev/null 2>&1 || die "'${cmd}' is required but not found."
    done
    command -v pkexec >/dev/null 2>&1 || die "pkexec (polkit) not found. It's needed to install into the system Qt plugin directory."
    QDBUS=""
    for cmd in qdbus6 qdbus; do
        if command -v "$cmd" >/dev/null 2>&1; then QDBUS="$cmd"; break; fi
    done
    [ -n "$QDBUS" ] || die "Neither qdbus6 nor qdbus found. Needed to talk to Plasma for the panel swap."

    check_host
    plasma_version
    detect_paths

    TMP_DIR="$(mktemp -d)"
    resolve_tag
    RELEASE_BASE="https://github.com/${REPO}/releases/download/${TAG}"
    info "Downloading ${TAG} from github.com/${REPO}..."

    # Manifest and build info first: they decide whether this release fits at all.
    fetch "$SUMS_ASSET"
    fetch "$INFO_ASSET"
    verify_asset "$INFO_ASSET"
    check_release
    info "Preflight checks passed (Plasma ${PLASMA_VERSION}, ${HOST_DISTRO} ${HOST_DISTRO_VERSION}, ${HOST_ARCH})."

    fetch "$SO_ASSET"
    fetch "$THEME_ASSET"
    verify_asset "$SO_ASSET"
    verify_asset "$THEME_ASSET"
    info "Checksums verified."
    EXPECTED_SO_SHA="$(manifest_sha "$SO_ASSET")"
    check_plugin "$TMP_DIR/$SO_ASSET"
    stage_theme

    # Everything is downloaded, verified and unpacked. From here on the system
    # changes, the one that can be refused (the password prompt) first.
    remember_user_settings
    install_plugin
    backup_layout
    write_state "${OLD_VERSION:-}"
    install_theme
    install_panel
    write_state "$VERSION"
    verify_install
}

main "$@"
