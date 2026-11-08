#!/bin/bash
# Tests the release gate (scripts/package-release.sh) with the real icon theme
# and a stand-in plugin: a good release passes, and each way a release could be
# broken is refused.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$REPO_ROOT/scripts/package-release.sh"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT

eval "$("$REPO_ROOT/scripts/release-contract.sh" | sed 's/^/C_/')"
SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
VERSION="v1.2.3"

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

# A stand-in plugin: a real x86-64 shared object.
mkdir -p "$T/plugin"
echo 'int wm_marker(void) { return 1; }' | gcc -shared -fPIC -x c - -o "$T/plugin/$C_SO_ASSET"
cat > "$T/plugin/$C_INFO_ASSET" <<INFO
name=windowsmodern-systemtray
version=${VERSION#v}
tag=$VERSION
source_commit=$SHA
plugin_id=$C_APP_ID
plugin_asset=$C_SO_ASSET
target_distro=fedora
target_distro_version=45
target_arch=x86_64
min_plasma=6.8.2
INFO

"$PKG" assemble "$T/plugin" "$T/good" >/dev/null
gate() { "$PKG" check "$1" "${2:-$VERSION}" "${3:-$SHA}"; }
fresh() { rm -rf "$T/bad"; cp -r "$T/good" "$T/bad"; }
resum() { (cd "$T/bad" && sha256sum "$C_SO_ASSET" "$C_THEME_ASSET" "$C_INFO_ASSET" "$C_INSTALL_ASSET" "$C_UNINSTALL_ASSET" > "$C_SUMS_ASSET"); }

echo "# a good release"
check "passes the gate" gate "$T/good"
check "has exactly the six contract assets" test "$(find "$T/good" -mindepth 1 | wc -l)" = 6
check "the published installer is the repository's installer" cmp -s "$T/good/$C_INSTALL_ASSET" "$REPO_ROOT/scripts/install.sh"
check "the published uninstaller is the repository's uninstaller" cmp -s "$T/good/$C_UNINSTALL_ASSET" "$REPO_ROOT/scripts/uninstall.sh"
check "the manifest covers the five downloadable assets" test "$(wc -l < "$T/good/$C_SUMS_ASSET")" = 5
check "the manifest does not list itself" bash -c "! grep -q '$C_SUMS_ASSET' '$T/good/$C_SUMS_ASSET'"
check "the icon theme archive holds the real theme" bash -c "tar -tzf '$T/good/$C_THEME_ASSET' | grep -qx '$C_THEME_NAME/index.theme'"
"$PKG" assemble "$T/plugin" "$T/again" >/dev/null
check "assembling twice gives byte-identical archives" cmp -s "$T/good/$C_THEME_ASSET" "$T/again/$C_THEME_ASSET"
refute "assembling into a non-empty directory is refused" "$PKG" assemble "$T/plugin" "$T/good"

echo "# a broken release is refused"
for asset in "$C_SO_ASSET" "$C_THEME_ASSET" "$C_SUMS_ASSET" "$C_INFO_ASSET" "$C_INSTALL_ASSET" "$C_UNINSTALL_ASSET"; do
    fresh; rm "$T/bad/$asset"
    refute "missing $asset" gate "$T/bad"
done
for asset in "$C_SO_ASSET" "$C_THEME_ASSET" "$C_INFO_ASSET"; do
    fresh; : > "$T/bad/$asset"; resum
    refute "empty $asset" gate "$T/bad"
done
fresh; echo stray > "$T/bad/extra.txt"
refute "an extra file nobody asked for" gate "$T/bad"
fresh; echo corrupt >> "$T/bad/$C_SO_ASSET"
refute "plugin changed after the manifest was written" gate "$T/bad"
fresh; echo corrupt >> "$T/bad/$C_THEME_ASSET"
refute "icon theme changed after the manifest was written" gate "$T/bad"
fresh; grep -v "$C_THEME_ASSET" "$T/bad/$C_SUMS_ASSET" > "$T/sums" && cp "$T/sums" "$T/bad/$C_SUMS_ASSET"
refute "manifest lacks an asset" gate "$T/bad"
fresh; cat "$T/bad/$C_SUMS_ASSET" "$T/bad/$C_SUMS_ASSET" > "$T/sums" && cp "$T/sums" "$T/bad/$C_SUMS_ASSET"
refute "manifest lists assets twice" gate "$T/bad"
fresh; echo "$(printf 'a%.0s' {1..64})  ghost.bin" >> "$T/bad/$C_SUMS_ASSET"
refute "manifest lists a file that is not published" gate "$T/bad"

fresh; echo "just text, not a library" > "$T/bad/$C_SO_ASSET"; resum
refute "plugin that is not an ELF shared object" gate "$T/bad"

fresh; sed -i 's/^tag=.*/tag=v9.9.9/' "$T/bad/$C_INFO_ASSET"; resum
refute "build info for another tag" gate "$T/bad"
fresh; sed -i 's/^version=.*/version=9.9.9/' "$T/bad/$C_INFO_ASSET"; resum
refute "build info with another version" gate "$T/bad"
fresh; sed -i 's/^source_commit=.*/source_commit=0000000000000000000000000000000000000000/' "$T/bad/$C_INFO_ASSET"; resum
refute "build info from another commit" gate "$T/bad"
fresh; sed -i 's/^target_distro=.*/target_distro=ubuntu/' "$T/bad/$C_INFO_ASSET"; resum
refute "plugin file name that does not match the target distribution" gate "$T/bad"
fresh; sed -i 's/^min_plasma=.*/min_plasma=six/' "$T/bad/$C_INFO_ASSET"; resum
refute "build info without a valid minimum Plasma version" gate "$T/bad"

fresh; stage="$(mktemp -d)"; mkdir -p "$stage/$C_THEME_NAME"; echo x > "$stage/$C_THEME_NAME/other.txt"
tar -czf "$T/bad/$C_THEME_ASSET" -C "$stage" "$C_THEME_NAME"; rm -rf "$stage"; resum
refute "icon theme without index.theme" gate "$T/bad"
fresh; stage="$(mktemp -d)"; mkdir -p "$stage/$C_THEME_NAME"; echo '[Icon Theme]' > "$stage/$C_THEME_NAME/index.theme"; ln -s /etc "$stage/$C_THEME_NAME/link"
tar -czf "$T/bad/$C_THEME_ASSET" -C "$stage" "$C_THEME_NAME"; rm -rf "$stage"; resum
refute "icon theme with a symlink" gate "$T/bad"

# The installer in the release is what decides which files are expected.
fresh; sed -i "s|^SO_ASSET=.*|SO_ASSET=\"renamed-plugin.so\"|" "$T/bad/$C_INSTALL_ASSET"; resum
refute "installer expects a plugin file the release does not have" gate "$T/bad"
fresh; sed -i "s|^INFO_ASSET=.*|INFO_ASSET=\"info.txt\"|" "$T/bad/$C_INSTALL_ASSET"; resum
refute "installer expects a build info file the release does not have" gate "$T/bad"
fresh; sed -i 's|^THEME_NAME=.*|THEME_NAME="Other"|' "$T/bad/$C_UNINSTALL_ASSET"; resum
refute "uninstaller disagrees with the installer about the theme" gate "$T/bad"
fresh; echo 'if then fi' >> "$T/bad/$C_UNINSTALL_ASSET"; resum
refute "uninstaller with a syntax error" gate "$T/bad"

refute "version without the leading v" gate "$T/good" 1.2.3
refute "prerelease version" gate "$T/good" v1.2.3-rc1
refute "a different version than the build info" gate "$T/good" v1.2.4

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
