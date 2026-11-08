#!/bin/bash
# Assembles the release assets and checks them. Used by the release workflow;
# the tests run the same code.
#
#   package-release.sh assemble <plugin-dir> <out-dir>
#       <plugin-dir> holds the built plugin and build-info.txt. <out-dir> gets
#       every asset the installer downloads, plus install.sh and uninstall.sh
#       and the SHA256SUMS that covers them.
#
#   package-release.sh check <out-dir> <version> <commit>
#       The release gate. Fails unless <out-dir> is exactly what the published
#       installer expects, and every checksum, archive and field is in order.
#
# File names come from the contract at the top of install.sh. For "check" they
# are read from the install.sh inside <out-dir>, i.e. from the installer users
# will actually download.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(dirname "$here")"

die() { echo "package-release: $*" >&2; exit 1; }

load_contract() { # load_contract INSTALLER
    # shellcheck source=/dev/null
    source <("$here/release-contract.sh" "$1")
}

kv() { # kv FILE KEY
    awk -F= -v key="$2" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$1"
}

assemble() {
    [ $# -eq 2 ] || die "usage: $0 assemble <plugin-dir> <out-dir>"
    local plugin_dir="$1" out="$2" epoch
    load_contract "$repo/scripts/install.sh"
    [ -s "$plugin_dir/$SO_ASSET" ]   || die "no built plugin at $plugin_dir/$SO_ASSET"
    [ -s "$plugin_dir/$INFO_ASSET" ] || die "no build info at $plugin_dir/$INFO_ASSET"
    [ -d "$repo/windows-icon/$THEME_NAME" ] || die "icon theme directory is missing"
    if [ -e "$out" ] && [ -n "$(find "$out" -mindepth 1 -maxdepth 1 -print -quit)" ]; then die "$out already exists and is not empty"; fi
    mkdir -p "$out"

    cp "$plugin_dir/$SO_ASSET" "$plugin_dir/$INFO_ASSET" "$out/"
    cp "$repo/scripts/install.sh"   "$out/$INSTALL_ASSET"
    cp "$repo/scripts/uninstall.sh" "$out/$UNINSTALL_ASSET"

    # Same input, same archive: sorted entries, fixed owner, the commit's date as
    # the modification time, no name or time in the gzip header.
    epoch="$(git -C "$repo" log -1 --format=%ct)"
    tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner \
        -cf - -C "$repo/windows-icon" "$THEME_NAME" | gzip -n -9 > "$out/$THEME_ASSET"

    # Everything except the manifest itself.
    (cd "$out" && sha256sum "$SO_ASSET" "$THEME_ASSET" "$INFO_ASSET" "$INSTALL_ASSET" "$UNINSTALL_ASSET" > "$SUMS_ASSET")
    echo "Assembled $(find "$out" -mindepth 1 -maxdepth 1 | wc -l) assets in $out"
}

check() {
    [ $# -eq 3 ] || die "usage: $0 check <out-dir> <version> <commit>"
    local out="$1" version="$2" commit="$3" name expected actual listed header types names info
    [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid version: $version"
    [ -f "$out/install.sh" ] || die "$out has no install.sh"
    load_contract "$out/install.sh"
    [ "$INSTALL_ASSET" = "install.sh" ] && [ "$UNINSTALL_ASSET" = "uninstall.sh" ] \
        || die "the installer names its own scripts differently from the files the workflow publishes"
    info="$out/$INFO_ASSET"

    # 1. Exactly the files the installer knows about: none missing, none extra.
    expected="$(printf '%s\n' "$SO_ASSET" "$THEME_ASSET" "$SUMS_ASSET" "$INFO_ASSET" "$INSTALL_ASSET" "$UNINSTALL_ASSET" | sort)"
    actual="$(find "$out" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)"
    [ "$expected" = "$actual" ] || die "asset list differs from the installer's contract.
expected:
$expected
found:
$actual"
    for name in $expected; do
        [ -f "$out/$name" ] || die "$name is not a regular file"
        [ -s "$out/$name" ] || die "$name is empty"
    done

    # 2. The manifest covers every downloadable asset once, and every hash is right.
    listed="$(awk 'NF == 2 { print $2 }' "$out/$SUMS_ASSET" | sort)"
    [ "$listed" = "$(printf '%s\n' "$SO_ASSET" "$THEME_ASSET" "$INFO_ASSET" "$INSTALL_ASSET" "$UNINSTALL_ASSET" | sort)" ] \
        || die "$SUMS_ASSET does not list exactly the downloadable assets: $listed"
    [ "$(wc -l < "$out/$SUMS_ASSET")" -eq 5 ] || die "$SUMS_ASSET has unexpected extra lines"
    (cd "$out" && sha256sum --check --strict --quiet "$SUMS_ASSET") || die "a checksum does not match"

    # 3. The plugin is an x86-64 shared library.
    header="$(od -An -v -tx1 -N20 -- "$out/$SO_ASSET" | tr -d ' \n')"
    if [ "${header:0:8}" != "7f454c46" ] || [ "${header:8:2}" != "02" ] || [ "${header:10:2}" != "01" ] \
       || [ "${header:32:4}" != "0300" ] || [ "${header:36:4}" != "3e00" ]; then
        die "$SO_ASSET is not an x86-64 shared library"
    fi

    # 4. The icon theme archive is intact and holds only what the installer accepts.
    gzip -t "$out/$THEME_ASSET" || die "$THEME_ASSET is not a valid gzip file"
    names="$(tar -tzf "$out/$THEME_ASSET")" || die "$THEME_ASSET is not a valid tar archive"
    types="$(tar -tvzf "$out/$THEME_ASSET" | cut -c1)"
    grep -qx "$THEME_NAME/index.theme" <<<"$names" || die "$THEME_ASSET has no $THEME_NAME/index.theme"
    if grep -Eqv "^${THEME_NAME}(/|\$)" <<<"$names" || grep -Eq '(^|/)\.\.(/|$)' <<<"$names" || grep -Eqv '^[-d]$' <<<"$types"; then
        die "$THEME_ASSET contains entries the installer would refuse"
    fi

    # 5. Both scripts parse.
    bash -n "$out/$INSTALL_ASSET"   || die "$INSTALL_ASSET has a syntax error"
    bash -n "$out/$UNINSTALL_ASSET" || die "$UNINSTALL_ASSET has a syntax error"
    [ "$(sed -n 's/^APP_ID="\(.*\)"$/\1/p;s/^THEME_NAME="\(.*\)"$/\1/p' "$out/$UNINSTALL_ASSET" | tr '\n' ' ')" = "$APP_ID $THEME_NAME " ] \
        || die "$UNINSTALL_ASSET disagrees with the installer about the plugin or theme name"

    # 6. The build info says what this release is.
    [ "$(kv "$info" tag)" = "$version" ]                 || die "build info tag is not $version"
    [ "$(kv "$info" version)" = "${version#v}" ]         || die "build info version is not ${version#v}"
    [ "$(kv "$info" source_commit)" = "$commit" ]        || die "build info was not made from commit $commit"
    [ "$(kv "$info" plugin_id)" = "$APP_ID" ]            || die "build info plugin_id is not $APP_ID"
    [ "$(kv "$info" plugin_asset)" = "$SO_ASSET" ]       || die "build info plugin_asset is not $SO_ASSET"
    [ "$(kv "$info" target_arch)" = "x86_64" ]           || die "build info target_arch must be x86_64"
    [[ "$(kv "$info" target_distro_version)" =~ ^[0-9]+$ ]] || die "build info has no numeric target_distro_version"
    [[ "$(kv "$info" min_plasma)" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "build info has no valid min_plasma"
    [ "$SO_ASSET" = "${APP_ID}-$(kv "$info" target_distro)-$(kv "$info" target_arch).so" ] \
        || die "the plugin file name does not match the distribution and architecture it was built for"

    echo "Release assets for $version ($commit) are consistent with the installer."
}

case "${1:-}" in
    assemble) shift; assemble "$@" ;;
    check)    shift; check "$@" ;;
    *)        die "usage: $0 assemble|check ..." ;;
esac
