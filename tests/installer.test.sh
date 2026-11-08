#!/bin/bash
# Installer and uninstaller tests, run entirely in a sandbox.
#
# A real Plasma session isn't available to CI, so the programs the scripts talk
# to (curl, pkexec, qdbus6, plasmashell, kreadconfig6, ...) are replaced by
# small stand-ins that emulate a release server and a panel. What is tested is
# the logic of install.sh and uninstall.sh: ordering, verification, repeated
# runs, failures and clean-up. What is NOT tested is real Plasma behaviour.
#
# Nothing outside a temporary directory is touched. The scripts refuse to run
# as root, so when started as root the test re-runs itself as "nobody".
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$(id -u)" -eq 0 ]; then
    exec setpriv --reuid=65534 --regid=65534 --clear-groups "$BASH" "$REPO_ROOT/tests/installer.test.sh" "$@"
fi

INSTALLER="$REPO_ROOT/scripts/install.sh"
UNINSTALLER="$REPO_ROOT/scripts/uninstall.sh"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
BASE_PATH="$PATH"

eval "$("$REPO_ROOT/scripts/release-contract.sh" | sed 's/^/CONTRACT_/')"
SERVER="$T/server"
W="$T/world"
export T W SERVER

pass=0; fail=0
check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then pass=$((pass + 1)); echo "ok   - $desc"
    else fail=$((fail + 1)); echo "FAIL - $desc"; fi
}
refute() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then fail=$((fail + 1)); echo "FAIL - $desc"
    else pass=$((pass + 1)); echo "ok   - $desc"; fi
}
section() { echo; echo "# $*"; }

# ── Stand-ins for the programs the scripts call ──────────────────────────
mkdir -p "$T/bin"
stub() { cat > "$T/bin/$1"; chmod +x "$T/bin/$1"; }

stub curl <<'EOF'
#!/bin/bash
out=""; url=""; fmt=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -w) fmt="$2"; shift 2 ;;
        --proto|--proto-redir|--retry|--retry-delay|--connect-timeout|--max-time) shift 2 ;;
        http*) url="$1"; shift ;;
        *) shift ;;
    esac
done
echo "$url" >> "$W/curl.log"
case "$url" in
    */releases/latest)
        [ -n "${FAKE_LATEST:-}" ] || { echo "curl: (22) The requested URL returned error: 404" >&2; exit 22; }
        [ -z "$fmt" ] || printf '%s' "https://github.com/owner/repo/releases/tag/$FAKE_LATEST"
        ;;
    */releases/download/*/*)
        tag="${url%/*}"; tag="${tag##*/}"; asset="${url##*/}"
        if [ "${FAKE_CURL_FAIL:-}" = "$asset" ]; then echo "curl: (18) transfer closed with bytes remaining" >&2; exit 18; fi
        [ -f "$SERVER/$tag/$asset" ] || { echo "curl: (22) The requested URL returned error: 404" >&2; exit 22; }
        cp "$SERVER/$tag/$asset" "$out"
        ;;
    *) echo "curl stub: unexpected URL $url" >&2; exit 2 ;;
esac
EOF

stub pkexec <<'EOF'
#!/bin/bash
echo "pkexec" >> "$W/pkexec.log"
[ -z "${FAKE_PKEXEC_FAIL:-}" ] || { echo "Error executing command as another user: Request dismissed" >&2; exit 126; }
exec "$@"
EOF

stub plasmashell <<'EOF'
#!/bin/bash
echo "plasmashell ${FAKE_PLASMA:-6.8.2}"
EOF

stub uname <<'EOF'
#!/bin/bash
if [ "${1:-}" = "-m" ]; then echo "${FAKE_ARCH:-x86_64}"; else exec /usr/bin/uname "$@"; fi
EOF

stub pkg-config <<'EOF'
#!/bin/bash
echo "$W/qtplugins"
EOF

stub kbuildsycoca6 <<'EOF'
#!/bin/bash
exit 0
EOF

