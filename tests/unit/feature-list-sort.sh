#!/usr/bin/env bash
# Unit test for scripts/feature-list-sort.mjs — actionable-first reorder that is
# deterministic, idempotent, and lossless (preserves unknown top-level keys, evidence,
# and 2-space formatting).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SORT="$PLUGIN_ROOT/scripts/feature-list-sort.mjs"
# Oracle checks below read the sorted JSON via python; discover it through the
# shared chain (python3→python→py) and pass paths as argv, never spliced into
# -c text — $FL is an absolute mktemp path native Windows python can't embed-open. (v0.13.0)
# shellcheck disable=SC1091
. "$PLUGIN_ROOT/scripts/lib/portable.sh" 2>/dev/null || true
PYBIN=""
command -v ha_python >/dev/null 2>&1 && PYBIN=$(ha_python || true)

PASS=0; FAIL=0
ok()  { echo "  OK   $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

command -v node >/dev/null 2>&1 || { echo "SKIP: node not found"; exit 0; }
[ -n "$PYBIN" ] || { echo "SKIP: needs python (python3/python/py) for oracle checks"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FL="$TMP/feature_list.json"

# Scrambled order + an unknown top-level key + two pass + two planned to exercise tie-breaks.
cat > "$FL" <<'JSON'
{
  "project": "demo",
  "description": "ordering fixture",
  "customKey": "must-survive",
  "features": [
    { "id": "z-pass-old", "name": "Z", "description": "d", "status": "pass", "done_criteria": ["x"], "evidence": { "timestamp": "2026-01-01T00:00:00Z", "commit": "old", "artifacts": ["a.log"] }, "completedAt": "2026-01-01T00:00:00Z" },
    { "id": "m-planned", "name": "M", "description": "d", "status": "planned", "done_criteria": ["x"], "evidence": null, "createdAt": "2026-03-01T00:00:00Z" },
    { "id": "a-inprog", "name": "A", "description": "d", "status": "in-progress", "done_criteria": ["x"], "evidence": null, "createdAt": "2026-02-01T00:00:00Z" },
    { "id": "b-blocked", "name": "B", "description": "d", "status": "blocked", "done_criteria": ["x"], "evidence": null, "createdAt": "2026-02-15T00:00:00Z", "blockedReason": "waiting" },
    { "id": "y-pass-new", "name": "Y", "description": "d", "status": "pass", "done_criteria": ["x"], "evidence": { "timestamp": "2026-05-01T00:00:00Z", "commit": "new", "artifacts": ["b.log"] }, "completedAt": "2026-05-01T00:00:00Z" },
    { "id": "c-planned-early", "name": "C", "description": "d", "status": "planned", "done_criteria": ["x"], "evidence": null, "createdAt": "2026-01-15T00:00:00Z" }
  ]
}
JSON

node "$SORT" "$FL" || bad "feature-list-sort exited non-zero"

# 1. actionable-first order: in-progress, blocked, planned(createdAt asc), pass(completedAt desc)
# shellcheck disable=SC2086
order=$($PYBIN -c "import json,sys; print(','.join(f['id'] for f in json.load(open(sys.argv[1]))['features']))" "$FL")
expected="a-inprog,b-blocked,c-planned-early,m-planned,y-pass-new,z-pass-old"
if [ "$order" = "$expected" ]; then ok "actionable-first order"; else bad "order: got [$order] want [$expected]"; fi

# 2. unknown top-level key preserved (no silent field loss)
# shellcheck disable=SC2086
if $PYBIN -c "import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get('customKey')=='must-survive' else 1)" "$FL"; then
    ok "unknown top-level key preserved"; else bad "customKey lost"; fi

# 3. evidence preserved on pass features
# shellcheck disable=SC2086
if $PYBIN -c "import json,sys; d=json.load(open(sys.argv[1])); e={f['id']:f.get('evidence') for f in d['features']}; sys.exit(0 if e['y-pass-new'] and e['y-pass-new']['commit']=='new' else 1)" "$FL"; then
    ok "evidence preserved"; else bad "evidence lost/corrupted"; fi

# 4. idempotent: a second run must not change a single byte
before=$(shasum "$FL" | awk '{print $1}')
node "$SORT" "$FL" || bad "second run exited non-zero"
after=$(shasum "$FL" | awk '{print $1}')
if [ "$before" = "$after" ]; then ok "idempotent (stable)"; else bad "second run changed the file"; fi

# 5. 2-space indent preserved
if grep -qE '^  "project":' "$FL"; then ok "2-space indent"; else bad "indentation not 2-space"; fi

# 6. no-op safety: a single-feature file is left byte-for-byte untouched
SOLO="$TMP/solo.json"
printf '{"project":"x","features":[{"id":"only","name":"O","description":"d","status":"planned","done_criteria":["x"]}]}\n' > "$SOLO"
solo_before=$(shasum "$SOLO" | awk '{print $1}')
node "$SORT" "$SOLO" || bad "solo run exited non-zero"
solo_after=$(shasum "$SOLO" | awk '{print $1}')
if [ "$solo_before" = "$solo_after" ]; then ok "single-feature file untouched"; else bad "single-feature file rewritten"; fi

# 7. schema-valid: the sorted output still satisfies feature_list.schema.json's core rules
# shellcheck disable=SC2086
if $PYBIN - "$FL" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
assert 'project' in d and isinstance(d.get('features'), list)
for f in d['features']:
    assert all(k in f for k in ('id', 'name', 'description', 'status', 'done_criteria'))
    assert re.match(r'^[a-z0-9][a-z0-9-]*$', f['id'])
    assert f['status'] in ('planned', 'in-progress', 'pass', 'blocked')
    assert f['status'] != 'pass' or f.get('evidence') is not None
print('ok')
PY
then ok "schema-valid output (incl. Default-FAIL)"; else bad "sorted output violates schema"; fi

echo ""
echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
