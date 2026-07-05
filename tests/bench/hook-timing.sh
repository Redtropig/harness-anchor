#!/usr/bin/env bash
# hook-timing.sh — Wall-clock benchmark for the four warn-only hooks (P1).
#
# Complements scripts/measure-context.sh: that guards the *byte* budget
# (invariant #2, SessionStart ≤ 12000 chars); this guards the *time* budget
# (invariant #7, hooks ≤ 5s). Same e2e fixture harness, orthogonal axis.
#
# It bootstraps the e2e C/C++ fixture and invokes each hook the way Claude Code
# would — correct env vars / stdin / cwd, and inputs that drive each hook down its
# *active* (slow) path (an in-progress + a pass feature exist in the fixture).
#
# Thresholds (per the v0.2.1 plan, aligned with the R1 5s self-watchdog):
#   WARN at ≥ 2000 ms   early regression signal — does NOT fail CI
#   FAIL at ≥ 5000 ms   a hook this slow is hitting its own watchdog (invariant #7)
#
# Timing uses python3 epoch-ms (portable; `date +%s%N` is GNU-only, absent on macOS).
# Each measurement includes one python-startup (~tens of ms) of constant overhead,
# which is negligible against the second-scale thresholds and errs conservative.
#
# Usage: bash tests/bench/hook-timing.sh
# Exit 0 = all hooks under the FAIL threshold; 1 = at least one hook ≥ 5s.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WARN_MS=2000
FAIL_MS=5000

PASS=0
WARN=0
FAIL=0

now_ms() { python3 -c "import time; print(int(time.time()*1000))"; }

report() {
    local label="$1" ms="$2"
    if [ "$ms" -ge "$FAIL_MS" ]; then
        echo "  FAIL  ${label}: ${ms}ms (≥ ${FAIL_MS}ms — exceeds hook time budget)"
        FAIL=$((FAIL+1))
    elif [ "$ms" -ge "$WARN_MS" ]; then
        echo "  WARN  ${label}: ${ms}ms (≥ ${WARN_MS}ms)"
        WARN=$((WARN+1))
    else
        echo "  OK    ${label}: ${ms}ms"
        PASS=$((PASS+1))
    fi
}

echo "=== hook-timing benchmark ==="

# ---- Bootstrap the e2e fixture (reused harness) ----
FIXTURE_DIR=$(bash "$PLUGIN_ROOT/tests/e2e-cpp-fixture/bootstrap.sh" 2>/dev/null)
if [ -z "$FIXTURE_DIR" ] || [ ! -d "$FIXTURE_DIR" ]; then
    echo "  FAIL  bootstrap.sh did not produce a temp dir"
    echo "==================================="
    echo " STATUS: FAILED"
    exit 1
fi
trap 'rm -rf "$FIXTURE_DIR"' EXIT
echo "Fixture: $FIXTURE_DIR"
echo "Thresholds: warn ≥ ${WARN_MS}ms, fail ≥ ${FAIL_MS}ms"
echo ""

# ---- session-start (env-driven; no stdin) ----
s=$(now_ms)
CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$FIXTURE_DIR" \
    bash "$PLUGIN_ROOT/hooks/session-start" >/dev/null 2>&1 || true
e=$(now_ms)
report "session-start" $((e - s))

# ---- post-tool-use (stdin = Edit event on a fixture source file → regression-warn path) ----
pms_input=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/src/engine.cpp"}}' "$FIXTURE_DIR")
s=$(now_ms)
printf '%s' "$pms_input" | bash "$PLUGIN_ROOT/hooks/post-tool-use" >/dev/null 2>&1 || true
e=$(now_ms)
report "post-tool-use" $((e - s))

# ---- user-prompt-submit (stdin = scope-jump prompt; cwd inside fixture → active-feature path) ----
ups_input='{"prompt":"by the way, can you also refactor the CLI parser?"}'
s=$(now_ms)
( cd "$FIXTURE_DIR" && printf '%s' "$ups_input" | bash "$PLUGIN_ROOT/hooks/user-prompt-submit" >/dev/null 2>&1 ) || true
e=$(now_ms)
report "user-prompt-submit" $((e - s))

# ---- stop (no stdin; cwd inside fixture → in-progress reminder path) ----
s=$(now_ms)
( cd "$FIXTURE_DIR" && bash "$PLUGIN_ROOT/hooks/stop" >/dev/null 2>&1 ) || true
e=$(now_ms)
report "stop" $((e - s))

echo ""
echo "==================================="
echo " OK: $PASS    Warn: $WARN    Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo " STATUS: PASSED"
    exit 0
else
    echo " STATUS: FAILED"
    exit 1
fi
