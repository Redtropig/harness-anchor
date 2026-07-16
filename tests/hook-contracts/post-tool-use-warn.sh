#!/usr/bin/env bash
# Contract test for hooks/post-tool-use.
#
# Sets up a temp project with a feature_list.json containing a 'pass' feature,
# then invokes post-tool-use with a synthetic Edit event on a source file.
# Expects: hook stdout is valid JSON containing a 'Note:' regression warning.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# JSON validity via the shared engine chain (python3→python→py→node); rc=2 = no
# engine → honest SKIP, not a false FAIL on engine-less machines. (v0.13.0)
# shellcheck disable=SC1091
. "$PLUGIN_ROOT/scripts/lib/portable.sh" 2>/dev/null || true

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR" || exit 1
mkdir -p src

# Build a fixture project anchored with feature_list.json marking one feature pass.
cat > feature_list.json <<'EOF'
{
  "project": "fixture",
  "features": [
    {
      "id": "feat-a",
      "name": "Feature A",
      "description": "passed feature",
      "status": "pass",
      "done_criteria": ["build", "tests"],
      "evidence": {
        "timestamp": "2026-01-01T00:00:00Z",
        "commit": "abc123",
        "artifacts": [".build/build.log"]
      }
    }
  ]
}
EOF

echo 'int main(){return 0;}' > src/main.cpp

# Simulate Claude Code's PostToolUse stdin payload.
input_json=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/src/main.cpp"}}' "$TMPDIR")

# Run the hook.
output=$(printf '%s' "$input_json" | bash "$PLUGIN_ROOT/hooks/post-tool-use" 2>/dev/null || true)

PASS=0
FAIL=0

assert_contains() {
    if printf '%s' "$2" | grep -q "$1"; then
        echo "  OK   contains: $1"
        PASS=$((PASS+1))
    else
        echo "  FAIL missing: $1 (in: $(printf '%s' "$2" | head -c 200))"
        FAIL=$((FAIL+1))
    fi
}

assert_json_valid() {
    printf '%s' "$1" | ha_json_valid
    case $? in
        0) echo "  OK   valid JSON"; PASS=$((PASS+1)) ;;
        2) echo "  SKIP json-validity (no JSON engine on this machine)" ;;
        *) echo "  FAIL invalid JSON output: $(printf '%s' "$1" | head -c 200)"; FAIL=$((FAIL+1)) ;;
    esac
}

echo "=== post-tool-use contract test ==="
echo "Output (truncated):"
echo "${output:0:300}"
echo "---"

if [ -z "$output" ]; then
    echo "  FAIL no output emitted; expected warning for pass-feature edit"
    FAIL=$((FAIL+1))
else
    assert_json_valid "$output"
    assert_contains "hookSpecificOutput" "$output"
    assert_contains "PostToolUse" "$output"
    assert_contains "feat-a" "$output"
    assert_contains "/sanitize" "$output"
fi

# Negative test: editing a file in NON-anchored dir should produce no output.
TMPDIR2=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2"' EXIT
cd "$TMPDIR2" || exit 1
input_json2=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/foo.txt"}}' "$TMPDIR2")
output2=$(printf '%s' "$input_json2" | bash "$PLUGIN_ROOT/hooks/post-tool-use" 2>/dev/null || true)

echo ""
echo "=== negative test (no anchor) ==="
if [ -z "$output2" ]; then
    echo "  OK   silent for non-anchored project"
    PASS=$((PASS+1))
else
    echo "  FAIL expected silent, got: $(printf '%s' "$output2" | head -c 100)"
    FAIL=$((FAIL+1))
fi

# Duplicate feature-id test: editing feature_list.json with a colliding id must warn.
# Pins the post-tool-use hook (L3) to agree with feature-list-validate.mjs (L2).
TMPDIR3=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2" "$TMPDIR3"' EXIT
cat > "$TMPDIR3/feature_list.json" <<'EOF'
{
  "project": "fixture",
  "features": [
    { "id": "parser", "name": "P1", "description": "d", "status": "planned", "done_criteria": ["x"] },
    { "id": "parser", "name": "P2", "description": "d", "status": "in-progress", "done_criteria": ["x"] }
  ]
}
EOF
input_json3=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/feature_list.json"}}' "$TMPDIR3")
output3=$(printf '%s' "$input_json3" | bash "$PLUGIN_ROOT/hooks/post-tool-use" 2>/dev/null || true)

echo ""
echo "=== duplicate feature-id test ==="
if [ -z "$output3" ]; then
    echo "  FAIL no output emitted; expected duplicate-id warning"
    FAIL=$((FAIL+1))
else
    assert_json_valid "$output3"
    assert_contains "Duplicate feature id" "$output3"
    assert_contains "parser" "$output3"
fi

# Negative: a UNIQUE-id ledger edit must stay silent (no false dup warning).
cat > "$TMPDIR3/feature_list.json" <<'EOF'
{
  "project": "fixture",
  "features": [
    { "id": "parser", "name": "P1", "description": "d", "status": "in-progress", "done_criteria": ["x"] },
    { "id": "engine", "name": "E", "description": "d", "status": "planned", "done_criteria": ["x"] }
  ]
}
EOF
output4=$(printf '%s' "$input_json3" | bash "$PLUGIN_ROOT/hooks/post-tool-use" 2>/dev/null || true)
if printf '%s' "$output4" | grep -q "Duplicate feature id"; then
    echo "  FAIL unique ledger wrongly flagged as duplicate"
    FAIL=$((FAIL+1))
else
    echo "  OK   unique-id ledger edit is silent (no false dup warning)"
    PASS=$((PASS+1))
fi

echo ""
echo "==================================="
echo " Pass: $PASS    Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo " STATUS: PASSED"
    exit 0
else
    echo " STATUS: FAILED"
    exit 1
fi
