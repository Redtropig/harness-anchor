#!/usr/bin/env bash
# Unit test: feature_list.schema.json is actually exercised (anti-drift) and the
# e2e fixture conforms to it. Reads the rules FROM the schema so they cannot
# silently drift from what's enforced. Python stdlib only — no `jsonschema`
# dependency, matching scripts/validate-manifests.sh.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Python discovery via the shared chain (python3→python→py); the whole test is a
# python oracle, so a missing interpreter is an honest whole-file SKIP. argv-passed
# path is MSYS-safe. (v0.13.0)
# shellcheck disable=SC1091
. "$PLUGIN_ROOT/scripts/lib/portable.sh" 2>/dev/null || true
PYBIN=""
command -v ha_python >/dev/null 2>&1 && PYBIN=$(ha_python || true)
[ -n "$PYBIN" ] || { echo "SKIP: feature-list-schema needs python (python3/python/py)"; exit 0; }

# shellcheck disable=SC2086
$PYBIN - "$PLUGIN_ROOT" <<'PY'
import json, re, sys, os
root = sys.argv[1]
schema_path  = os.path.join(root, "templates", "feature_list.schema.json")
fixture_path = os.path.join(root, "tests", "e2e-cpp-fixture", "feature_list.json")

P = F = 0
def ok(m):
    global P; P += 1; print(f"  OK   {m}")
def bad(m):
    global F; F += 1; print(f"  FAIL {m}")

with open(schema_path) as fh:
    schema = json.load(fh)
ok("schema parses as JSON")

feat = schema["definitions"]["feature"]

# --- anti-drift: the schema must still DECLARE its core constraints ---
req_top = schema.get("required", [])
if "project" in req_top and "features" in req_top:
    ok("top-level requires project + features")
else:
    bad(f"top-level required drift: {req_top}")

freq = set(feat.get("required", []))
expected_freq = {"id", "name", "description", "status", "done_criteria"}
if expected_freq.issubset(freq):
    ok("feature required fields intact")
else:
    bad(f"feature required drift: {sorted(freq)}")

status_enum = set(feat["properties"]["status"]["enum"])
if status_enum == {"planned", "in-progress", "pass", "blocked"}:
    ok("status enum intact")
else:
    bad(f"status enum drift: {sorted(status_enum)}")

id_pat = feat["properties"]["id"]["pattern"]

allof = json.dumps(feat.get("allOf", []))
if '"const": "pass"' in allof and "evidence" in allof:
    ok("Default-FAIL rule present (status=pass requires evidence object)")
else:
    bad("Default-FAIL allOf missing from schema")

# --- validator driven by the schema-derived rules ---
def violations(doc):
    errs = []
    for k in req_top:
        if k not in doc:
            errs.append(f"missing top-level '{k}'")
    for ft in doc.get("features", []):
        fid = ft.get("id")
        for k in expected_freq:
            if k not in ft:
                errs.append(f"{fid}: missing '{k}'")
        if ft.get("status") not in status_enum:
            errs.append(f"{fid}: bad status {ft.get('status')!r}")
        if not re.match(id_pat, ft.get("id", "")):
            errs.append(f"{fid}: id violates pattern")
        if not ft.get("done_criteria"):
            errs.append(f"{fid}: empty done_criteria")
        if ft.get("status") == "pass" and not isinstance(ft.get("evidence"), dict):
            errs.append(f"{fid}: status=pass without evidence object")
    return errs

with open(fixture_path) as fh:
    fixture = json.load(fh)
errs = violations(fixture)
if not errs:
    ok("e2e fixture conforms to the schema")
else:
    bad("e2e fixture violations: " + "; ".join(errs))

# --- feature ids must be UNIQUE (the schema cannot express this; enforced imperatively) ---
fixture_ids = [ft.get("id") for ft in fixture.get("features", [])]
if len(fixture_ids) == len(set(fixture_ids)):
    ok("e2e fixture feature ids are unique")
else:
    dupes = sorted({i for i in fixture_ids if fixture_ids.count(i) > 1})
    bad("e2e fixture has duplicate feature ids: " + ", ".join(dupes))

# --- negative: Default-FAIL must reject a pass-without-evidence doc ---
bad_doc = {"project": "x", "features": [
    {"id": "f", "name": "n", "description": "d",
     "status": "pass", "done_criteria": ["c"], "evidence": None}]}
if violations(bad_doc):
    ok("Default-FAIL rejects pass-without-evidence")
else:
    bad("Default-FAIL did NOT reject pass-without-evidence")

print(f"\n Pass: {P}  Fail: {F}")
print(" STATUS: PASSED" if F == 0 else " STATUS: FAILED")
sys.exit(0 if F == 0 else 1)
PY
