#!/bin/bash
# Prints the release asset contract as NAME=value lines.
#
# The contract lives in one place: the marked block at the top of install.sh.
# The release workflow, the tests and the docs check read it from here, so the
# names the installer downloads and the names the workflow publishes cannot
# drift apart.
#
# Usage: scripts/release-contract.sh [path/to/install.sh]
set -euo pipefail

installer="${1:-$(dirname "${BASH_SOURCE[0]}")/install.sh}"
block="$(sed -n '/^# BEGIN RELEASE ASSET CONTRACT$/,/^# END RELEASE ASSET CONTRACT$/p' "$installer")"
[ -n "$block" ] || { echo "No release asset contract found in $installer" >&2; exit 1; }

names=(DEFAULT_REPO APP_ID THEME_NAME SO_ASSET THEME_ASSET SUMS_ASSET INFO_ASSET INSTALL_ASSET UNINSTALL_ASSET)

# Evaluate the block in a clean shell. It only holds plain assignments.
# shellcheck disable=SC2016  # the script below is meant to stay unexpanded
env -i bash -c '
    set -euo pipefail
    eval "$1"
    shift
    for name in "$@"; do
        value="${!name:?missing in the release asset contract: $name}"
        [[ "$value" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "Unexpected characters in $name: $value" >&2; exit 1; }
        printf "%s=%s\n" "$name" "$value"
    done
' _ "$block" "${names[@]}"
