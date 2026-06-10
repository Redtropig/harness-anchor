#!/usr/bin/env bash
# Unit test for scripts/toc-freshness.sh — every status branch, including the
# documented bug-fix paths (anchor-commit existence guard; numeric sanitization;
# TOC self-exclusion: the TOC never counts toward its own staleness).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF="$PLUGIN_ROOT/scripts/toc-freshness.sh"

PASS=0; FAIL=0
expect() { # <label> <expected-prefix> <actual>
  case "$3" in
    "$2"*) echo "  OK   $1 → $3"; PASS=$((PASS+1));;
    *)     echo "  FAIL $1 → got '$3' expected '$2*'"; FAIL=$((FAIL+1));;
  esac
}

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
mkgit() { mkdir -p "$1"; ( cd "$1" || exit 1; git init -q; git config user.email t@e.com; git config user.name t; ); }

# absent — no TOC at all
mkdir -p "$ROOT/absent"
expect "absent" "absent" "$(bash "$TF" "$ROOT/absent")"

# no-anchor — TOC without a generated-at-commit header
mkdir -p "$ROOT/noheader"
printf '# PROJECT TOC\n' > "$ROOT/noheader/PROJECT-TOC.md"
expect "no-anchor(no header)" "no-anchor" "$(bash "$TF" "$ROOT/noheader")"

# no-anchor — placeholder SHA
mkdir -p "$ROOT/placeholder"
printf '<!-- generated-at-commit: PLACEHOLDER_COMMIT_SHA -->\n' > "$ROOT/placeholder/PROJECT-TOC.md"
expect "no-anchor(placeholder)" "no-anchor" "$(bash "$TF" "$ROOT/placeholder")"

# not-git — valid-looking anchor but the dir is not a git repo
mkdir -p "$ROOT/notgit"
printf '<!-- generated-at-commit: abcdef1234 -->\n' > "$ROOT/notgit/PROJECT-TOC.md"
expect "not-git" "not-git" "$(bash "$TF" "$ROOT/notgit")"

# no-anchor — anchor commit does NOT exist in the repo (git cat-file guard)
mkgit "$ROOT/missingcommit"; ( cd "$ROOT/missingcommit" || exit 1; echo x>f; git add -A; git commit -qm init )
printf '<!-- generated-at-commit: %s -->\n' "0000000000000000000000000000000000000000" > "$ROOT/missingcommit/PROJECT-TOC.md"
expect "no-anchor(missing commit)" "no-anchor" "$(bash "$TF" "$ROOT/missingcommit")"

# stale — anchor == HEAD but a real (non-TOC) untracked file dirties the tree.
# The untracked TOC alone must NOT count (self-exclusion) — see the fresh cases.
mkgit "$ROOT/stale"; ( cd "$ROOT/stale" || exit 1; echo x>f; git add -A; git commit -qm init )
h_stale=$(cd "$ROOT/stale" || exit 1; git rev-parse HEAD)
printf '<!-- generated-at-commit: %s -->\n' "$h_stale" > "$ROOT/stale/PROJECT-TOC.md"
echo y > "$ROOT/stale/new-file"
expect "stale(untracked non-TOC file)" "stale" "$(bash "$TF" "$ROOT/stale")"

# fresh — anchor == HEAD and clean tree (gitignore the TOC so it doesn't dirty status)
mkgit "$ROOT/fresh"; ( cd "$ROOT/fresh" || exit 1; echo x>f; printf 'PROJECT-TOC.md\n'>.gitignore; git add -A; git commit -qm init )
h_fresh=$(cd "$ROOT/fresh" || exit 1; git rev-parse HEAD)
printf '<!-- generated-at-commit: %s -->\n' "$h_fresh" > "$ROOT/fresh/PROJECT-TOC.md"
expect "fresh" "fresh" "$(bash "$TF" "$ROOT/fresh")"

# fresh — CANONICAL tracked-TOC workflow (regression pin for the self-exclusion
# fix): regenerate (anchor = HEAD), commit the TOC. Without the exclusion this
# loop could never converge to fresh — the TOC's own commit re-staled it forever.
mkgit "$ROOT/canonical"; ( cd "$ROOT/canonical" || exit 1; echo x>f; git add -A; git commit -qm init )
h_canon=$(cd "$ROOT/canonical" || exit 1; git rev-parse HEAD)
printf '<!-- generated-at-commit: %s -->\n' "$h_canon" > "$ROOT/canonical/PROJECT-TOC.md"
( cd "$ROOT/canonical" || exit 1; git add -A; git commit -qm toc )
expect "fresh(canonical: TOC committed)" "fresh" "$(bash "$TF" "$ROOT/canonical")"

# …and real drift after that canonical fresh state still reports stale.
( cd "$ROOT/canonical" || exit 1; echo y>grown.c; git add -A; git commit -qm grow )
expect "stale(real drift past canonical fresh)" "stale" "$(bash "$TF" "$ROOT/canonical")"

echo ""
echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
