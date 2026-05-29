#!/usr/bin/env bash
# Contract test for hooks/stop.
#
# Happy path: an in-progress feature surfaces a wrap-up reminder.
# Negative: non-anchored dir exits silently.

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

# ---- Happy path: anchored project with in-progress feature ----
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cd "$TMPDIR"

cat > feature_list.json <<'EOF'
{
  "project": "stop-test",
  "features": [
    {
      "id": "feat-active",
      "name": "Active Feature",
      "description": "still in progress",
      "status": "in-progress",
      "done_criteria": ["build"]
    }
  ]
}
EOF

# Make progress.md "stale" (older than 30 min) by backdating it.
cat > progress.md <<'EOF'
# Progress

## Session 2026-05-28
- Started feat-active
EOF
# Set mtime to 1 hour ago (requires touch -t, portable on macOS/Linux).
STALE_TIME=$(python3 -c "
import datetime, sys
t = datetime.datetime.now() - datetime.timedelta(hours=1)
print(t.strftime('%Y%m%d%H%M'))
")
touch -t "$STALE_TIME" progress.md 2>/dev/null || true

echo "=== stop hook (in-progress feature + stale progress) ==="
output=$(bash "$PLUGIN_ROOT/hooks/stop" 2>/dev/null || true)

if [ -z "$output" ]; then
    echo "  (no output — stop hook may have exited silently)"
    # This can happen if CWD isn't the feature_list.json dir in some edge cases.
    # Try with explicit cd.
    output=$(cd "$TMPDIR" && bash "$PLUGIN_ROOT/hooks/stop" 2>/dev/null || true)
fi

if [ -n "$output" ]; then
    assert_json_valid "$output"
    assert_contains "Stop" "$output"
    assert_contains "feat-active" "$output"
else
    fail "no output emitted; expected wrap-up reminder for in-progress feature"
fi

# ---- Negative: non-anchored dir ----
TMPDIR2=$(mktemp -d)
trap "rm -rf $TMPDIR $TMPDIR2" EXIT

echo ""
echo "=== stop hook (non-anchored) ==="
output2=$(cd "$TMPDIR2" && bash "$PLUGIN_ROOT/hooks/stop" 2>/dev/null || true)

if [ -z "$output2" ]; then
    ok "silent for non-anchored project"
else
    fail "expected silent, got: $(printf '%s' "$output2" | head -c 100)"
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
