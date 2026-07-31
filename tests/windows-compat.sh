#!/usr/bin/env bash
# windows-compat.sh — Static Windows-compatibility invariants (any platform).
#
#   [0/5] Hook discovery (glob, not enumeration) + the non-vacuity guard the four
#         hook-scoped checks below depend on — an empty list would make them no-ops
#   [1/5] No bare python3 invocation in hooks (must go through scripts/lib/portable.sh)
#   [2/5] No '!= "/"' loop termination anywhere in hooks/ or scripts/ (non-portable
#         on drive-letter paths; use ha_find_project_root / fixed-point dirname)
#   [3/5] Every bash-consumed file carries gitattributes eol=lf; index has no CRLF
#   [4/5] run-hook.cmd: env-var Git paths + WSL System32 bash exclusion present
#   [5/5] Every hook sources scripts/lib/portable.sh and calls ha_platform_init
#
# Exit 1 on any violation.
# shellcheck disable=SC2086  # $HOOKS word-splitting is intentional (discovered list)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PLUGIN_ROOT" || exit 2

PASS=0; FAIL=0
ok()   { echo "  OK   $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

# Hooks are DISCOVERED, not enumerated — everything under hooks/ except the JSON
# manifest and the cmd/bash polyglot launcher (CLAUDE.md #10 excludes run-hook.cmd
# from eol=lf on purpose; it is not a bash hook either).
#
# The old hard-coded list had already rotted: hooks/pre-compact shipped in v0.15.0
# and was never added to it, so checks [1/5], [3/5] and [5/5] silently skipped the
# newest hook for two releases. Enumeration rots — this is the same defect class
# tests/README.md and CI both call out in their own comments.
HOOKS=""
for _h in hooks/*; do
    case "$_h" in *.json|*.cmd) continue ;; esac
    [ -f "$_h" ] || continue
    HOOKS="$HOOKS $_h"
done
HOOKS="${HOOKS# }"

echo "[0/5] Hook discovery..."
# Non-vacuity guard: an empty HOOKS makes every loop below a no-op and the suite
# would report all-pass having checked nothing — the exact "didn't look reads as
# found nothing" failure this repo bans elsewhere.
if [ -z "$HOOKS" ]; then
    fail "no hooks discovered under hooks/ — every check below would pass vacuously"
else
    ok "discovered $(printf '%s\n' $HOOKS | grep -c .) hook(s): $HOOKS"
fi

echo "[1/5] No bare python3 INVOCATION in hooks..."
# Match invocation shapes only (python3 -c / python3 - "$f" / | python3 / $(python3);
# prose mentions like "(needs python3 or node)" and comments must NOT trip this.
#
# Comment lines are dropped the same way [2/5] does it. Until v0.18.0 the intent
# above was stated but not implemented: a COMMENT containing the invocation shape
# tripped the check. It fired on hooks/stop and hooks/user-prompt-submit for
# comments explaining that ha_json_engine_init probes by running `python3 -c` —
# i.e. it punished documenting the very hazard this file exists to police. An
# executable line is never comment-leading, so dropping those loses no coverage;
# a trailing comment after real code still matches, which is correct.
PY_INVOKE='python3[[:space:]]+-|[|]([[:space:]])*python3|\$\(python3'
py_hits=$(grep -nE "$PY_INVOKE" $HOOKS 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
if [ -n "$py_hits" ]; then
    printf '%s\n' "$py_hits"
    fail "bare python3 invocation in a hook — use the portable.sh engine chain"
else
    ok "hooks have no direct python3 invocation (engine chain only)"
fi

echo "[2/5] No '!= \"/\"' walk-up termination..."
# A comment that *documents* the retired anti-pattern (e.g. "the old `!= \"/\"`
# loop") is not itself a non-portable loop. Match executable lines only: drop
# grep hits whose content (after the file:line: prefix) begins with '#'.
walk_hits=$(grep -rn '!= "/"' hooks/ scripts/ 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
if [ -n "$walk_hits" ]; then
    printf '%s\n' "$walk_hits"
    fail "non-portable root-walk termination found (breaks on C:/ paths)"
else
    ok "no non-portable walk-up loops"
fi

echo "[3/5] eol=lf attributes + clean index..."
# Beyond the hooks: the shared lib, and the meta-skill — awk-consumed by
# hooks/session-start for the conditional-region filter and the injection length
# count, so its marker anchors and byte counts must not shift with a CRLF
# checkout (.gitattributes says exactly this). Nothing else in the repo verifies
# that pin; it was added in v0.14.0 and this check never learned about it.
for h in $HOOKS scripts/lib/portable.sh skills/using-harness-anchor/SKILL.md; do
    attr=$(git check-attr eol -- "$h" 2>/dev/null | sed 's/.*: eol: //')
    if [ "$attr" = "lf" ]; then ok "eol=lf: $h"; else fail "missing eol=lf attribute: $h (got '$attr')"; fi
done
if git ls-files --eol -- hooks scripts templates tests 2>/dev/null | grep -E 'i/crlf' | grep -q .; then
    git ls-files --eol -- hooks scripts templates tests | grep -E 'i/crlf'
    fail "CRLF content committed to the index"
else
    ok "index is CRLF-free"
fi

echo "[4/5] run-hook.cmd hardening..."
RH="hooks/run-hook.cmd"
grep -qF '%LOCALAPPDATA%\Programs\Git' "$RH" && ok "user-scope Git path present" || fail "missing %LOCALAPPDATA% Git path"
# NB: `-i` COMBINED WITH `-F` SIGABRTs (exit 134) on this MSYS2 grep (GNU 3.0)
# in any non-UTF-8 locale — and an unset LANG, the default here, is the C locale.
# No backslash needed: it dies at matcher construction, so even empty input or a
# non-matching pattern aborts. grep writes nothing to stderr, so the crash reads
# as a legitimate "no matches" — empty string in `$(...)`, false branch in
# `if`/`&&`. Plain `-F` without `-i` is unaffected (see the -qF lines here).
# Hence -E below, with '.' standing in for the literal backslash — same match.
grep -qiE 'System32.bash\.exe' "$RH" && ok "WSL bash exclusion present" || fail "missing System32\\bash.exe (WSL) exclusion"
if grep -qF 'C:\Program Files' "$RH"; then fail "hard-coded 'C:\\Program Files' literal (use %ProgramFiles%)"; else ok "no hard-coded Program Files literal"; fi

echo "[5/5] Hooks source the lib + platform init..."
for h in $HOOKS; do
    grep -q 'scripts/lib/portable\.sh' "$h" && ok "sources lib: $h" || fail "does not source portable.sh: $h"
    grep -q 'ha_platform_init' "$h" && ok "platform init: $h" || fail "missing ha_platform_init: $h"
done

echo ""; echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
