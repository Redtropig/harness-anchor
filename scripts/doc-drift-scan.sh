#!/usr/bin/env bash
# doc-drift-scan.sh — Find documentation that should have changed with the code
# and did not.
#
# Usage:
#   bash doc-drift-scan.sh [--base <ref>] [--target <dir>]
#     --base    git ref to diff against (default: merge-base with the default
#               branch if resolvable, else HEAD~1, else empty tree)
#     --target  project root (default: cwd)
#
# Output (stdout, one candidate per line, TAB-separated):
#   <md-file>:<line><TAB><symbol><TAB><the claim text>
# No candidates → no output. Exit code: ALWAYS 0.
#
# WHY (v0.16.0): drift-analyst bounded its scan to CHANGED files, and its
# doc-drift heuristic only matched docs referencing RENAMED/REMOVED symbols. A
# README sentence asserting behaviour about a symbol that still exists — whose
# behaviour the diff just changed — fell through both. Real case: "Cancellation
# is safe to call at any time" survived a change that made cancel() reject
# terminal-state jobs, and /gc reported clean.
#
# RESIDUAL BLIND SPOT: a stale claim that names no symbol ("the pool is fast")
# is NOT detectable this way. Documented in agents/drift-analyst.md and frozen
# as a negative assertion in tests/unit/doc-drift-scan.sh — a silent pass here
# must never be read as "the docs were checked".

set -uo pipefail

BASE=""; TARGET=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --base)   BASE="${2:-}"; shift 2;;
        --target) TARGET="${2:-}"; shift 2;;
        *) shift;;
    esac
done
[ -n "$TARGET" ] || TARGET="$(pwd)"
cd "$TARGET" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

if [ -z "$BASE" ]; then
    for cand in main master; do
        if git rev-parse --verify -q "$cand" >/dev/null 2>&1; then
            BASE=$(git merge-base HEAD "$cand" 2>/dev/null || true)
            [ -n "$BASE" ] && break
        fi
    done
fi
[ -n "$BASE" ] || BASE=$(git rev-parse --verify -q HEAD~1 2>/dev/null || true)
[ -n "$BASE" ] || exit 0

# ---- 1. changed symbol names --------------------------------------------------
# Two sources, unioned:
#   (a) identifiers on changed lines that look like a declaration/definition
#   (b) the nearest ENCLOSING symbol when only a body line changed — this is the
#       MiniSched case (cancel()'s signature never moved) and is why (a) alone
#       is not enough. `git diff -U0` hunk headers carry that context after the
#       `@@ ... @@` marker, which is exactly git's "enclosing function" hint.
SYMS=$(
  {
    git diff -U0 "$BASE"..HEAD -- '*.c' '*.cc' '*.cpp' '*.cxx' '*.h' '*.hpp' 2>/dev/null |
      grep -E '^\+' | grep -vE '^\+\+\+' |
      grep -oE '\b[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' |
      sed 's/[[:space:]]*($//; s/[[:space:]]*(//'
    git diff -U0 "$BASE"..HEAD -- '*.c' '*.cc' '*.cpp' '*.cxx' '*.h' '*.hpp' 2>/dev/null |
      grep -E '^@@' |
      sed 's/^@@[^@]*@@//' |
      grep -oE '\b[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' |
      sed 's/[[:space:]]*($//; s/[[:space:]]*(//'
  } 2>/dev/null | sort -u |
    grep -vE '^(if|for|while|switch|return|sizeof|catch|and|or|not)$' || true
)
[ -n "$SYMS" ] || exit 0

# ---- 2. reverse-grep the docs -------------------------------------------------
# Product/build artefacts are not documentation — skip them.
MD_FILES=$(git ls-files '*.md' 2>/dev/null |
    grep -vE '^(\.harness-anchor/|evidence/|docs/superpowers/|node_modules/)' || true)
[ -n "$MD_FILES" ] || exit 0

printf '%s\n' "$SYMS" | while IFS= read -r sym; do
    [ -n "$sym" ] || continue
    # LEADING \b only — deliberately, and verified: the motivating case needs the
    # symbol `cancel` to match the prose word "Cancellation", so this MUST be a
    # prefix match. `\bcancel\b` matches neither "Cancellation" nor
    # "cancellation_policy" and would break the only case this exists for.
    # Prefix matching therefore also hits `cancellation_policy` — an ACCEPTED
    # over-match, not an oversight: this script emits CANDIDATES for a human or
    # agent to judge, never verdicts. Over-matching costs one read; under-matching
    # costs a silent miss, which is the failure being fixed.
    # -i because prose capitalises.
    printf '%s\n' "$MD_FILES" | while IFS= read -r md; do
        [ -f "$md" ] || continue
        grep -inE "\\b${sym}" "$md" 2>/dev/null | while IFS=: read -r ln text; do
            printf '%s:%s\t%s\t%s\n' "$md" "$ln" "$sym" \
                "$(printf '%s' "$text" | sed 's/^[[:space:]-]*//')"
        done
    done
done | sort -u

exit 0
