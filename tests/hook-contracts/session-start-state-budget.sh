#!/usr/bin/env bash
# Contract test for the SessionStart state-file budget sentinel (v0.9.0).
#
# The sentinel line must appear ONLY when a budgeted state file exceeds its byte
# threshold, must name every offending file on ONE line, must point at /session-end,
# and must never push the decoded context past the 8000-char cap (invariant #2).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0; FAIL=0
ok()  { echo "  OK   $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

decode_ctx() {
    printf '%s' "$1" | python3 -c "import json,sys; print(json.load(sys.stdin).get('hookSpecificOutput',{}).get('additionalContext',''))" 2>/dev/null || true
}
run_hook() {
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$1" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true
}

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1
printf '{ "project": "s", "features": [] }\n' > feature_list.json
printf '# Progress Log\n\n---\n\n## 2026-07-01 — Session 1\n- ok\n' > progress.md

echo "=== small files -> NO sentinel line ==="
ctx=$(decode_ctx "$(run_hook "$T")")
if printf '%s' "$ctx" | grep -q 'State budget:'; then
    bad "sentinel fired on small files"
else
    ok "no sentinel on small files"
fi

echo ""
echo "=== progress.md > 64KB -> sentinel names it, budget held ==="
python3 - <<'PY'
with open('progress.md', 'w') as f:
    f.write('# Progress Log\n\n---\n')
    for i in range(400):
        f.write(f'\n## 2026-06-01 10:{i % 60:02d} — Session {i}\n\n- ' + 'x' * 160 + '\n')
PY
out=$(run_hook "$T"); ctx=$(decode_ctx "$out")
printf '%s' "$ctx" | grep -q 'State budget:' && ok "sentinel line present" || bad "sentinel missing"
printf '%s' "$ctx" | grep -q 'progress.md' && ok "names progress.md" || bad "progress.md not named"
printf '%s' "$ctx" | grep -q '/session-end' && ok "points at /session-end" || bad "no /session-end pointer"
len=${#ctx}
if [ "$len" -le 8000 ]; then ok "context ${len} <= 8000"; else bad "context ${len} > 8000"; fi

echo ""
echo "=== feature_list.json also > 32KB -> both named on ONE line ==="
python3 - <<'PY'
import json
feats = []
for i in range(60):
    feats.append({"id": f"f-{i:03d}", "name": "N" * 40, "description": "D" * 300,
                  "status": "planned", "done_criteria": ["x" * 100]})
json.dump({"project": "s", "features": feats}, open('feature_list.json', 'w'), indent=2)
PY
ctx=$(decode_ctx "$(run_hook "$T")")
printf '%s' "$ctx" | grep -q 'feature_list.json' && ok "names feature_list.json" || bad "feature_list.json not named"
printf '%s' "$ctx" | grep -q 'progress.md' && ok "still names progress.md" || bad "progress.md dropped"
n=$(printf '%s' "$ctx" | grep -c 'State budget:')
if [ "$n" -eq 1 ]; then ok "exactly one sentinel line"; else bad "expected 1 sentinel line, got $n"; fi

echo ""
echo "==================================="
echo " Pass: $PASS    Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
