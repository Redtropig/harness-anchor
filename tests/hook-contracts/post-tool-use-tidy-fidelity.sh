#!/usr/bin/env bash
# Contract test for hooks/post-tool-use — Check 2 signal fidelity.
#
# 1. Fatal-parse case: stub clang-tidy emits clang-diagnostic-error + garbage warning →
#    hook must emit ONE honest line and suppress the garbage.
# 2. Normal case: stub emits a real warning → hook passes it through + skill-pointer tail.
# 3. Clean case: stub emits nothing → hook stays silent.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR" || exit 1
mkdir -p src bin

# Anchored fixture with an in-progress feature (keeps Check 1/1b/1c silent for Edit).
cat > feature_list.json <<'EOF'
{
  "project": "fixture",
  "features": [
    { "id": "feat-a", "name": "A", "description": "d", "status": "in-progress", "done_criteria": ["x"] }
  ]
}
EOF
echo 'int main(){return 0;}' > src/main.cpp
echo '[]' > compile_commands.json

input_json=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/src/main.cpp"}}' "$TMPDIR")

PASS=0; FAIL=0
assert_contains() {
    if printf '%s' "$2" | grep -q "$1"; then
        echo "  OK   contains: $1"; PASS=$((PASS+1))
    else
        echo "  FAIL missing: $1 (in: $(printf '%s' "$2" | head -c 200))"; FAIL=$((FAIL+1))
    fi
}
assert_not_contains() {
    if printf '%s' "$2" | grep -q "$1"; then
        echo "  FAIL should NOT contain: $1"; FAIL=$((FAIL+1))
    else
        echo "  OK   absent: $1"; PASS=$((PASS+1))
    fi
}
assert_json_valid() {
    if printf '%s' "$1" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        echo "  OK   valid JSON"; PASS=$((PASS+1))
    else
        echo "  FAIL invalid JSON: $(printf '%s' "$1" | head -c 200)"; FAIL=$((FAIL+1))
    fi
}

run_hook() { printf '%s' "$input_json" | bash "$PLUGIN_ROOT/hooks/post-tool-use" 2>/dev/null || true; }

echo "=== fatal-parse case (unparseable TU) ==="
cat > bin/clang-tidy <<'EOF'
#!/usr/bin/env bash
echo "src/main.cpp:1:10: error: 'atomic' file not found [clang-diagnostic-error]"
echo "src/main.cpp:2:5: warning: variable 'x' can be declared 'const' [misc-const-correctness]"
exit 1
EOF
chmod +x bin/clang-tidy
output=$(PATH="$TMPDIR/bin:$PATH" run_hook)
if [ -z "$output" ]; then
    echo "  FAIL no output; expected one honest fidelity line"; FAIL=$((FAIL+1))
else
    assert_json_valid "$output"
    assert_contains "could not fully parse" "$output"
    assert_contains "diagnostics suppressed" "$output"
    assert_not_contains "misc-const-correctness" "$output"
fi

echo ""
echo "=== normal-warning case (parseable TU) ==="
cat > bin/clang-tidy <<'EOF'
#!/usr/bin/env bash
echo "src/main.cpp:1:1: warning: use auto when initializing with a cast [modernize-use-auto]"
exit 0
EOF
chmod +x bin/clang-tidy
output=$(PATH="$TMPDIR/bin:$PATH" run_hook)
if [ -z "$output" ]; then
    echo "  FAIL no output; expected clang-tidy warning passthrough"; FAIL=$((FAIL+1))
else
    assert_json_valid "$output"
    assert_contains "modernize-use-auto" "$output"
    assert_contains "self-correction-loop" "$output"
    assert_not_contains "could not fully parse" "$output"
fi

echo ""
echo "=== clean case (no diagnostics) ==="
cat > bin/clang-tidy <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x bin/clang-tidy
output=$(PATH="$TMPDIR/bin:$PATH" run_hook)
if [ -z "$output" ]; then
    echo "  OK   silent on clean lint"; PASS=$((PASS+1))
else
    echo "  FAIL expected silence, got: $(printf '%s' "$output" | head -c 150)"; FAIL=$((FAIL+1))
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
