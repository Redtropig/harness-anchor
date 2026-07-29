#!/usr/bin/env bash
# doc-drift-scan.sh — Find documentation that should have changed with the code
# and did not.
#
# Usage:
#   bash doc-drift-scan.sh [--base <ref>] [--target <dir>]
#     --base    git ref to diff against (default: merge-base with the default
#               branch if resolvable AND not HEAD itself, else HEAD~1, else the
#               empty-tree hash, so a repo with only one commit still diffs
#               against "nothing" instead of silently skipping the scan). A
#               merge-base that resolves to HEAD itself (we ARE the default
#               branch — the solo-dev / this-repo case) is treated the same as
#               "unresolved" and falls through to HEAD~1: diffing HEAD against
#               HEAD is always empty, so it is not a useful base.
#     --target  project root (default: cwd)
#
# The diff is always BASE..working-tree (`git diff -U0 "$BASE"`, the one-ref
# form) — NEVER "$BASE"..HEAD. /gc is documented (commands/gc.md) as running
# "after a batch of generated code, before /session-end" — i.e. precisely on
# UNCOMMITTED work — so a commit-to-commit range would be blind to exactly the
# case this script exists for.
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
# RESIDUAL BLIND SPOT: symbol extraction only recognizes CALL/DEFINITION-SHAPED
# tokens — an identifier immediately followed by `(`. Two consequences, both
# undetectable by this script: (a) a stale claim that names no symbol at all
# ("the pool is fast") has nothing to key on; (b) a changed global variable,
# macro, enum constant, struct field, or typedef produces NO symbol either —
# so a doc claim naming that exact symbol (e.g. "max_retries defaults to 3"
# after `max_retries` is edited) is just as invisible, for a different reason
# than (a). Documented in agents/drift-analyst.md and frozen as negative
# assertions in tests/unit/doc-drift-scan.sh — a silent pass here must never
# be read as "the docs were checked".
#
# LANGUAGE SCOPE (a separate, orthogonal blind spot): the diff below is
# pathspec-limited to the SCAN_PATHSPEC whitelist. That whitelist IS the
# coverage declaration — a language not on it contributes ZERO symbols even
# when its definitions are perfectly call-shaped (a Python `def cancel(job_id):`
# is as call-shaped as the C++ `bool cancel(JobId id)` this script was built
# around). v0.17.0 widened it from C/C++ only to the mainstream set, and — more
# importantly — made the miss AUDIBLE: when a run changes files but none are in
# the whitelist, that is announced on stderr rather than returning the same
# silent exit 0 as a genuinely clean scan. Through v0.16.0 those two were
# indistinguishable, which is how this script's total blindness on its own
# repository (bash + markdown, zero C/C++ files changed in the whole release)
# survived a full release cycle unnoticed.
#
# NOISE: symbol extraction takes any call-shaped token on any added line —
# including ordinary call sites, not just new/renamed symbols — and doc
# matching is deliberately prefix-based (needed to match "Cancellation" from
# `cancel`; see the comment at the grep site below). For a common-word
# identifier (read, write, get, set, run, check, test, ...) this floods: one
# body-only edit inside a `read(...)` call can surface "please read this",
# "README", "readable", and similar unrelated prose as candidates. This is an
# accepted trade-off, not a bug — see agents/drift-analyst.md's doc-drift step
# for triage guidance when a candidate list is dominated by a common-word
# symbol.

set -uo pipefail

# Diagnostics go to stderr, never stdout: stdout is a parsed contract (one
# candidate per line) and must stay pure. A caller that sees empty stdout AND
# no stderr note has a genuinely clean scan; a caller that sees a `skipped`
# note has NO scan. Those are different facts and must not share a channel.
note() { printf 'doc-drift-scan: %s\n' "$1" >&2; }

