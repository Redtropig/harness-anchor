#!/usr/bin/env bash
# hook-timing.sh — Wall-clock benchmark for every warn-only hook (P1).
#
# The hooks are enumerated below, not globbed, because each needs its own env /
# stdin / cwd to reach its active path — a glob loop would run them all down their
# early-return path and measure nothing. Enumeration rots, so the list is guarded:
# the final check asserts the number benchmarked equals the number of hooks on
# disk and FAILS if it does not. That guard exists because the list had already
# rotted — hooks/pre-compact shipped in v0.15.0 and was never added, so the test
# for the 5s budget silently skipped a hook for three releases.
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
# Timing uses epoch-ms via the shared engine chain ($PYBIN→node→date; `date +%s%N`
# is GNU-only, absent on macOS/BSD).
# Each measurement includes one python-startup (~tens of ms) of constant overhead,
# which is negligible against the second-scale thresholds and errs conservative.
#
# Usage: bash tests/bench/hook-timing.sh
# Exit 0 = all hooks under the FAIL threshold; 1 = at least one hook ≥ 5s.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
. "$PLUGIN_ROOT/scripts/lib/portable.sh" 2>/dev/null || true
PYBIN=""
command -v ha_python >/dev/null 2>&1 && PYBIN=$(ha_python || true)

WARN_MS=2000
FAIL_MS=5000

PASS=0
WARN=0
FAIL=0

now_ms() {  # portable epoch-ms: $PYBIN (python3→python→py) → node → 1s date fallback
    if [ -n "$PYBIN" ]; then
        # shellcheck disable=SC2086
        $PYBIN -c "import time; print(int(time.time()*1000))"
    elif command -v node >/dev/null 2>&1; then
        node -e 'console.log(Date.now())'
    else
        echo $(( $(date +%s) * 1000 ))
    fi
}

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

# ---- pre-compact (stdin = PreCompact event; writes the forensics marker) ----
# A real transcript path is not needed: the hook stats whatever it is given and
# records the size, so a missing file exercises the same code path.
pc_input=$(printf '{"session_id":"bench","transcript_path":"%s/transcript.jsonl","cwd":"%s","hook_event_name":"PreCompact","trigger":"auto"}' "$FIXTURE_DIR" "$FIXTURE_DIR")
s=$(now_ms)
( cd "$FIXTURE_DIR" && printf '%s' "$pc_input" | bash "$PLUGIN_ROOT/hooks/pre-compact" >/dev/null 2>&1 ) || true
e=$(now_ms)
report "pre-compact" $((e - s))

# ---- Completeness guard: the enumeration above must cover every hook on disk ----
# Same discipline as tests/windows-compat.sh [0/5]: a benchmark that silently
# skips a hook reports all-green while the 5s budget goes unmeasured for it.
n_disk=$(find "$PLUGIN_ROOT/hooks" -maxdepth 1 -type f ! -name '*.json' ! -name '*.cmd' | grep -c .)
n_bench=$((PASS + WARN + FAIL))
if [ "$n_bench" -eq "$n_disk" ]; then
    echo "  OK    coverage: benchmarked $n_bench of $n_disk hook(s) on disk"
    PASS=$((PASS+1))
else
    echo "  FAIL  coverage: benchmarked $n_bench but $n_disk hook(s) exist — add the missing one(s) above"
    FAIL=$((FAIL+1))
fi

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
