#!/usr/bin/env bash
# doc-align.sh — Integrity of the `doc-align` markers under docs/.
#
# A doc-align marker is a standing claim: "this document was verified against
# commit X". Nothing checked the claim's own well-formedness until v0.18.0, and
# two real failures had already happened by then, both in one session:
#
#   1. A 40-character sha typed out from a 7-character short sha. The short form
#      was real; the long form was invented and resolved to nothing. This has now
#      happened twice in this repo's history.
#   2. A marker left pointing at a commit that an `--amend` + rebase had rewritten.
#      The sha was real when written and dangling by the time it was committed.
#
# Neither is visible by reading — both look exactly like a correct marker. Both
# are one `git rev-parse` away from being caught, which is what this does.
#
# Markers are DISCOVERED by glob over docs/*.md, never enumerated.
#
# Checks per marker:
#   [1] the HTML comment carries exactly one 40-hex-character sha
#   [2] that sha resolves to a real commit        (skipped on a shallow clone)
#   [3] that commit is an ancestor of HEAD        (skipped on a shallow clone)
#   [4] any short sha in the human-readable line below is a prefix of the long one
#
# Checks 2 and 3 need real history, which a shallow clone does not have. Rather
# than fail there, they SKIP — and say so on their own line, because a skipped
# check that prints OK is the failure mode this whole file exists to stop.
#
# CI is NOT shallow: .github/workflows/validate.yml sets fetch-depth: 0 on the
# fast-tests job precisely so these two run. Without it the check would pass on a
# marker pointing at a commit that does not exist, which is the case it was
# written for. If that setting is ever removed, this file keeps working and
# quietly stops being a gate — the SKIP line is the only thing that tells you.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PLUGIN_ROOT" || exit 2

PASS=0
FAIL=0
SKIP=0
ok()   { echo "  OK   $*"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL $*"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP $*"; SKIP=$((SKIP+1)); }

SHALLOW=0
if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
    SHALLOW=1
fi

# ---- Discover markers ----
MARKED=""
for f in docs/*.md; do
    [ -f "$f" ] || continue
    grep -q '^<!-- doc-align:' "$f" && MARKED="$MARKED $f"
done
MARKED="${MARKED# }"

# Non-vacuity guard: no markers means every loop below is a no-op and this suite
# would report all-pass having checked nothing.
if [ -z "$MARKED" ]; then
    bad "no doc-align markers found under docs/ — either they were all removed or the pattern stopped matching; every check below would pass vacuously"
else
    # shellcheck disable=SC2086
    ok "discovered $(printf '%s\n' $MARKED | grep -c .) marked doc(s): $MARKED"
fi

if [ "$SHALLOW" -eq 1 ]; then
    skip "shallow clone — sha resolution and ancestry cannot be checked here (CI uses fetch-depth 1; run locally for full coverage)"
fi

# shellcheck disable=SC2086
for f in $MARKED; do
    line=$(grep -m1 '^<!-- doc-align:' "$f")

    # ---- [1] exactly one 40-hex sha in the marker ----
    n_sha=$(printf '%s' "$line" | grep -oE '\b[0-9a-f]{40}\b' | grep -c .)
    if [ "$n_sha" -ne 1 ]; then
        bad "$f: marker carries $n_sha 40-char sha(s), expected exactly 1 — $line"
        continue
    fi
    sha=$(printf '%s' "$line" | grep -oE '\b[0-9a-f]{40}\b' | head -1)
    ok "$f: well-formed 40-char sha"

    # ---- [2] resolves, and [3] is an ancestor of HEAD ----
    if [ "$SHALLOW" -eq 1 ]; then
        : # already reported once, above
    elif ! git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null 2>&1; then
        bad "$f: sha ${sha} does not resolve to any commit — typed out from a short sha, or rewritten by an amend/rebase"
    else
        ok "$f: sha resolves to a real commit"
        if git merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then
            ok "$f: that commit is an ancestor of HEAD"
        else
            bad "$f: ${sha} resolves but is NOT an ancestor of HEAD — the marker points off this branch's history"
        fi
    fi

    # ---- [4] short sha in the prose line agrees with the long one ----
    # The human-readable line under the comment often abbreviates. A mismatch
    # means one of the two was edited alone.
    # 7-40, not 7-12: docs/commands.md spells the sha out in full inside the link
    # text, and a full-length copy that disagrees is exactly as broken as a short one.
    shorts=$(sed -n '1,12p' "$f" | grep -oE '\[`[0-9a-f]{7,40}`\]' | tr -d '[]`' | sort -u)
    if [ -z "$shorts" ]; then
        ok "$f: no abbreviated sha to cross-check"
    else
        mismatch=0
        for s in $shorts; do
            case "$sha" in
                "$s"*) : ;;
                *) bad "$f: prose short sha '$s' is not a prefix of marker sha ${sha}"; mismatch=1 ;;
            esac
        done
        [ "$mismatch" -eq 0 ] && ok "$f: abbreviated sha agrees with the marker"
    fi
done

echo ""
echo "doc-align: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