# The languages this scan can see. Widening this list is the supported way to
# extend coverage; see LANGUAGE SCOPE in the header for what the list means.
SCAN_PATHSPEC=(
    '*.c' '*.cc' '*.cpp' '*.cxx' '*.h' '*.hpp'
    '*.py' '*.js' '*.jsx' '*.mjs' '*.ts' '*.tsx'
    '*.go' '*.rs' '*.rb' '*.java' '*.kt' '*.cs' '*.sh'
)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/portable.sh" 2>/dev/null || true
if command -v ha_platform_init >/dev/null 2>&1; then ha_platform_init; fi
: "${HA_OS:=linux}"

# Fallback if portable.sh was unavailable — keep the script self-sufficient.
if ! command -v ha_normalize_path >/dev/null 2>&1; then
    ha_normalize_path() { printf '%s' "${1//\\//}"; }
fi

BASE=""; TARGET=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --base)
            # A value-less --base (end of args) must not re-enter the loop with
            # $1/$# unchanged (that's the infinite-loop bug: `shift 2` fails and
            # is a no-op when only one positional remains). A value that itself
            # looks like a flag (starts with `-') must be rejected rather than
            # swallowed as BASE — otherwise the real next flag silently vanishes
            # and the run goes quiet, indistinguishable from "no drift".
            case "${2-}" in
                ""|-*) echo "doc-drift-scan.sh: --base requires a value" >&2; shift;;
                *)     BASE="$2"; shift 2;;
            esac
            ;;
        --target)
            case "${2-}" in
                ""|-*) echo "doc-drift-scan.sh: --target requires a value" >&2; shift;;
                *)     TARGET="$2"; shift 2;;
            esac
            ;;
        *) shift;;
    esac
done
[ -n "$TARGET" ] || TARGET="$(pwd)"
TARGET="$(ha_normalize_path "$TARGET")"
cd "$TARGET" 2>/dev/null || { note "skipped — target is not a readable directory: $TARGET"; exit 0; }
git rev-parse --git-dir >/dev/null 2>&1 || { note "skipped — not a git repository: $TARGET"; exit 0; }

if [ -z "$BASE" ]; then
    for cand in main master; do
        if git rev-parse --verify -q "$cand" >/dev/null 2>&1; then
            BASE=$(git merge-base HEAD "$cand" 2>/dev/null || true)
            [ -n "$BASE" ] && break
        fi
    done
fi
# A merge-base that resolves to HEAD itself means we ARE the default branch
# (the solo-dev default, and this repo's own state) — that is not a useful
# base (BASE..HEAD is always empty, and even the working-tree diff below would
# only ever be "HEAD vs HEAD"'s own uncommitted edits with no committed
# history behind it). Discard it so the HEAD~1 fallback on the next line
# actually gets a turn — previously that fallback was guarded on BASE being
# *empty*, not on it being *useless*, so it never fired here.
if [ -n "$BASE" ]; then
    HEAD_SHA=$(git rev-parse --verify -q HEAD 2>/dev/null || true)
    [ -n "$HEAD_SHA" ] && [ "$BASE" = "$HEAD_SHA" ] && BASE=""
fi
[ -n "$BASE" ] || BASE=$(git rev-parse --verify -q HEAD~1 2>/dev/null || true)
[ -n "$BASE" ] || BASE=$(git hash-object -t tree /dev/null 2>/dev/null || true)
[ -n "$BASE" ] || { note "skipped — no usable base ref (no main/master, no HEAD~1, no empty-tree hash)"; exit 0; }

