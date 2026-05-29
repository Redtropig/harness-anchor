#!/usr/bin/env bash
# Contract test for hooks/user-prompt-submit.
#
# Happy path: scope-jump keyword + active feature triggers warning.
# Negative: benign prompt stays silent.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0

ok()   { echo "  OK   $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

assert_json_valid() {
    if printf '%s' "$1" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        echo "  OK   valid JSON"
        PASS=$((PASS+1))
    else
        echo "  FAIL invalid JSON output: $(printf '%s' "$1" | head -c 200)"
        FAIL=$((FAIL+1))
    fi
}

assert_contains() {
    if printf '%s' "$2" | grep -q "$1"; then
        echo "  OK   contains: $1"
        PASS=$((PASS+1))
    else
        echo "  FAIL missing: $1 (in: $(printf '%s' "$2" | head -c 200))"
        FAIL=$((FAIL+1))
    fi
}

# ---- Set up anchored project with in-progress feature ----
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cd "$TMPDIR"

cat > feature_list.json <<'EOF'
{
  "project": "scope-test",
  "features": [
    {
      "id": "feat-current",
      "name": "Current Feature",
      "description": "in-progress",
      "status": "in-progress",
      "done_criteria": ["build"]
    }
  ]
}
EOF

# ---- Happy path: scope-jump keyword ----
echo "=== user-prompt-submit (scope-jump keyword) ==="
scope_input='{"prompt":"Can you also add a login page?"}'
output=$(printf '%s' "$scope_input" | bash "$PLUGIN_ROOT/hooks/user-prompt-submit" 2>/dev/null || true)

if [ -n "$output" ]; then
    assert_json_valid "$output"
    assert_contains "UserPromptSubmit" "$output"
    assert_contains "feat-current" "$output"
else
    fail "no output emitted; expected scope-jump warning"
fi

# ---- Happy path: Chinese scope-jump keyword ----
echo ""
echo "=== user-prompt-submit (Chinese scope-jump keyword) ==="
cn_input='{"prompt":"顺便帮我修一下那个bug"}'
output2=$(printf '%s' "$cn_input" | bash "$PLUGIN_ROOT/hooks/user-prompt-submit" 2>/dev/null || true)

if [ -n "$output2" ]; then
    assert_json_valid "$output2"
    assert_contains "feat-current" "$output2"
else
    fail "no output emitted for Chinese scope-jump keyword"
fi

# ---- Negative: benign prompt ----
echo ""
echo "=== user-prompt-submit (benign prompt) ==="
benign_input='{"prompt":"Continue implementing the parser for feat-current"}'
output3=$(printf '%s' "$benign_input" | bash "$PLUGIN_ROOT/hooks/user-prompt-submit" 2>/dev/null || true)

if [ -z "$output3" ]; then
    ok "silent for benign prompt"
else
    fail "expected silent for benign prompt, got: $(printf '%s' "$output3" | head -c 100)"
fi

# ---- Negative: no active feature ----
TMPDIR2=$(mktemp -d)
trap "rm -rf $TMPDIR $TMPDIR2" EXIT
cd "$TMPDIR2"

cat > feature_list.json <<'EOF'
{
  "project": "no-active",
  "features": [
    {
      "id": "feat-done",
      "name": "Done Feature",
      "description": "already passed",
      "status": "pass",
      "done_criteria": ["build"],
      "evidence": {"timestamp":"2026-01-01T00:00:00Z","commit":"abc123","artifacts":[]}
    }
  ]
}
EOF

echo ""
echo "=== user-prompt-submit (scope keyword but no active feature) ==="
no_active_input='{"prompt":"Also fix the footer"}'
output4=$(printf '%s' "$no_active_input" | bash "$PLUGIN_ROOT/hooks/user-prompt-submit" 2>/dev/null || true)

if [ -z "$output4" ]; then
    ok "silent when no in-progress feature"
else
    fail "expected silent when no active feature, got: $(printf '%s' "$output4" | head -c 100)"
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
