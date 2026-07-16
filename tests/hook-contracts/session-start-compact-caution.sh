#!/usr/bin/env bash
# Contract test for hooks/session-start — compact-source caution line (v0.12.0).
#
# source=="compact" on stdin  -> banner carries the "Compact notice:" line.
# source=="startup"           -> no such line (zero regular-path increment).
# stdin at EOF (</dev/null)   -> hook still emits, no caution, no hang.
# stdin held open (no EOF)    -> bounded (~1s), still emits — pins the hang hazard.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# JSON validity via the shared engine chain (rc=2 = no engine → honest SKIP). (v0.13.0)
# shellcheck disable=SC1091
. "$PLUGIN_ROOT/scripts/lib/portable.sh" 2>/dev/null || true

# Millisecond clock (portable): python3 → node → 1s-resolution date fallback.
# The stdin-boundedness assertion below needs sub-second resolution — the old
# integer `date +%s` rounded a legitimate ~2.5s Windows run across the 3s bound.
_now_ms() {
    if command -v python3 >/dev/null 2>&1 && python3 -c 'print(1)' >/dev/null 2>&1; then
        python3 -c 'import time; print(int(time.time()*1000))'
    elif command -v node >/dev/null 2>&1; then
        node -e 'console.log(Date.now())'
    else
        echo $(( $(date +%s) * 1000 ))
    fi
}

PASS=0; FAIL=0
assert_contains() {
    if printf '%s' "$2" | grep -q "$1"; then
        echo "  OK   contains: $1"; PASS=$((PASS+1))
    else
        echo "  FAIL missing: $1 (in: $(printf '%s' "$2" | head -c 200))"; FAIL=$((FAIL+1))
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

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR" || exit 1
printf '{ "project": "compact-test", "features": [] }\n' > feature_list.json

echo "=== session-start (source=compact → caution line) ==="
output=$(printf '{"source":"compact","session_id":"s1"}' \
    | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$TMPDIR" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true)
if [ -z "$output" ]; then
    echo "  FAIL no output emitted"; FAIL=$((FAIL+1))
else
    assert_json_valid "$output"
    assert_contains "Compact notice:" "$output"
    assert_contains "on-disk evidence" "$output"
fi

echo ""
echo "=== session-start (source=startup → NO caution line) ==="
output2=$(printf '{"source":"startup","session_id":"s1"}' \
    | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$TMPDIR" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true)
if printf '%s' "$output2" | grep -q "Compact notice:"; then
    echo "  FAIL caution line present on source=startup"; FAIL=$((FAIL+1))
else
    echo "  OK   no caution line on regular startup"; PASS=$((PASS+1))
fi

echo ""
echo "=== session-start (stdin at EOF → still emits, no caution, no hang) ==="
output3=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$TMPDIR" bash "$PLUGIN_ROOT/hooks/session-start" </dev/null 2>/dev/null || true)
if [ -z "$output3" ]; then
    echo "  FAIL no output emitted on stdin-less invocation"; FAIL=$((FAIL+1))
else
    assert_json_valid "$output3"
    if printf '%s' "$output3" | grep -q "Compact notice:"; then
        echo "  FAIL caution line present without stdin"; FAIL=$((FAIL+1))
    else
        echo "  OK   stdin-less invocation clean"; PASS=$((PASS+1))
    fi
fi

echo ""
echo "=== session-start (stdin held open, no EOF → bounded, still emits) ==="
t0=$(_now_ms)
output4=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$TMPDIR" \
    bash "$PLUGIN_ROOT/hooks/session-start" < <(printf '{"source":"startup","session_id":"s1"}'; sleep 3) 2>/dev/null || true)
t1=$(_now_ms)
if [ -n "$output4" ]; then
    echo "  OK   emits despite held-open stdin"; PASS=$((PASS+1))
else
    echo "  FAIL no output with held-open stdin"; FAIL=$((FAIL+1))
fi
# The correct read -t 1 path returns at ~1s + work; a hung (no-timeout) read
# would wait for pipe close (sleep 3) + work. 3500ms is the midpoint — robust to
# Windows subprocess-spawn slowness (~2.5s legitimate run) yet still well below
# the ~4.5s a hang would take. (v0.13.0: was an integer `-lt 3`s bound that flaked.)
elapsed_ms=$(( t1 - t0 ))
if [ "$elapsed_ms" -lt 3500 ]; then
    echo "  OK   bounded: ${elapsed_ms}ms < 3500ms (did not wait for pipe close)"; PASS=$((PASS+1))
else
    echo "  FAIL unbounded stdin wait: ${elapsed_ms}ms"; FAIL=$((FAIL+1))
fi

echo ""
echo "==================================="
echo " Pass: $PASS    Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
