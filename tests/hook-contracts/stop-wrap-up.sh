#!/usr/bin/env bash
# Contract test for hooks/stop.
#
# Happy path: an in-progress feature surfaces a wrap-up reminder.
# Negative: non-anchored dir exits silently.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Shared engine chain: JSON validity (rc=2 → SKIP) + $PYBIN for python payloads. (v0.13.0)
# shellcheck disable=SC1091
. "$PLUGIN_ROOT/scripts/lib/portable.sh" 2>/dev/null || true
PYBIN=""
command -v ha_python >/dev/null 2>&1 && PYBIN=$(ha_python || true)

PASS=0
FAIL=0

ok()   { echo "  OK   $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

assert_json_valid() {
    printf '%s' "$1" | ha_json_valid
    case $? in
        0) echo "  OK   valid JSON"; PASS=$((PASS+1)) ;;
        2) echo "  SKIP json-validity (no JSON engine on this machine)" ;;
        *) echo "  FAIL invalid JSON output: $(printf '%s' "$1" | head -c 200)"; FAIL=$((FAIL+1)) ;;
    esac
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

# Validate against Claude Code's ACTUAL Stop-event output schema. The Stop event
# accepts only top-level fields (NO hookSpecificOutput channel), and harness-anchor
# is warn-only, so no blocking fields (stopReason / decision:block / permissionDecision:deny).
# This is the assertion that would have caught the hookSpecificOutput regression.
assert_valid_stop_schema() {
    if [ -z "$PYBIN" ]; then echo "  SKIP warn-only Stop schema (needs python)"; return 0; fi
    # shellcheck disable=SC2086
    if $PYBIN -c '
import json, sys
d = json.loads(sys.argv[1])
allowed = {"continue", "suppressOutput", "stopReason", "decision", "reason",
           "systemMessage", "terminalSequence", "permissionDecision"}
assert set(d).issubset(allowed), "unexpected Stop keys: %s" % (set(d) - allowed)
assert "hookSpecificOutput" not in d, "Stop event has no hookSpecificOutput channel"
assert "stopReason" not in d, "warn-only: must not set stopReason"
assert d.get("decision") != "block", "warn-only: must not block the stop"
assert d.get("permissionDecision") != "deny", "warn-only: must not deny"
' "$1" 2>/dev/null; then
        echo "  OK   valid warn-only Stop schema"
        PASS=$((PASS+1))
    else
        echo "  FAIL invalid Stop schema: $(printf '%s' "$1" | head -c 200)"
        FAIL=$((FAIL+1))
    fi
}

# ---- Happy path: anchored project with in-progress feature ----
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR" || exit 1

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
if [ -n "$PYBIN" ]; then
    # shellcheck disable=SC2086
    STALE_TIME=$($PYBIN -c "import datetime; print((datetime.datetime.now()-datetime.timedelta(hours=1)).strftime('%Y%m%d%H%M'))")
else
    # Portable fallback (GNU then BSD date) — keeps the staleness scenario meaningful
    # without python. (v0.13.0)
    STALE_TIME=$(date -d '1 hour ago' +%Y%m%d%H%M 2>/dev/null || date -v-1H +%Y%m%d%H%M 2>/dev/null || echo "")
fi
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
    assert_valid_stop_schema "$output"
    assert_contains "systemMessage" "$output"
    assert_contains "feat-active" "$output"
    assert_contains "flush it to disk" "$output"
else
    fail "no output emitted; expected wrap-up reminder for in-progress feature"
fi

# ---- Negative: non-anchored dir ----
TMPDIR2=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2"' EXIT

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
