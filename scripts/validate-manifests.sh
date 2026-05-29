#!/usr/bin/env bash
# validate-manifests.sh — Validate plugin.json and marketplace.json manifests.
#
# Uses Python stdlib only (json module) — no third-party jsonschema dependency.
# Human-readable JSON Schema files exist under scripts/schemas/ for reference only.
#
# Checks:
#   1. Both files parse as valid JSON
#   2. plugin.json: name (kebab-case), description (non-empty), version (semver),
#      keywords (all strings)
#   3. marketplace.json: name (non-empty), plugins[0] required fields
#   4. plugin.json and marketplace.json versions match
#
# Usage: bash scripts/validate-manifests.sh [--plugin-root <path>]
#         bash scripts/validate-manifests.sh --fixtures <dir>  (test negative fixtures)
#
# Exit 0 on pass, 1 on fail.

set -uo pipefail

FAIL=0
PASS_COUNT=0
FAIL_COUNT=0

ok()   { echo "  OK    $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "  FAIL  $*"; FAIL_COUNT=$((FAIL_COUNT+1)); FAIL=1; }

# ---- Parse args ----
PLUGIN_ROOT=""
FIXTURE_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --plugin-root) PLUGIN_ROOT="$2"; shift 2 ;;
        --fixtures)    FIXTURE_DIR="$2"; shift 2 ;;
        *)             echo "Unknown arg: $1"; exit 2 ;;
    esac
done

