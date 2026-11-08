#!/bin/bash
# Writes the release notes for a new release to stdout.
#
# Usage: scripts/release-notes.sh <version> <commit> [<previous-tag>]
#
#   version         the new tag, for example v1.2.0
#   commit          the exact commit being released
#   previous-tag    tag of the previous published release; leave it out for
#                   the first release
#
# The list is every commit title reachable from <commit> but not from the
# previous release, in git log order (newest first). Titles come straight from
# git; only Markdown characters are escaped.
set -euo pipefail

die() { echo "release-notes: $*" >&2; exit 1; }

[ $# -ge 2 ] && [ $# -le 3 ] || die "usage: $0 <version> <commit> [<previous-tag>]"
version="$1"; commit="$2"; previous="${3:-}"

[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid version: $version"
commit="$(git rev-parse --verify --quiet "${commit}^{commit}")" || die "unknown commit: $2"

if [ -n "$previous" ]; then
    git rev-parse --verify --quiet "refs/tags/${previous}^{commit}" >/dev/null \
        || die "previous release tag ${previous} does not exist in this clone (fetch tags first)"
    range="refs/tags/${previous}..${commit}"
else
    range="$commit"
fi

# Backslash-escape every ASCII punctuation character Markdown could act on.
escape() {
    sed -e 's/\\/\\\\/g' -e 's/[][`*_{}()<>#+!|~&@]/\\&/g'
}

titles="$(git log --format=%s "$range" | tr -d '\r')"
[ -n "$titles" ] || die "no new commits since ${previous:-the beginning}: nothing to release"
count="$(printf '%s\n' "$titles" | wc -l | tr -d ' ')"
short="$(git rev-parse --short=12 "$commit")"

if [ "$count" -eq 1 ]; then noun="commit"; else noun="commits"; fi
if [ -n "$previous" ]; then
    since="${count} new ${noun} since ${previous}"
else
    since="${count} ${noun} in total, as this is the first release"
fi

printf '# New Changes\n\n'
# shellcheck disable=SC2016  # the backticks are Markdown, not a command
printf 'Windows Modern System Tray %s for KDE Plasma 6, built from commit `%s`: %s.\n\n' "$version" "$short" "$since"
printf '## Changes in this Release\n\n'
printf '%s\n' "$titles" | escape | sed 's/^/- /'