# ---- 1. changed symbol names --------------------------------------------------
# Two sources, unioned:
#   (a) identifiers on changed lines that look like a declaration/definition
#   (b) the nearest ENCLOSING symbol when only a body line changed — this is the
#       MiniSched case (cancel()'s signature never moved) and is why (a) alone
#       is not enough. `git diff -U0` hunk headers carry that context after the
#       `@@ ... @@` marker, which is exactly git's "enclosing function" hint.
#
# BASE..working-tree, not BASE..HEAD (one-ref `git diff -U0 "$BASE"`, not
# `"$BASE"..HEAD`) — see the file header: uncommitted changes must be visible.
SYMS=$(
  {
    git diff -U0 "$BASE" -- "${SCAN_PATHSPEC[@]}" 2>/dev/null |
      grep -E '^\+' | grep -vE '^\+\+\+' |
      grep -oE '\b[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' |
      sed 's/[[:space:]]*($//; s/[[:space:]]*(//'
    git diff -U0 "$BASE" -- "${SCAN_PATHSPEC[@]}" 2>/dev/null |
      grep -E '^@@' |
      sed 's/^@@[^@]*@@//' |
      grep -oE '\b[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' |
      sed 's/[[:space:]]*($//; s/[[:space:]]*(//'
  } 2>/dev/null | sort -u |
    grep -vE '^(if|for|while|switch|return|sizeof|catch|and|or|not)$' || true
)
if [ -z "$SYMS" ]; then
    n_all=$(git diff --name-only "$BASE" 2>/dev/null | grep -c . || true)
    n_scanned=$(git diff --name-only "$BASE" -- "${SCAN_PATHSPEC[@]}" 2>/dev/null | grep -c . || true)
    if [ "$n_scanned" -eq 0 ]; then
        # The self-blindness case: work happened, this sensor simply cannot see
        # the languages it happened in. Reporting "clean" here would be a lie.
        note "skipped — $n_all file(s) changed, none in scanned languages (see LANGUAGE SCOPE)"
    else
        note "skipped — no changed symbols extracted from $n_scanned changed source file(s)"
    fi
    exit 0
fi

# ---- 2. reverse-grep the docs -------------------------------------------------
# Product/build artefacts are not documentation — skip them.
MD_FILES=$(git ls-files '*.md' 2>/dev/null |
    grep -vE '^(\.harness-anchor/|evidence/|docs/superpowers/|node_modules/)' || true)
[ -n "$MD_FILES" ] || { note "skipped — no documentation files tracked"; exit 0; }

# ---- 3. reverse-grep the docs ------------------------------------------------
# One grep per DOC FILE per chunk — O(files), not O(symbols x files). The old
# nested form ran one grep per (symbol, file) pair and measured 184s on 160
# symbols x 60 docs.
#
# Files stay in a `while read` loop rather than being expanded into grep's
# argument list: `git ls-files '*.md'` can return paths containing spaces, and
# unquoted expansion would shred them. The loop keeps O(files) AND space safety.
#
# LEADING \b only — deliberately, and verified: the motivating case needs the
# symbol `cancel` to match the prose word "Cancellation", so this MUST be a
# prefix match. `\bcancel\b` matches neither "Cancellation" nor
# "cancellation_policy" and would break the only case this exists for.
# Prefix matching therefore also hits `cancellation_policy` — an ACCEPTED
# over-match, not an oversight: this script emits CANDIDATES for a human or
# agent to judge, never verdicts. Over-matching costs one read; under-matching
# costs a silent miss, which is the failure being fixed. -i because prose
# capitalises.
CHUNK=400
HARD_CAP=2000

n_sym=$(printf '%s\n' "$SYMS" | grep -c . || true)
if [ "$n_sym" -gt "$HARD_CAP" ]; then
    SYMS=$(printf '%s\n' "$SYMS" | head -n "$HARD_CAP")
    note "symbol set truncated to $HARD_CAP of $n_sym — results are PARTIAL"
    n_sym="$HARD_CAP"
fi

# Longest symbols first so a longer name is preferred over a shorter one that
# prefixes it (`getFoo` before `get`), without relying on the grep
# implementation's leftmost-longest behaviour.
SYMS_SORTED=$(printf '%s\n' "$SYMS" | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)

n_chunks=$(( (n_sym + CHUNK - 1) / CHUNK ))
[ "$n_chunks" -gt 1 ] && note "chunked into $n_chunks passes ($n_sym symbols)"