stub kreadconfig6 <<'EOF'
#!/bin/bash
default=""
while [ $# -gt 0 ]; do case "$1" in --default) default="$2"; shift 2 ;; *) shift ;; esac; done
if [ -f "$W/theme" ]; then cat "$W/theme"; else printf '%s\n' "$default"; fi
EOF

stub kwriteconfig6 <<'EOF'
#!/bin/bash
echo "${@: -1}" > "$W/theme"
EOF

stub plasma-changeicons <<'EOF'
#!/bin/bash
echo "$1" > "$W/theme"
echo "$1" >> "$W/changeicons.log"
EOF

stub systemctl <<'EOF'
#!/bin/bash
case "$*" in
    "--user is-active plasma-plasmashell.service") exit 0 ;;
    "--user restart plasma-plasmashell.service")
        echo restart >> "$W/restarts.log"
        # Plasma only knows the applet if its file is in place when it starts.
        if [ -f "$W/qtplugins/plasma/applets/org.kde.windowsmodern.systemtray.so" ]; then touch "$W/known"; else rm -f "$W/known"; fi ;;
esac
EOF

# A panel with one tray that is either "stock" or "ours".
stub qdbus6 <<'EOF'
#!/bin/bash
if [ $# -eq 1 ]; then [ "${FAKE_PLASMA_RUNNING:-1}" = "1" ]; exit; fi
script="$4"
panel="$(cat "$W/panel")"
case "$script" in
    *'print("ready")'*) echo ready ;;
    *knownWidgetTypes*)
        if [ ! -f "$W/known" ]; then echo "ERROR:PLUGIN_NOT_KNOWN"
        elif [ "$panel" = ours ]; then echo "ALREADY_PRESENT"
        elif [ "$panel" = stock ]; then echo ours > "$W/panel"; echo swap >> "$W/swaps.log"; echo "SWAPPED:1"
        else echo "NOT_FOUND"; fi ;;
    *RESTORE_FAILED*)
        if [ "$panel" = ours ]; then
            if [ -n "${FAKE_RESTORE_FAIL:-}" ]; then echo "RESTORE_FAILED:1"; else echo stock > "$W/panel"; echo "RESTORED:1"; fi
        elif [ "$panel" = stock ]; then echo "ALREADY_STOCK"
        else echo "NOT_FOUND"; fi ;;
esac
EOF

# ── Fixtures ─────────────────────────────────────────────────────────────

