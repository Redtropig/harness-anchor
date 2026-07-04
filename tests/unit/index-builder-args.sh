#!/usr/bin/env bash
# Unit test for --target/--output argument hardening in scripts/index-builder.mjs.
#
# index-builder WRITES PROJECT-TOC.md into join(TARGET, OUTPUT). With lax parsing
# (args.target = argv[++i]), a missing or empty value (e.g. an unset shell variable
# in --target "$DIR") silently falls back to the cwd and REWRITES THE WRONG
# PROJECT'S INDEX, and a following flag is eaten as the value (--target --output
# even mkdirs a junk './--output/.harness-anchor/' via the fatal-path error log).
# Mirrors tests/unit/state-archive.sh case 11: missing / empty / flag-like value
# -> exit 1, clear one-line error, decoy cwd byte-identical, no junk paths.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IB="$PLUGIN_ROOT/scripts/index-builder.mjs"

PASS=0; FAIL=0
ok()  { echo "  OK   $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

command -v node >/dev/null 2>&1 || { echo "SKIP: node not found"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# init_repo <dir> — throwaway git repo with one tracked file: a VALID index target,
# so a wrongful fallback write would actually succeed — that is the hazard we pin.
init_repo() {
    git -C "$1" init -q
    git -C "$1" config user.email t@e.com
    git -C "$1" config user.name t
    printf '# tracked\n' > "$1/tracked.md"
    git -C "$1" add -A
    git -C "$1" commit -qm init
}

DECOY="$TMP/decoy"; mkdir -p "$DECOY"; init_repo "$DECOY"
WORK="$TMP/work";   mkdir -p "$WORK";  init_repo "$WORK"

# Sentinel TOC in the decoy: any rewrite of it is the failure we're guarding against.
printf 'SENTINEL — this exact content must survive every refused run\n' > "$DECOY/PROJECT-TOC.md"
sha() { shasum "$1" | awk '{print $1}'; }
b0=$(sha "$DECOY/PROJECT-TOC.md")

echo "=== 1. --target hardening (missing/empty/flag-like -> exit 1) ==="
out=$( cd "$DECOY" && node "$IB" --target 2>&1 ); rc=$?
[ "$rc" -eq 1 ] && ok "missing value exits 1" || bad "missing value: expected exit 1, got $rc ($out)"
printf '%s' "$out" | grep -q -- '--target requires' && ok "missing value names the problem" || bad "no clear error: $out"
out=$( cd "$DECOY" && node "$IB" --target "" 2>&1 ); rc=$?
[ "$rc" -eq 1 ] && ok "empty value (unset shell var) exits 1" || bad "empty value: expected exit 1, got $rc ($out)"
out=$( cd "$DECOY" && node "$IB" --target --output out.md 2>&1 ); rc=$?
[ "$rc" -eq 1 ] && ok "flag-like value exits 1 (does not eat --output)" || bad "flag-like value: expected exit 1, got $rc ($out)"
printf '%s' "$out" | grep -q -- '--target requires' && ok "refusal is the parse error, not a downstream fatal" || bad "wrong error: $out"

echo "=== 2. --output hardening (missing/empty/flag-like -> exit 1) ==="
out=$( cd "$DECOY" && node "$IB" --output 2>&1 ); rc=$?
[ "$rc" -eq 1 ] && ok "missing value exits 1" || bad "missing value: expected exit 1, got $rc ($out)"
printf '%s' "$out" | grep -q -- '--output requires' && ok "missing value names the problem" || bad "no clear error: $out"
out=$( cd "$DECOY" && node "$IB" --output "" 2>&1 ); rc=$?
[ "$rc" -eq 1 ] && ok "empty value exits 1" || bad "empty value: expected exit 1, got $rc ($out)"
out=$( cd "$DECOY" && node "$IB" --output --target "$WORK" 2>&1 ); rc=$?
[ "$rc" -eq 1 ] && ok "flag-like value exits 1 (does not eat --target)" || bad "flag-like value: expected exit 1, got $rc ($out)"

echo "=== 3. refused runs left no trace in the decoy cwd ==="
[ "$(sha "$DECOY/PROJECT-TOC.md")" = "$b0" ] && ok "decoy PROJECT-TOC.md byte-identical" || bad "a refused run rewrote the decoy's index"
[ ! -e "$DECOY/--output" ] && [ ! -e "$DECOY/--target" ] && ok "no junk flag-named paths created" || bad "flag eaten as a path left junk in the decoy"
[ ! -e "$DECOY/.harness-anchor" ] && ok "usage refusal never reached the TARGET-derived error log" || bad "refusal wrote .harness-anchor/ into the decoy"
[ ! -e "$WORK/PROJECT-TOC.md" ] && ok "work repo untouched by refused runs" || bad "refused run wrote into the work repo"

echo "=== 4. valid values still work (value consumption intact) ==="
out=$( cd "$DECOY" && node "$IB" --target "$WORK" --output custom-toc.md 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && ok "valid --target + --output exit 0" || bad "valid run failed: rc=$rc ($out)"
[ -f "$WORK/custom-toc.md" ] && ok "wrote into the requested target/output" || bad "custom-toc.md not written"
grep -q 'tracked.md' "$WORK/custom-toc.md" 2>/dev/null && ok "index content present" || bad "index content missing"
[ "$(sha "$DECOY/PROJECT-TOC.md")" = "$b0" ] && ok "decoy still untouched after valid run elsewhere" || bad "valid run leaked into the decoy cwd"

echo ""
echo "==================================="
echo " Pass: $PASS    Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
