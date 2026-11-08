#!/bin/bash
# Tests scripts/release-notes.sh against real git history in a throwaway repo.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTES="$REPO_ROOT/scripts/release-notes.sh"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT

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

cd "$T" && git init -q -b main repo && cd repo || exit 1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
n=0
commit() { n=$((n + 1)); echo "$n" > "file$n"; git add "file$n"; git commit -q -m "$1"; }

commit 'Add the plugin skeleton'
commit 'Fix [brackets] and *stars*'
commit 'Update <b>html</b> & stuff'
git tag v1.0.0
commit 'Use _underscores_ #12 @someone'
commit 'Backslash \ and pipe | here'
# shellcheck disable=SC2016  # backticks are part of the title being tested
commit 'Run `make` before `install`'
sha_one="$(git rev-parse HEAD)"

# ── first release ─────────────────────────────────────────────────────────
"$NOTES" v1.0.0 v1.0.0 > first.md
check "first release exits 0" test -s first.md
check "first release starts with the New Changes heading" test "$(sed -n 1p first.md)" = "# New Changes"
check "first release has the Changes heading" grep -qx '## Changes in this Release' first.md
check "first release lists all 3 commits" test "$(grep -c '^- ' first.md)" = 3
check "first release says it is the first" grep -q 'first release' first.md
check "first release names the commit" grep -q "$(git rev-parse --short=12 v1.0.0)" first.md

# ── later release ─────────────────────────────────────────────────────────
"$NOTES" v1.1.0 "$sha_one" v1.0.0 > second.md
check "second release lists only the 3 new commits" test "$(grep -c '^- ' second.md)" = 3
refute "old commits are not repeated" grep -q 'plugin skeleton' second.md
refute "the commit the previous release was cut at is not repeated" grep -q 'html' second.md
# shellcheck disable=SC2016
check "newest commit comes first" test "$(grep '^- ' second.md | sed -n 1p)" = '- Run \`make\` before \`install\`'
check "oldest included commit comes last" test "$(grep '^- ' second.md | sed -n 3p)" = '- Use \_underscores\_ \#12 \@someone'
check "backslash and pipe are escaped" grep -qxF -- '- Backslash \\ and pipe \| here' second.md
check "mentions the previous release" grep -q 'since v1.0.0' second.md
check "has both headings in order" test "$(grep -n '^#' second.md | cut -d: -f2 | tr '\n' '|')" = '# New Changes|## Changes in this Release|'

"$NOTES" v1.0.0 v1.0.0 > escape.md
check "brackets and asterisks are escaped" grep -qxF -- '- Fix \[brackets\] and \*stars\*' escape.md
check "html and ampersands are escaped" grep -qxF -- '- Update \<b\>html\</b\> \& stuff' escape.md

# ── a merge commit and a branch that was cut after the release ───────────
git checkout -q -b feature v1.0.0
commit 'Feature work'
git checkout -q main
git merge -q --no-ff feature -m 'Merge feature'
sha_two="$(git rev-parse HEAD)"
"$NOTES" v1.2.0 "$sha_two" v1.0.0 > third.md
check "merge commit and the commits it brought are all listed" test "$(grep -c '^- ' third.md)" = 5
check "merge title is listed" grep -qxF -- '- Merge feature' third.md
check "feature commit is listed" grep -qxF -- '- Feature work' third.md

# ── a previous tag that is not an ancestor ────────────────────────────────
git checkout -q -b side v1.0.0
commit 'Only on the side branch'
git tag v0.9.0-side
git checkout -q main
"$NOTES" v1.3.0 "$sha_two" v0.9.0-side > nonancestor.md 2>/dev/null
check "diverged previous tag: lists everything not in it" grep -qxF -- '- Merge feature' nonancestor.md
refute "diverged previous tag: its own commit is not listed" grep -q 'Only on the side branch' nonancestor.md

# ── refusals ──────────────────────────────────────────────────────────────
git tag v1.2.0 "$sha_two"
refute "no commits since the previous tag is an error" "$NOTES" v1.4.0 "$sha_two" v1.2.0
refute "unknown previous tag is an error" "$NOTES" v1.4.0 "$sha_two" v0.0.1
refute "invalid version is an error" "$NOTES" 1.4 "$sha_two" v1.0.0
refute "prerelease version is an error" "$NOTES" v1.4.0-rc1 "$sha_two" v1.0.0
refute "unknown commit is an error" "$NOTES" v1.4.0 deadbeefdeadbeefdeadbeef v1.0.0
refute "missing arguments are an error" "$NOTES" v1.4.0

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
