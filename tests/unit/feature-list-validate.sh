#!/usr/bin/env bash
# Unit test for scripts/feature-list-validate.mjs — feature `id` uniqueness enforcement
# (the schema's blind spot: draft-07 cannot express per-field uniqueness). Covers default
# (whole-file) mode, --check candidate mode, error paths, the -N suggestion, and read-only.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$PLUGIN_ROOT/scripts/feature-list-validate.mjs"

PASS=0; FAIL=0
ok()  { echo "  OK   $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

command -v node >/dev/null 2>&1 || { echo "SKIP: node not found"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# expect_exit <label> <expected-code> <actual-code>
expect_exit() {
    if [ "$2" = "$3" ]; then ok "$1 (exit $3)"; else bad "$1 — expected exit $2, got $3"; fi
}

UNIQUE="$TMP/unique.json"
cat > "$UNIQUE" <<'JSON'
{ "project": "p", "features": [
  { "id": "cli-parser", "name": "A", "description": "d", "status": "in-progress", "done_criteria": ["x"] },
  { "id": "engine-init", "name": "B", "description": "d", "status": "planned", "done_criteria": ["x"] },
  { "id": "logging", "name": "C", "description": "d", "status": "planned", "done_criteria": ["x"] }
] }
JSON

DUP="$TMP/dup.json"
cat > "$DUP" <<'JSON'
{ "project": "p", "features": [
  { "id": "parser", "name": "A", "description": "d", "status": "planned", "done_criteria": ["x"] },
  { "id": "parser", "name": "B", "description": "d", "status": "in-progress", "done_criteria": ["x"] },
  { "id": "auth", "name": "C", "description": "d", "status": "planned", "done_criteria": ["x"] },
  { "id": "auth", "name": "D", "description": "d", "status": "planned", "done_criteria": ["x"] }
] }
JSON

# ---- default mode ----
node "$VALIDATE" "$UNIQUE" >/dev/null 2>&1
expect_exit "unique file passes" 0 "$?"

out=$(node "$VALIDATE" "$DUP" 2>&1); rc=$?
expect_exit "duplicate file rejected" 3 "$rc"
printf '%s' "$out" | grep -q "parser" && ok "names the duplicated id 'parser'" || bad "did not name 'parser' (got: $out)"
printf '%s' "$out" | grep -q "auth" && ok "names the duplicated id 'auth'" || bad "did not name 'auth'"

# ---- --check candidate mode ----
node "$VALIDATE" --check brand-new "$UNIQUE" >/dev/null 2>&1
expect_exit "--check free id passes" 0 "$?"

out=$(node "$VALIDATE" --check cli-parser "$UNIQUE" 2>&1); rc=$?
expect_exit "--check taken id rejected" 3 "$rc"
printf '%s' "$out" | grep -q "cli-parser-2" && ok "--check suggests a free id (cli-parser-2)" || bad "no suggestion (got: $out)"

# trailing -N suffix bumps rather than stacks
SUFFIXED="$TMP/suffixed.json"
cat > "$SUFFIXED" <<'JSON'
{ "project": "p", "features": [
  { "id": "parser", "name": "A", "description": "d", "status": "planned", "done_criteria": ["x"] },
  { "id": "parser-2", "name": "B", "description": "d", "status": "planned", "done_criteria": ["x"] }
] }
JSON
out=$(node "$VALIDATE" --check parser "$SUFFIXED" 2>&1)
printf '%s' "$out" | grep -q "parser-3" && ok "--check bumps past existing -N (suggests parser-3)" || bad "expected parser-3 suggestion (got: $out)"

# ---- error paths ----
node "$VALIDATE" "$TMP/missing.json" >/dev/null 2>&1
expect_exit "missing file (default) errors" 1 "$?"

node "$VALIDATE" --check anything "$TMP/missing.json" >/dev/null 2>&1
expect_exit "missing file (--check) is free" 0 "$?"

printf '{not json' > "$TMP/bad.json"
node "$VALIDATE" "$TMP/bad.json" >/dev/null 2>&1
expect_exit "invalid JSON errors" 1 "$?"

node "$VALIDATE" --check >/dev/null 2>&1
expect_exit "--check without id is a usage error" 1 "$?"

# ---- read-only: validating must not mutate the file ----
before=$(shasum "$DUP" | awk '{print $1}')
node "$VALIDATE" "$DUP" >/dev/null 2>&1 || true
after=$(shasum "$DUP" | awk '{print $1}')
if [ "$before" = "$after" ]; then ok "read-only (file byte-identical after run)"; else bad "validator mutated the file"; fi

echo ""
echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