# make_release TAG [SEED]: a complete, valid release under $SERVER/TAG.
make_release() {
    local tag="$1" seed="${2:-1}" d="$SERVER/$1" stage
    rm -rf "$d"; mkdir -p "$d"
    printf 'int wm_marker(void) { return %s; }\n' "$seed" | gcc -shared -fPIC -x c - -o "$d/$CONTRACT_SO_ASSET"
    stage="$(mktemp -d)"
    mkdir -p "$stage/$CONTRACT_THEME_NAME/apps"
    printf '[Icon Theme]\nName=Windows Modern (WhiteSurApps)\n' > "$stage/$CONTRACT_THEME_NAME/index.theme"
    echo "$seed" > "$stage/$CONTRACT_THEME_NAME/apps/icon.svg"
    tar -czf "$d/$CONTRACT_THEME_ASSET" -C "$stage" "$CONTRACT_THEME_NAME"
    rm -rf "$stage"
    cat > "$d/$CONTRACT_INFO_ASSET" <<INFO
name=windowsmodern-systemtray
version=${tag#v}
tag=$tag
plugin_id=$CONTRACT_APP_ID
plugin_asset=$CONTRACT_SO_ASSET
target_distro=fedora
target_distro_version=45
target_arch=x86_64
min_plasma=6.8.2
INFO
    cp "$INSTALLER" "$d/$CONTRACT_INSTALL_ASSET"
    cp "$UNINSTALLER" "$d/$CONTRACT_UNINSTALL_ASSET"
    write_sums "$d"
}
write_sums() {
    (cd "$1" && sha256sum "$CONTRACT_SO_ASSET" "$CONTRACT_THEME_ASSET" "$CONTRACT_INFO_ASSET" \
        "$CONTRACT_INSTALL_ASSET" "$CONTRACT_UNINSTALL_ASSET" > "$CONTRACT_SUMS_ASSET")
}

# new_world [THEME]: a fresh machine with the stock tray and a current icon theme.
new_world() {
    rm -rf "$W"
    mkdir -p "$W/home/.config" "$W/tmp" "$W/qtplugins" "$W/root/etc"
    printf 'ID=fedora\nVERSION_ID=45\nVARIANT_ID=kde\n' > "$W/root/etc/os-release"
    echo "layout with the stock tray" > "$W/home/.config/plasma-org.kde.plasma.desktop-appletsrc"
    echo stock > "$W/panel"
    if [ $# -ge 1 ]; then [ -z "$1" ] || echo "$1" > "$W/theme"; else echo "breeze-dark" > "$W/theme"; fi
    unset FAKE_CURL_FAIL FAKE_PKEXEC_FAIL FAKE_ARCH FAKE_PLASMA FAKE_RESTORE_FAIL FAKE_PLASMA_RUNNING WM_VERSION WM_REPO
    export FAKE_LATEST="v1.0.0"
}

run() { # run SCRIPT: execute it in the sandbox, output to $W/out.log, keep the exit code
    local script="$1"
    ( cd "$W" && env HOME="$W/home" TMPDIR="$W/tmp" PATH="$T/bin:$BASE_PATH" WM_ROOT="$W/root" WM_PLASMA_WAIT=2 \
        bash "$script" ) > "$W/out.log" 2>&1
    echo $? > "$W/exit"
}
run_piped() {
    ( cd "$W" && cat "$1" | env HOME="$W/home" TMPDIR="$W/tmp" PATH="$T/bin:$BASE_PATH" WM_ROOT="$W/root" WM_PLASMA_WAIT=2 bash ) > "$W/out.log" 2>&1
    echo $? > "$W/exit"
}

exit_is() { [ "$(cat "$W/exit")" = "$1" ]; }
exit_nonzero() { [ "$(cat "$W/exit")" != "0" ]; }
log_has() { grep -qF -- "$1" "$W/out.log"; }
count_lines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
count_is() { [ "$(count_lines "$1")" = "$2" ]; }
state() { awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$W/home/.local/share/windowsmodern-systemtray/state"; }
plugin() { echo "$W/qtplugins/plasma/applets/$CONTRACT_APP_ID.so"; }
icons() { echo "$W/home/.local/share/icons/$CONTRACT_THEME_NAME"; }
file_sha() { sha256sum "$1" | awk '{print $1}'; }
sha_matches_release() { [ "$(file_sha "$(plugin)")" = "$(file_sha "$SERVER/$1/$CONTRACT_SO_ASSET")" ]; }
nothing_installed() { [ ! -e "$(plugin)" ] && [ ! -e "$(icons)" ] && [ ! -e "$W/home/.local/share/windowsmodern-systemtray" ]; }
has_hidden_entries() { # any dot-file in DIR?
    local entry
    for entry in "$1"/.[!.]*; do [ ! -e "$entry" ] || return 0; done
    return 1
}
no_leftovers() {
    [ -z "$(ls -A "$W/tmp")" ] && ! has_hidden_entries "$W/home/.local/share/icons" \
        && ! has_hidden_entries "$W/qtplugins/plasma/applets"
}
theme_is() { [ "$(cat "$W/theme" 2>/dev/null)" = "$1" ]; }
panel_is() { [ "$(cat "$W/panel")" = "$1" ]; }

make_release v1.0.0 1

# ── Install ──────────────────────────────────────────────────────────────
section "fresh install"
new_world; run "$INSTALLER"
check "exits 0" exit_is 0
check "plugin installed and identical to the release" sha_matches_release v1.0.0
check "icon theme installed" test -f "$(icons)/index.theme"
check "icon theme activated" theme_is "$CONTRACT_THEME_NAME"
check "stock tray swapped for ours" panel_is ours
check "state records the version" test "$(state INSTALLED_VERSION)" = "1.0.0"
check "state records the previous icon theme" test "$(state PREVIOUS_ICON_THEME)" = "breeze-dark"
check "state marks the icon theme as recorded" test "$(state ICON_THEME_RECORDED)" = "1"
check "panel layout backup taken" grep -q "stock tray" "$W/home/.local/share/windowsmodern-systemtray/appletsrc.backup"
check "one password prompt" count_is "$W/pkexec.log" 1
check "no temporary files left behind" no_leftovers
check "all downloads come from the one resolved tag" bash -c "! grep -v '/releases/download/v1.0.0/\\|/releases/latest' '$W/curl.log'"

section "install through a pipe (curl | bash)"
new_world; run_piped "$INSTALLER"
check "works when the script arrives on stdin" exit_is 0
check "plugin installed" sha_matches_release v1.0.0

section "truncated download of the script"
new_world
size="$(wc -c < "$INSTALLER")"
head -c $((size * 6 / 10)) "$INSTALLER" > "$W/cut.sh"
run_piped "$W/cut.sh"
check "a cut-off script changes nothing" nothing_installed
check "and never asks for a password" test ! -e "$W/pkexec.log"

section "reinstall (same version)"
new_world; run "$INSTALLER"; : > "$W/changeicons.log"
cp "$W/home/.local/share/windowsmodern-systemtray/appletsrc.backup" "$W/backup.first"
echo "layout after install" > "$W/home/.config/plasma-org.kde.plasma.desktop-appletsrc"
run "$INSTALLER"
check "exits 0" exit_is 0
check "no second password prompt" count_is "$W/pkexec.log" 1
check "plasmashell is not restarted again" count_is "$W/restarts.log" 1
check "no duplicate tray (one swap in total)" count_is "$W/swaps.log" 1
check "tray is still ours" panel_is ours
check "previous icon theme is not overwritten by ours" test "$(state PREVIOUS_ICON_THEME)" = "breeze-dark"
check "icon theme not re-applied" count_is "$W/changeicons.log" 0
check "the original layout backup is kept" cmp -s "$W/backup.first" "$W/home/.local/share/windowsmodern-systemtray/appletsrc.backup"
check "no temporary files left behind" no_leftovers

section "repair (plugin file damaged)"
new_world; run "$INSTALLER"; echo broken > "$(plugin)"; run "$INSTALLER"
check "plugin restored to the release version" sha_matches_release v1.0.0
check "password asked again for the repair" count_is "$W/pkexec.log" 2

section "upgrade"
make_release v1.1.0 2
new_world; run "$INSTALLER"
export FAKE_LATEST=v1.1.0; run "$INSTALLER"
check "exits 0" exit_is 0
check "plugin is the new release" sha_matches_release v1.1.0
check "state records the new version" test "$(state INSTALLED_VERSION)" = "1.1.0"
check "previous icon theme still the original" test "$(state PREVIOUS_ICON_THEME)" = "breeze-dark"
check "plasmashell restarted to load the new plugin" count_is "$W/restarts.log" 2
check "still one tray" count_is "$W/swaps.log" 1
check "no temporary files left behind" no_leftovers

section "pinned version"
new_world; export FAKE_LATEST=v1.1.0 WM_VERSION=v1.0.0; run "$INSTALLER"
check "WM_VERSION wins over latest" sha_matches_release v1.0.0

# ── Install refusals and failures: each must leave the machine untouched ──
section "failed download"
new_world; export FAKE_CURL_FAIL="$CONTRACT_THEME_ASSET"; run "$INSTALLER"
check "fails" exit_nonzero
check "names the asset" log_has "$CONTRACT_THEME_ASSET"
check "nothing installed" nothing_installed
check "icon theme setting untouched" theme_is breeze-dark
check "tray untouched" panel_is stock
check "no temporary files left behind" no_leftovers

section "missing asset"
make_release v1.0.0 1; rm "$SERVER/v1.0.0/$CONTRACT_SO_ASSET"; new_world; run "$INSTALLER"
check "fails" exit_nonzero
check "nothing installed" nothing_installed
make_release v1.0.0 1

section "corrupted plugin (checksum mismatch)"
echo corrupt >> "$SERVER/v1.0.0/$CONTRACT_SO_ASSET"; new_world; run "$INSTALLER"
check "fails" exit_nonzero
check "says checksum" log_has "Checksum mismatch"
check "nothing installed" nothing_installed
check "tray untouched" panel_is stock
make_release v1.0.0 1

section "corrupted icon theme archive (checksum mismatch)"
new_world; head -c 100 "$SERVER/v1.0.0/$CONTRACT_THEME_ASSET" > "$T/theme.cut"; cp "$T/theme.cut" "$SERVER/v1.0.0/$CONTRACT_THEME_ASSET"; run "$INSTALLER"
check "fails" exit_nonzero
check "says checksum" log_has "Checksum mismatch"
check "nothing installed" nothing_installed
check "tray untouched" panel_is stock
make_release v1.0.0 1

section "tampered build info (checksum mismatch)"
new_world; sed -i 's/^min_plasma=.*/min_plasma=1.0.0/' "$SERVER/v1.0.0/$CONTRACT_INFO_ASSET"; run "$INSTALLER"
check "fails" exit_nonzero
check "says checksum" log_has "Checksum mismatch"
check "nothing installed" nothing_installed
make_release v1.0.0 1

section "manifest lacks an asset"
new_world; grep -v "$CONTRACT_THEME_ASSET" "$SERVER/v1.0.0/$CONTRACT_SUMS_ASSET" > "$T/sums.cut"; cp "$T/sums.cut" "$SERVER/v1.0.0/$CONTRACT_SUMS_ASSET"; run "$INSTALLER"
check "fails (an unlisted asset is never trusted)" exit_nonzero
check "nothing installed" nothing_installed
make_release v1.0.0 1

section "manifest lists an asset twice"
new_world; { cat "$SERVER/v1.0.0/$CONTRACT_SUMS_ASSET"; grep "$CONTRACT_SO_ASSET" "$SERVER/v1.0.0/$CONTRACT_SUMS_ASSET"; } > "$T/sums.dup"
cp "$T/sums.dup" "$SERVER/v1.0.0/$CONTRACT_SUMS_ASSET"; run "$INSTALLER"
check "fails" exit_nonzero
check "nothing installed" nothing_installed
make_release v1.0.0 1

section "build info for another system"
new_world; sed -i 's/^target_distro_version=.*/target_distro_version=44/' "$SERVER/v1.0.0/$CONTRACT_INFO_ASSET"; write_sums "$SERVER/v1.0.0"; run "$INSTALLER"
check "refused" exit_nonzero
check "explains the mismatch" log_has "built for fedora 44"
check "nothing installed" nothing_installed
make_release v1.0.0 1
new_world; export FAKE_ARCH=aarch64; run "$INSTALLER"
check "wrong CPU architecture refused" exit_nonzero
check "nothing installed" nothing_installed
new_world; export FAKE_PLASMA=6.7.0; run "$INSTALLER"
check "too old Plasma refused" exit_nonzero
check "nothing installed" nothing_installed
new_world; mkdir -p "$W/root/run"; touch "$W/root/run/ostree-booted"; run "$INSTALLER"
check "image-based Fedora refused" exit_nonzero
check "nothing installed" nothing_installed

section "build info that does not belong to the tag"
new_world; sed -i 's/^tag=.*/tag=v9.9.9/' "$SERVER/v1.0.0/$CONTRACT_INFO_ASSET"; write_sums "$SERVER/v1.0.0"; run "$INSTALLER"
check "refused" exit_nonzero
check "nothing installed" nothing_installed
make_release v1.0.0 1

section "plugin that is not an x86-64 shared library"
new_world; echo "just text" > "$SERVER/v1.0.0/$CONTRACT_SO_ASSET"; write_sums "$SERVER/v1.0.0"; run "$INSTALLER"
check "refused although its checksum matches" exit_nonzero
check "nothing installed" nothing_installed
make_release v1.0.0 1

section "icon theme archive with a symlink"
new_world; stage="$(mktemp -d)"; mkdir -p "$stage/$CONTRACT_THEME_NAME"
printf '[Icon Theme]\n' > "$stage/$CONTRACT_THEME_NAME/index.theme"; ln -s /etc "$stage/$CONTRACT_THEME_NAME/escape"
tar -czf "$SERVER/v1.0.0/$CONTRACT_THEME_ASSET" -C "$stage" "$CONTRACT_THEME_NAME"; rm -rf "$stage"; write_sums "$SERVER/v1.0.0"; run "$INSTALLER"
check "refused" exit_nonzero
check "nothing installed" nothing_installed
check "no temporary files left behind" no_leftovers
make_release v1.0.0 1

section "icon theme archive with a path outside the theme"
new_world; stage="$(mktemp -d)"; mkdir -p "$stage/other"; echo x > "$stage/other/file"
tar -czf "$SERVER/v1.0.0/$CONTRACT_THEME_ASSET" -C "$stage" other; rm -rf "$stage"; write_sums "$SERVER/v1.0.0"; run "$INSTALLER"
check "refused" exit_nonzero
check "nothing installed" nothing_installed
make_release v1.0.0 1

section "password prompt dismissed"
new_world; export FAKE_PKEXEC_FAIL=1; run "$INSTALLER"
check "fails" exit_nonzero
check "nothing installed, no state written" nothing_installed
check "icon theme setting untouched" theme_is breeze-dark
check "tray untouched" panel_is stock
check "no temporary files left behind" no_leftovers

section "bad settings"
new_world; export WM_VERSION="latest;rm"; run "$INSTALLER"
check "invalid WM_VERSION rejected" exit_nonzero
new_world; export WM_REPO="not a repo"; run "$INSTALLER"
check "invalid WM_REPO rejected" exit_nonzero
new_world; export FAKE_LATEST=""; run "$INSTALLER"
check "no release published: clear error" exit_nonzero
check "mentions building from source" log_has "build from source"

section "Plasma not running"
new_world; export FAKE_PLASMA_RUNNING=0; run "$INSTALLER"
check "plugin and theme still installed" sha_matches_release v1.0.0
check "tray left alone with a warning" panel_is stock
check "exits 0" exit_is 0

section "no icon theme configured before install"
new_world ""; run "$INSTALLER"
check "recorded as 'was the default'" test "$(state ICON_THEME_RECORDED)" = "1" -a -z "$(state PREVIOUS_ICON_THEME)"

# ── Uninstall ────────────────────────────────────────────────────────────
section "uninstall"
new_world; run "$INSTALLER"; run "$UNINSTALLER"
check "exits 0" exit_is 0
check "plugin removed" test ! -e "$(plugin)"
check "icon theme removed" test ! -e "$(icons)"
check "previous icon theme restored" theme_is breeze-dark
check "stock tray back" panel_is stock
check "install record removed" test ! -e "$W/home/.local/share/windowsmodern-systemtray"
check "plasmashell restarted" count_is "$W/restarts.log" 2

section "uninstall twice"
: > "$W/pkexec.log"; : > "$W/restarts.log"
run "$UNINSTALLER"
check "exits 0" exit_is 0
check "says it is not installed" log_has "not installed"
check "asks for no password" count_is "$W/pkexec.log" 0
check "does not restart plasmashell" count_is "$W/restarts.log" 0
check "settings stay as they were" theme_is breeze-dark

section "uninstall when nothing was ever installed"
new_world; run "$UNINSTALLER"
check "exits 0 and does nothing" exit_is 0
check "asks for no password" test ! -e "$W/pkexec.log"

section "uninstall keeps a theme you chose afterwards"
new_world; run "$INSTALLER"; echo "breeze" > "$W/theme"; run "$UNINSTALLER"
check "your choice stays" theme_is breeze
check "plugin removed" test ! -e "$(plugin)"

section "uninstall when the default icon theme was in use"
new_world ""; run "$INSTALLER"; run "$UNINSTALLER"
check "falls back to Breeze instead of a deleted theme" theme_is breeze

section "uninstall when Plasma refuses to restore the tray"
new_world; run "$INSTALLER"; export FAKE_RESTORE_FAIL=1; run "$UNINSTALLER"
check "fails" exit_nonzero
check "plugin stays so the panel does not break" test -f "$(plugin)"
check "install record kept for a retry" test -f "$W/home/.local/share/windowsmodern-systemtray/state"
unset FAKE_RESTORE_FAIL; run "$UNINSTALLER"
check "a later run finishes the job" exit_is 0
check "plugin removed" test ! -e "$(plugin)"

section "uninstall with the password prompt dismissed"
new_world; run "$INSTALLER"; export FAKE_PKEXEC_FAIL=1; run "$UNINSTALLER"
check "fails" exit_nonzero
check "does not claim success" bash -c "! grep -q 'has been uninstalled' '$W/out.log'"
check "install record kept" test -f "$W/home/.local/share/windowsmodern-systemtray/state"
unset FAKE_PKEXEC_FAIL; run "$UNINSTALLER"
check "retry finishes" exit_is 0
check "plugin removed" test ! -e "$(plugin)"

section "uninstall leaves unrelated files alone"
new_world; run "$INSTALLER"; mkdir -p "$W/home/.local/share/icons/SomeOtherTheme"; echo keep > "$W/home/.local/share/icons/SomeOtherTheme/index.theme"
echo keep > "$W/qtplugins/plasma/applets/org.example.other.so"; run "$UNINSTALLER"
check "other icon themes kept" test -f "$W/home/.local/share/icons/SomeOtherTheme/index.theme"
check "other plasma plugins kept" test -f "$W/qtplugins/plasma/applets/org.example.other.so"

# ── The release pipeline's own output ────────────────────────────────────
# The fixtures above are hand-made. This one is what package-release.sh builds
# from the real icon theme and the real scripts, so the installer is proven to
# accept exactly what the workflow publishes.
section "a release assembled by package-release.sh"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'
head_sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"
mkdir -p "$T/plugin15"
printf 'int wm_marker(void) { return 15; }\n' | gcc -shared -fPIC -x c - -o "$T/plugin15/$CONTRACT_SO_ASSET"
cat > "$T/plugin15/$CONTRACT_INFO_ASSET" <<INFO
name=windowsmodern-systemtray
version=1.5.0
tag=v1.5.0
source_commit=$head_sha
plugin_id=$CONTRACT_APP_ID
plugin_asset=$CONTRACT_SO_ASSET
target_distro=fedora
target_distro_version=45
target_arch=x86_64
min_plasma=6.8.2
INFO
"$REPO_ROOT/scripts/package-release.sh" assemble "$T/plugin15" "$SERVER/v1.5.0" >/dev/null
check "the release gate accepts it" "$REPO_ROOT/scripts/package-release.sh" check "$SERVER/v1.5.0" v1.5.0 "$head_sha"
new_world; export FAKE_LATEST=v1.5.0; run "$SERVER/v1.5.0/install.sh"
check "the published install.sh installs it" exit_is 0
check "plugin installed" sha_matches_release v1.5.0
check "the real icon theme is in place" test "$(find "$(icons)" -type f | wc -l)" -gt 1000
check "the real theme's index.theme is intact" grep -q '^\[Icon Theme\]' "$(icons)/index.theme"
check "stock tray swapped" panel_is ours
run "$SERVER/v1.5.0/uninstall.sh"
check "the published uninstall.sh removes it" exit_is 0
check "nothing left" nothing_installed
check "previous icon theme back" theme_is breeze-dark

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
