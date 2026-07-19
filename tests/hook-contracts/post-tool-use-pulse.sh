#!/usr/bin/env bash
# Contract test for hooks/post-tool-use — pulse fast lane (v0.15.0).
#
# Covers: duplicate-call nudge (3x identical -> fires; 2x / varied input -> silent),
# error-streak nudge, post-nudge cooldown, malformed stdin, unanchored cwd,
# non-Edit tools bypassing the slow lane. Tasks 2-3 append watermark + selfcheck
# scenarios at the marker near the bottom.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/post-tool-use"

PASS=0; FAIL=0
ok()  { echo "  OK   $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }
assert_contains() {
    if printf '%s' "$2" | grep -q "$1"; then ok "contains: $1"
    else bad "missing: $1 (in: $(printf '%s' "$2" | head -c 200))"; fi
}
assert_silent() {
    if [ -z "$2" ]; then ok "$1 silent"
    else bad "$1 unexpectedly emitted: $(printf '%s' "$2" | head -c 200)"; fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR" || exit 1
printf '{ "project": "pulse-fixture", "features": [] }\n' > feature_list.json

# mkev <tool> <sid> <input-json-fragment> <response-json-fragment>
# Emits a hook event whose envelope fields precede tool_input (matching Claude
# Code serialization — the fast lane reads them from a 1 KiB head slice).
mkev() {
    printf '{"session_id":"%s","transcript_path":"","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":%s,"tool_response":%s}' \
        "$2" "$TMPDIR" "$1" "$3" "$4"
}
run_hook() { bash "$HOOK" 2>/dev/null || true; }

echo "=== duplicate call: 3x identical Bash -> nudge on the 3rd, not before ==="
o1=$(mkev Bash s-dup '{"command":"ls -la"}' '{"stdout":"x"}' | run_hook)
assert_silent "1st call" "$o1"
o2=$(mkev Bash s-dup '{"command":"ls -la"}' '{"stdout":"x"}' | run_hook)
assert_silent "2nd call" "$o2"
o3=$(mkev Bash s-dup '{"command":"ls -la"}' '{"stdout":"x"}' | run_hook)
assert_contains "called 3x with identical input" "$o3"
assert_contains "additionalContext" "$o3"
[ -f "$TMPDIR/.harness-anchor/pulse-s-dup.tsv" ] && ok "pulse window file written" || bad "pulse tsv missing"
[ "$(tr -cd '0-9' < "$TMPDIR/.harness-anchor/pulse-s-dup.last" 2>/dev/null)" = "3" ] && ok "cooldown anchor = 3" || bad "cooldown anchor wrong"

echo ""
echo "=== cooldown: 4th identical call stays silent ==="
o4=$(mkev Bash s-dup '{"command":"ls -la"}' '{"stdout":"x"}' | run_hook)
assert_silent "4th call (cooldown)" "$o4"

echo ""
echo "=== varied input: 2 identical + 1 different -> silent ==="
mkev Bash s-var '{"command":"a"}' '{"stdout":"x"}' | run_hook >/dev/null
mkev Bash s-var '{"command":"a"}' '{"stdout":"x"}' | run_hook >/dev/null
ov=$(mkev Bash s-var '{"command":"b"}' '{"stdout":"x"}' | run_hook)
assert_silent "varied 3rd" "$ov"

echo ""
echo "=== error streak: 3x same tool with is_error:true (inputs differ) ==="
mkev Bash s-err '{"command":"x1"}' '{"is_error":true,"stderr":"boom"}' | run_hook >/dev/null
mkev Bash s-err '{"command":"x2"}' '{"is_error":true,"stderr":"boom"}' | run_hook >/dev/null
oe=$(mkev Bash s-err '{"command":"x3"}' '{"is_error":true,"stderr":"boom"}' | run_hook)
assert_contains "failed 3x in a row" "$oe"

echo ""
echo "=== non-Edit tool never reaches the slow lane (no regression-warn) ==="
# A pass-feature ledger would make the slow lane warn on source edits; a Grep
# event must not trigger it even with a file_path in tool_input.
printf '{ "project": "p", "features": [ {"id":"f","name":"F","description":"d","status":"pass","done_criteria":["x"],"evidence":{"timestamp":"t","commit":"c","artifacts":["src/a.py"]}} ] }\n' > feature_list.json
og=$(mkev Grep s-grep '{"pattern":"x","file_path":"'"$TMPDIR"'/src/a.py"}' '{"matches":[]}' | run_hook)
assert_silent "Grep bypasses slow lane" "$og"
printf '{ "project": "pulse-fixture", "features": [] }\n' > feature_list.json

echo ""
echo "=== malformed stdin -> exit 0, silent ==="
om=$(printf '{not json' | run_hook)
assert_silent "malformed stdin" "$om"

echo ""
echo "=== unanchored cwd -> silent, no state dir created ==="
UNANCH=$(mktemp -d)
ou=$(printf '{"session_id":"s-un","transcript_path":"","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"stdout":"x"}}' "$UNANCH" | run_hook)
assert_silent "unanchored" "$ou"
[ ! -d "$UNANCH/.harness-anchor" ] && ok "no state dir in unanchored project" || bad "state dir created in unanchored project"
rm -rf "$UNANCH"

# === TASK2-SCENARIOS ===
# === TASK3-SCENARIOS ===

echo ""
echo "==================================="
echo " Pass: $PASS    Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