if [ -n "$FIXTURE_DIR" ]; then
    # Test mode: validate all .json files in the fixture dir as if they were plugin.json.
    # Each should FAIL (they're negative fixtures).
    echo "=== validate-manifests (fixture test) ==="
    echo "Root: $FIXTURE_DIR"
    echo ""

    for f in "$FIXTURE_DIR"/*.json "$FIXTURE_DIR"/*/*.json; do
        [ -e "$f" ] || continue
        # Skip files in version-mismatch subdirs — they're tested as pairs below.
        dir_of_f=$(dirname "$f")
        if [ -f "$dir_of_f/plugin.json" ] && [ -f "$dir_of_f/marketplace.json" ]; then
            continue
        fi
        label=$(basename "$f")
        # Run the validator on the fixture as plugin.json
        result=$(python3 - "$f" <<'PY' 2>&1 || true
import json, sys, re

path = sys.argv[1]
try:
    with open(path) as f:
        d = json.load(f)
except Exception as e:
    print(f"FAIL: {e}")
    sys.exit(1)

errors = []

name = d.get("name", "")
if not name:
    errors.append("name missing")
elif not re.match(r'^[a-z][a-z0-9-]*$', name):
    errors.append(f"name not kebab-case: '{name}'")

desc = d.get("description", "")
if not desc:
    errors.append("description empty")

version = d.get("version", "")
if not version:
    errors.append("version missing")
elif not re.match(r'^\d+\.\d+\.\d+$', version):
    errors.append(f"version not semver: '{version}'")

keywords = d.get("keywords", [])
if not isinstance(keywords, list):
    errors.append("keywords not array")
elif not all(isinstance(k, str) for k in keywords):
    errors.append("keywords contain non-strings")

if errors:
    for e in errors:
        print(f"FAIL: {e}")
    sys.exit(1)
else:
    print("PASS")
    sys.exit(0)
PY
)
        if echo "$result" | grep -q "FAIL"; then
            ok "$label: correctly rejected (negative fixture)"
        else
            fail "$label: should have been rejected but passed"
        fi
    done

    # Also test version-sync on subdirs that have both plugin.json + marketplace.json.
    for subdir in "$FIXTURE_DIR"/*/; do
        [ -d "$subdir" ] || continue
        pj="$subdir/plugin.json"
        mj="$subdir/marketplace.json"
        if [ -f "$pj" ] && [ -f "$mj" ]; then
            dir_label=$(basename "$subdir")
            pv=$(python3 -c "import json; print(json.load(open('$pj')).get('version',''))" 2>/dev/null || echo "")
            mv=$(python3 -c "import json; print(json.load(open('$mj')).get('plugins',[{}])[0].get('version',''))" 2>/dev/null || echo "")
            if [ "$pv" != "$mv" ]; then
                ok "$dir_label: version mismatch correctly detected ($pv vs $mv)"
            else
                fail "$dir_label: versions unexpectedly match ($pv)"
            fi
        fi
    done

    echo ""
    echo "==================================="
    echo " Pass: $PASS_COUNT    Fail: $FAIL_COUNT"
    if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
fi

# ---- Normal mode: validate real manifests ----
PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$PLUGIN_ROOT" || { echo "FATAL: cannot cd to $PLUGIN_ROOT"; exit 2; }

echo "=== validate-manifests ==="
echo "Root: $PLUGIN_ROOT"
echo ""

PLUGIN_JSON=".claude-plugin/plugin.json"
MARKETPLACE_JSON=".claude-plugin/marketplace.json"

# ---- Shared Python validator ----
validate_plugin_json() {
    local path="$1"
    local label="$2"
    python3 - "$path" <<'PY' 2>&1
import json, sys, re

path = sys.argv[1]
try:
    with open(path) as f:
        d = json.load(f)
except Exception as e:
    print(f"FAIL: JSON parse error: {e}")
    sys.exit(1)

errors = []

name = d.get("name", "")
if not name:
    errors.append("name missing")
elif not re.match(r'^[a-z][a-z0-9-]*$', name):
    errors.append(f"name not kebab-case: '{name}'")

desc = d.get("description", "")
if not desc:
    errors.append("description empty")

version = d.get("version", "")
if not version:
    errors.append("version missing")
elif not re.match(r'^\d+\.\d+\.\d+$', version):
    errors.append(f"version not semver: '{version}'")

keywords = d.get("keywords", [])
if not isinstance(keywords, list):
    errors.append("keywords not array")
elif not all(isinstance(k, str) for k in keywords):
    errors.append("keywords contain non-strings")

if errors:
    for e in errors:
        print(f"FAIL: {e}")
    sys.exit(1)
else:
    print("PASS")
    sys.exit(0)
PY
}

# ---- 1. plugin.json ----
echo "[1/3] plugin.json..."
if [ -f "$PLUGIN_JSON" ]; then
    result=$(validate_plugin_json "$PLUGIN_JSON" "plugin.json")
    if echo "$result" | grep -q "PASS"; then
        ok "plugin.json valid"
    else
        echo "$result" | while IFS= read -r line; do fail "$line"; done
    fi
else
    fail "plugin.json not found"
fi
echo ""

# ---- 2. marketplace.json ----
echo "[2/3] marketplace.json..."
if [ -f "$MARKETPLACE_JSON" ]; then
    result=$(python3 - "$MARKETPLACE_JSON" <<'PY' 2>&1
import json, sys, re

path = sys.argv[1]
try:
    with open(path) as f:
        d = json.load(f)
except Exception as e:
    print(f"FAIL: JSON parse error: {e}")
    sys.exit(1)

errors = []

name = d.get("name", "")
if not name:
    errors.append("name missing")

plugins = d.get("plugins", [])
if not isinstance(plugins, list) or len(plugins) == 0:
    errors.append("plugins array empty or missing")
else:
    p = plugins[0]
    for field in ["name", "description", "version"]:
        if not p.get(field):
            errors.append(f"plugins[0].{field} missing or empty")

if errors:
    for e in errors:
        print(f"FAIL: {e}")
    sys.exit(1)
else:
    print("PASS")
    sys.exit(0)
PY
)
    if echo "$result" | grep -q "PASS"; then
        ok "marketplace.json valid"
    else
        echo "$result" | while IFS= read -r line; do fail "$line"; done
    fi
else
    fail "marketplace.json not found"
fi
echo ""

# ---- 3. Version sync ----
echo "[3/3] Version sync..."
pv=$(python3 -c "import json; print(json.load(open('$PLUGIN_JSON')).get('version',''))" 2>/dev/null || echo "")
mv=$(python3 -c "import json; print(json.load(open('$MARKETPLACE_JSON')).get('plugins',[{}])[0].get('version',''))" 2>/dev/null || echo "")

if [ -z "$pv" ] || [ -z "$mv" ]; then
    fail "could not read version from one or both manifests"
elif [ "$pv" = "$mv" ]; then
    ok "versions match: $pv"
else
    fail "version mismatch: plugin.json=$pv, marketplace.json=$mv"
fi
echo ""

# ---- Summary ----
echo "==================================="
echo " Pass: $PASS_COUNT    Fail: $FAIL_COUNT"
if [ "$FAIL" -eq 0 ]; then
    echo " STATUS: PASSED"
    exit 0
else
    echo " STATUS: FAILED"
    exit 1
fi
