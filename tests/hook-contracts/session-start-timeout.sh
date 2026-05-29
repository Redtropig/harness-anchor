#!/usr/bin/env bash
# Contract test for hooks/session-start self-timeout (R1).
#
# Proves the TOTAL watchdog cap works: when a sub-command hangs, session-start
# exits 0 within ~6 seconds and emits nothing (no truncated JSON).
#
# Strategy:
#   1. Temporarily replace scripts/cpp-detect.sh with a sleep-10 stub
#   2. Also shadow timeout/gtimeout from PATH (disable the per-command shim)
#   3. Verify wall-clock ≤ 6s AND output is empty or valid JSON (no truncation)
#   4. Restore original cpp-detect.sh via trap cleanup

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0

ok()   { echo "  OK   $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

# ---- Back up the real cpp-detect.sh ----
REAL_DETECT="$PLUGIN_ROOT/scripts/cpp-detect.sh"
BACKUP_DETECT="$PLUGIN_ROOT/scripts/cpp-detect.sh.bak"

if [ ! -f "$REAL_DETECT" ]; then
    echo "  SKIP cpp-detect.sh not found — cannot test timeout"
    echo "==================================="
    echo " Pass: 0    Fail: 0"
    echo " STATUS: SKIPPED"
    exit 0
fi

cp "$REAL_DETECT" "$BACKUP_DETECT"

cleanup() {
    # Restore original cpp-detect.sh
    mv "$BACKUP_DETECT" "$REAL_DETECT" 2>/dev/null || true
    rm -rf "$TMPDIR" "$NO_TIMEOUT_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Replace with a stub that sleeps for 10 seconds
cat > "$REAL_DETECT" <<'STUB'
#!/usr/bin/env bash
sleep 10
echo '{"is_cpp_project":false,"build_system":"none"}'
STUB
chmod +x "$REAL_DETECT"

# ---- Create a PATH that shadows timeout/gtimeout (disable per-command shim) ----
NO_TIMEOUT_DIR=$(mktemp -d)

# no-op timeout wrapper: runs the command with no time limit.
# Strip ONLY a leading numeric duration (the "3" in `timeout 3 bash script`),
# then exec the rest verbatim. (The old `shift; shift` also dropped the command
# word and only worked incidentally because the script was directly executable.)
cat > "$NO_TIMEOUT_DIR/timeout" <<'NOOP'
#!/usr/bin/env bash
case "${1:-}" in
    [0-9]*) shift ;;
esac
exec "$@"
NOOP
chmod +x "$NO_TIMEOUT_DIR/timeout"
cp "$NO_TIMEOUT_DIR/timeout" "$NO_TIMEOUT_DIR/gtimeout"

export PATH="$NO_TIMEOUT_DIR:$PATH"

# ---- Set up a temp project ----
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
git init -q
git config user.email test@example.com
git config user.name test

cat > feature_list.json <<'EOF'
{
  "project": "timeout-test",
  "features": []
}
EOF
git add -A && git commit -qm "init" 2>/dev/null || true

echo "=== session-start self-timeout test ==="
echo "  (cpp-detect stub will sleep 10s; total watchdog must cap at ~5s)"

start_ms=$(python3 -c "import time; print(int(time.time()*1000))")
output=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$TMPDIR" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true)
end_ms=$(python3 -c "import time; print(int(time.time()*1000))")

elapsed_ms=$(( end_ms - start_ms ))
elapsed_s=$(( elapsed_ms / 1000 ))

echo "  Wall-clock: ${elapsed_s}s (${elapsed_ms}ms)"

# The total watchdog is 5s; allow up to 6s for process overhead.
if [ "$elapsed_s" -le 6 ]; then
    ok "completed within 6s (elapsed: ${elapsed_s}s)"
else
    fail "took >6s (elapsed: ${elapsed_s}s) — total watchdog may not be working"
fi

# On timeout, the hook should emit nothing (no truncated JSON).
if [ -z "$output" ]; then
    ok "no output on timeout (correct — avoids truncated JSON)"
else
    # If there IS output, it must be valid JSON (not truncated).
    if printf '%s' "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        ok "output is valid JSON even under timeout"
    else
        fail "output is truncated/invalid JSON — this is the partial-JSON pitfall"
    fi
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
