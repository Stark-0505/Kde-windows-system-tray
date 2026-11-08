#!/bin/bash
# Checks that the pieces of the release system agree with each other:
# installer, uninstaller, workflow, docs, and the versions in the source.
#
#   tests/release_contract.test.sh           the three declared versions must match each other
#   tests/release_contract.test.sh v1.2.0    ...and the release being cut
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1
WANT_VERSION="${1:-}"

eval "$(scripts/release-contract.sh | sed 's/^/C_/')"
WORKFLOW=.github/workflows/release.yml
DOCS=(README.md system-tray/BUILD.md)

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
in_docs() { grep -qF -- "$1" "${DOCS[@]}"; }

echo "# installer and uninstaller"
check "the installer ends by calling main (a cut-off download runs nothing)" test "$(grep -v '^[[:space:]]*$' scripts/install.sh | tail -n 1)" = 'main "$@"'
check "the uninstaller ends by calling main" test "$(grep -v '^[[:space:]]*$' scripts/uninstall.sh | tail -n 1)" = 'main "$@"'
check "the uninstaller uses the installer's plugin id" grep -qx "APP_ID=\"$C_APP_ID\"" scripts/uninstall.sh
check "the uninstaller uses the installer's theme name" grep -qx "THEME_NAME=\"$C_THEME_NAME\"" scripts/uninstall.sh
check "the plugin file name carries the target it is built for" test "$C_SO_ASSET" = "${C_APP_ID}-fedora-x86_64.so"
check "the installer's own file names are the published script names" test "$C_INSTALL_ASSET $C_UNINSTALL_ASSET" = "install.sh uninstall.sh"

echo "# workflow"
check "there is exactly one workflow" test "$(find .github/workflows -type f | wc -l)" = 1
check "it is the release workflow" test -f "$WORKFLOW"
check "it can be started by hand" grep -q '^  workflow_dispatch:' "$WORKFLOW"
for trigger in push pull_request pull_request_target schedule release create workflow_run; do
    refute "it does not run on $trigger" grep -Eq "^  ${trigger}:" "$WORKFLOW"
done
check "it takes a version input" grep -q '^      version:' "$WORKFLOW"
check "it starts with no permissions" grep -qx 'permissions: {}' "$WORKFLOW"
check "one job at a time can write" test "$(grep -c 'contents: write' "$WORKFLOW")" = 1
check "only the publish job can write" bash -c "awk '/^  [a-z]+:\$/ {job=\$1} /contents: write/ {print job}' '$WORKFLOW' | grep -qx 'publish:'"
check "releases never cancel each other" bash -c "grep -A2 '^concurrency:' '$WORKFLOW' | grep -q 'cancel-in-progress: false'"
check "every action is pinned to a full commit" bash -c "! grep -E '^\s+(- )?uses:' '$WORKFLOW' | grep -Ev 'uses: [^@ ]+@[0-9a-f]{40}( |\$)'"
check "it uses at least one action (so the check above means something)" grep -Eq 'uses: [^@ ]+@[0-9a-f]{40}' "$WORKFLOW"
check "it takes asset names from the installer's contract" grep -q 'scripts/release-contract.sh' "$WORKFLOW"
check "it runs the release gate" grep -q 'package-release.sh check' "$WORKFLOW"
check "it publishes as a draft first" grep -q -- '--draft' "$WORKFLOW"
# shellcheck disable=SC2016  # matching the literal text "$SHA"
check "it tags the built commit, not main" grep -q -- '--target "\$SHA"' "$WORKFLOW"
check "it builds on Fedora 45" grep -q 'image: fedora:45' "$WORKFLOW"
check "the version never appears inside a script body" bash -c "! grep -n 'inputs.version' '$WORKFLOW' | grep -v 'VERSION: \${{ inputs.version }}'"
for name in "$C_SO_ASSET" "$C_THEME_ASSET" "$C_SUMS_ASSET" "$C_INFO_ASSET" "$C_APP_ID" "$C_THEME_NAME" "$C_DEFAULT_REPO"; do
    refute "the workflow does not repeat '$name'" grep -qF -- "$name" "$WORKFLOW"
done

echo "# versions"
cmake_version="$(sed -nE 's/^project\([^ ]+ VERSION ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' system-tray/CMakeLists.txt)"
meta_version="$(python3 -c 'import json; print(json.load(open("system-tray/metadata.json"))["KPlugin"]["Version"])')"
spec_version="$(sed -nE 's/^Version:[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+)$/\1/p' spec/*.spec)"
check "CMakeLists.txt declares a version" test -n "$cmake_version"
check "CMakeLists.txt, metadata.json and the spec say the same version" test "$cmake_version" = "$meta_version" -a "$cmake_version" = "$spec_version"
if [ -n "$WANT_VERSION" ]; then
    check "the source says ${WANT_VERSION#v}, the version being released" test "$cmake_version" = "${WANT_VERSION#v}"
fi
cmake_plasma="$(sed -nE 's/^set\(PLASMA_MIN_VERSION "([0-9.]+)"\)/\1/p' system-tray/CMakeLists.txt)"
meta_plasma="$(python3 -c 'import json; print(json.load(open("system-tray/metadata.json"))["X-Plasma-API-Minimum-Version"])')"
check "CMake and metadata.json need the same minimum Plasma" test -n "$cmake_plasma" -a "$cmake_plasma" = "$meta_plasma"
check "the README states that minimum" grep -qF "Plasma $cmake_plasma or newer" README.md

echo "# docs"
install_url="https://github.com/$C_DEFAULT_REPO/releases/latest/download/$C_INSTALL_ASSET"
uninstall_url="https://github.com/$C_DEFAULT_REPO/releases/latest/download/$C_UNINSTALL_ASSET"
check "the README has the one-command install URL" grep -qF "curl -fsSL $install_url | bash" README.md
check "the README has the one-command uninstall URL" grep -qF "curl -fsSL $uninstall_url | bash" README.md
for name in "$C_SO_ASSET" "$C_THEME_ASSET" "$C_INSTALL_ASSET" "$C_UNINSTALL_ASSET" "$C_SUMS_ASSET" "$C_INFO_ASSET"; do
    check "the README lists the release asset $name" grep -qF "\`$name\`" README.md
done
check "the README says how to start a release" grep -q 'gh workflow run release.yml' README.md
check "the README names the supported binary target" grep -q 'Fedora 45' README.md
check "BUILD.md names the supported binary target" grep -q 'Fedora 45, x86_64' system-tray/BUILD.md
refute "no doc mentions the removed shellcheck workflow" grep -q 'shellcheck.yml' "${DOCS[@]}"
refute "no doc says releases start from a pushed tag" grep -Eqi 'git push origin v|push a tag|pushing a tag|tag push' "${DOCS[@]}"
check "the docs use the one repository" bash -c "! grep -hoE 'github.com/[A-Za-z0-9_.-]+/Kde-windows-system-tray' README.md system-tray/BUILD.md scripts/*.sh system-tray/dev.sh spec/*.spec | grep -viE '^github.com/$C_DEFAULT_REPO\$'"
check "the docs mention the build info file" in_docs "$C_INFO_ASSET"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