RESULTS=$(
  c=0
  while [ "$c" -lt "$n_chunks" ]; do
    CHUNK_SYMS=$(printf '%s\n' "$SYMS_SORTED" | tail -n +$(( c * CHUNK + 1 )) | head -n "$CHUNK")
    ALT=$(printf '%s\n' "$CHUNK_SYMS" | paste -sd'|' -)
    c=$((c+1))
    [ -n "$ALT" ] || continue
    printf '%s\n' "$MD_FILES" | while IFS= read -r md; do
        [ -f "$md" ] || continue
        # Attribution used to spawn `grep -oiE` + `grep -ix` PER CANDIDATE
        # LINE, inside a `while IFS=: read` loop fed by the search grep below.
        # Cheap-looking in isolation, but on the motivating repository
        # candidate LINES vastly outnumber symbol-file pairs (5635 candidates
        # vs. 76 symbols x 53 docs on --base v0.15.0): measured subprocess
        # count went from 4028 (the pre-this-file nested per-(symbol,file)
        # loop) to roughly 11,323 (53 searches + 2 greps x 5635 candidates),
        # and wall time from 8m25.794s (completed) to >10min (killed by
        # timeout, did not complete). The search-phase win this file
        # collapses to O(files) x chunks is real; it was the attribution
        # phase, still scaling with CANDIDATE count, that erased it. A single
        # awk invocation attributes every matching symbol on every candidate
        # line of a document in one pass — one fork per document for
        # attribution, matching the one-fork-per-document search — so total
        # forks per document return to ~2 regardless of candidate count.
        #
        # Attribute the hit back to EVERY symbol that matches on this line —
        # not just the first. A single doc line can legitimately match more
        # than one symbol from the chunk (two renamed functions mentioned in
        # the same sentence is common in this repo's own CHANGELOG); emitting
        # only the first (leftmost) match would silently drop every other
        # symbol's candidate for that line — exactly the silent-miss failure
        # this script exists to avoid (regression-tested: assertion 12).
        #
        # The symbol list is known up front (CHUNK_SYMS, already code-cased),
        # so unlike the old grep -oiE capture there is no PROSE-cased match
        # text to map back to a symbol via a second case-insensitive lookup:
        # awk searches for each symbol's LOWERCASE form inside the LOWERCASE
        # line text directly, and prints the symbol exactly as spelled in
        # CHUNK_SYMS — never the prose casing ("Cancellation" is never
        # printed; `cancel` is).
        #
        # LEADING \b only, reproduced by hand (awk has no \b): a match counts
        # only when the character immediately before it is NOT [a-z0-9_].
        # There is deliberately NO trailing-boundary check — the motivating
        # case needs `cancel` to match inside "Cancellation", so this must
        # stay a prefix match. Do not add one. The inner while-loop re-scans
        # forward past a non-boundary occurrence (start = abs + 1), so
        # `cancel` embedded in `precancel` is correctly skipped at that
        # position while a later, properly-bounded `cancel` on the same line
        # still matches (verified with both occurrences on one line).
        grep -inE "\b(${ALT})" "$md" 2>/dev/null | awk -v syms="$CHUNK_SYMS" -v md="$md" '
            BEGIN { n = split(syms, S, "\n") }
            {
                p = index($0, ":"); if (p == 0) next
                ln = substr($0, 1, p-1); text = substr($0, p+1)
                low = tolower(text)
                stripped = text; sub(/^[[:space:]-]*/, "", stripped)
                for (i = 1; i <= n; i++) {
                    s = S[i]; if (s == "") continue
                    ls = tolower(s); start = 1; found = 0
                    while ((pos = index(substr(low, start), ls)) > 0) {
                        abs = start + pos - 1
                        prev = (abs == 1) ? "" : substr(low, abs-1, 1)
                        if (prev !~ /[a-z0-9_]/) { found = 1; break }
                        start = abs + 1
                    }
                    if (found) print md ":" ln "\t" s "\t" stripped
                }
            }'
    done
  done | sort -u
)
[ -n "$RESULTS" ] && printf '%s\n' "$RESULTS"

n_md=$(printf '%s\n' "$MD_FILES" | grep -c . || true)
n_hit=$(printf '%s\n' "$RESULTS" | grep -c . || true)
note "scanned $n_sym symbol(s) x $n_md doc(s), $n_hit candidate(s)"

exit 0
