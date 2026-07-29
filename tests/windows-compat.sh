#!/usr/bin/env bash
# windows-compat.sh — Static Windows-compatibility invariants (any platform).
#
#   [1/5] No bare python3 invocation in hooks (must go through scripts/lib/portable.sh)
#   [2/5] No '!= "/"' loop termination anywhere in hooks/ or scripts/ (non-portable
#         on drive-letter paths; use ha_find_project_root / fixed-point dirname)
#   [3/5] Every extensionless hook carries gitattributes eol=lf; index has no CRLF
#   [4/5] run-hook.cmd: env-var Git paths + WSL System32 bash exclusion present
#   [5/5] Every hook sources scripts/lib/portable.sh and calls ha_platform_init
#
# Exit 1 on any violation.
# shellcheck disable=SC2086  # $HOOKS word-splitting is intentional (fixed known list)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PLUGIN_ROOT" || exit 2

PASS=0; FAIL=0
ok()   { echo "  OK   $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

HOOKS="hooks/session-start hooks/post-tool-use hooks/stop hooks/user-prompt-submit"

echo "[1/5] No bare python3 INVOCATION in hooks..."
# Match invocation shapes only (python3 -c / python3 - "$f" / | python3 / $(python3);
# prose mentions like "(needs python3 or node)" and comments must NOT trip this.
if grep -nE 'python3[[:space:]]+-|[|]([[:space:]])*python3|\$\(python3' $HOOKS 2>/dev/null | grep -q .; then
    grep -nE 'python3[[:space:]]+-|[|]([[:space:]])*python3|\$\(python3' $HOOKS
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
for h in $HOOKS scripts/lib/portable.sh; do
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
