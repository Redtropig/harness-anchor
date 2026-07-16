#!/usr/bin/env bash
# Contract test for the SessionStart state-file budget sentinel (v0.9.0).
#
# The sentinel line must appear ONLY when a budgeted state file exceeds its byte
# threshold, must name every offending file on ONE line, must point at /session-end,
# and must never push the decoded context past the 12000-char cap (invariant #2).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Shared engine chain: ha_json_field for additionalContext, $PYBIN for the
# fixture-writer heredocs (python3→python→py). (v0.13.0)
# shellcheck disable=SC1091
. "$PLUGIN_ROOT/scripts/lib/portable.sh" 2>/dev/null || true
PYBIN=""
command -v ha_python >/dev/null 2>&1 && PYBIN=$(ha_python || true)
# The fixture generators below need python to build the >64KB/>32KB state files;
# without it there is nothing meaningful to measure — honest whole-file SKIP. (v0.13.0)
[ -n "$PYBIN" ] || { echo "SKIP: session-start-state-budget needs python (python3/python/py)"; exit 0; }
PASS=0; FAIL=0
ok()  { echo "  OK   $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

decode_ctx() {
    printf '%s' "$1" | ha_json_field hookSpecificOutput.additionalContext
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
# shellcheck disable=SC2086
$PYBIN - <<'PY'
with open('progress.md', 'w') as f:
    f.write('# Progress Log\n\n---\n')
    for i in range(400):
        f.write(f'\n## 2026-06-01 10:{i % 60:02d} — Session {i}\n\n- ' + 'x' * 160 + '\n')
PY
# Discriminator note: 'progress.md' / '/session-end' also occur in the injected meta-skill
# body, so line-content assertions must be scoped to the sentinel line itself.
out=$(run_hook "$T"); ctx=$(decode_ctx "$out")
sline=$(printf '%s' "$ctx" | grep 'State budget:' || true)
[ -n "$sline" ] && ok "sentinel line present" || bad "sentinel missing"
printf '%s' "$sline" | grep -q 'progress.md' && ok "sentinel names progress.md" || bad "progress.md not on sentinel line: $sline"
printf '%s' "$sline" | grep -q '/session-end' && ok "sentinel points at /session-end" || bad "no /session-end pointer on sentinel line: $sline"
len=${#ctx}
if [ "$len" -le 12000 ]; then ok "context ${len} <= 12000"; else bad "context ${len} > 12000"; fi

echo ""
echo "=== feature_list.json also > 32KB -> both named on ONE line ==="
# shellcheck disable=SC2086
$PYBIN - <<'PY'
import json
feats = []
for i in range(60):
    feats.append({"id": f"f-{i:03d}", "name": "N" * 40, "description": "D" * 300,
                  "status": "planned", "done_criteria": ["x" * 100]})
json.dump({"project": "s", "features": feats}, open('feature_list.json', 'w'), indent=2)
PY
ctx=$(decode_ctx "$(run_hook "$T")")
sline=$(printf '%s' "$ctx" | grep 'State budget:' || true)
printf '%s' "$sline" | grep -q 'feature_list.json' && ok "sentinel names feature_list.json" || bad "feature_list.json not on sentinel line: $sline"
printf '%s' "$sline" | grep -q 'progress.md' && ok "sentinel still names progress.md" || bad "progress.md dropped from sentinel line: $sline"
n=$(printf '%s' "$ctx" | grep -c 'State budget:')
if [ "$n" -eq 1 ]; then ok "exactly one sentinel line"; else bad "expected 1 sentinel line, got $n"; fi

echo ""
echo "=== golden-rules.md > 8KB (non-archivable file) -> also named on the sentinel line ==="
# shellcheck disable=SC2086
$PYBIN - <<'PY'
with open('golden-rules.md', 'w') as f:
    f.write('# Golden Rules\n\n## Rules\n')
    for i in range(1, 60):
        f.write(f'\n### GR-{i} — rule {i}\n- **Why / origin:** ' + 'y' * 120 + '\n- **Check:** manual review\n')
PY
ctx=$(decode_ctx "$(run_hook "$T")")
sline=$(printf '%s' "$ctx" | grep 'State budget:' || true)
printf '%s' "$sline" | grep -q 'golden-rules.md' && ok "sentinel names golden-rules.md" || bad "golden-rules.md not on sentinel line: $sline"
n=$(printf '%s' "$ctx" | grep -c 'State budget:')
if [ "$n" -eq 1 ]; then ok "still exactly one sentinel line"; else bad "expected 1 sentinel line, got $n"; fi

echo ""
echo "=== barely over cap (65537B) -> size rounds UP: 65KB>64KB, never self-equal 64KB>64KB ==="
printf '{ "project": "s", "features": [] }\n' > feature_list.json
rm -f golden-rules.md
# shellcheck disable=SC2086
$PYBIN - <<'PY'
# ASCII-only so char count == byte count: exactly 65537 bytes, one over the cap.
s = '# Progress Log\n\n---\n\n## 2026-06-02 - Session X\n\n- '
s += 'x' * (65537 - len(s))
open('progress.md', 'w').write(s)
PY
ctx=$(decode_ctx "$(run_hook "$T")")
sline=$(printf '%s' "$ctx" | grep 'State budget:' || true)
printf '%s' "$sline" | grep -q 'progress.md 65KB>64KB' && ok "boundary renders 65KB>64KB" || bad "boundary not ceiled: $sline"
if printf '%s' "$sline" | grep -q '64KB>64KB'; then bad "self-equal 64KB>64KB rendered: $sline"; else ok "no self-equal rendering"; fi

echo ""
echo "==================================="
echo " Pass: $PASS    Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
