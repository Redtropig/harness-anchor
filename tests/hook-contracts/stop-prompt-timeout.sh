#!/usr/bin/env bash
# Contract test for the R1 self-timeout in hooks/stop and hooks/user-prompt-submit.
#
# Proves the TOTAL watchdog cap works on the two hooks that gained it in v0.18.0:
# when the JSON engine wedges, each hook exits 0 within ~6 seconds and emits
# nothing (no truncated JSON).
#
# Strategy:
#   1. Build a stub dir whose python3 / python / py / node all `sleep 30`
#   2. Put it FIRST on PATH, with /usr/bin already present so ha_platform_init's
#      Windows PATH shield is a no-op and cannot shadow the stubs
#   3. Run each hook; assert wall-clock ≤ 8s, exit 0, and empty-or-valid output
#
# Why the engine is the right thing to wedge: both hooks call ha_json_engine_init,
# which probes by RUNNING `python3 -c 'print(1)'`. That probe is the first forking
# call in each hook — if the watchdog does not cover it, nothing does. This test
# fails if ha_json_engine_init is ever moved back outside main().

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
. "$PLUGIN_ROOT/scripts/lib/portable.sh" 2>/dev/null || true

PASS=0
FAIL=0
ok()   { echo "  OK   $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

# ---- Stub dir: every engine in the chain hangs ----
STUB_DIR=$(mktemp -d)
FIXTURE=$(mktemp -d)
trap 'rm -rf "$STUB_DIR" "$FIXTURE"' EXIT

for eng in python3 python py node; do
    printf '#!/bin/sh\nsleep 30\n' > "$STUB_DIR/$eng"
    chmod +x "$STUB_DIR/$eng"
done

# Anchored fixture so the hooks get past their early "no project root" returns and
# actually reach the engine calls. Without this the test would pass vacuously.
cat > "$FIXTURE/feature_list.json" <<'EOF'
{ "project": "t", "features": [ { "id": "f1", "name": "F1", "description": "d",
  "status": "in-progress", "done_criteria": ["build"] } ] }
EOF
printf '# progress\n' > "$FIXTURE/progress.md"
printf '# handoff\n'  > "$FIXTURE/session-handoff.md"
# Backdate both so hooks/stop's staleness checks fire and it wants to emit.
touch -t 202001010000 "$FIXTURE/progress.md" "$FIXTURE/session-handoff.md" 2>/dev/null || true

# /usr/bin listed explicitly: ha_platform_init only prepends it when absent, so
# including it here keeps STUB_DIR in front on Git-Bash as well as POSIX.
WEDGED_PATH="$STUB_DIR:/usr/bin:$PATH"

run_timed() {  # $1=label  $2=hook path  $3=stdin payload
    _label="$1"; _hook="$2"; _stdin="$3"
    _t0=$(date +%s)
    # HA_JSON_ENGINE/HA_PY are cleared to empty STRINGS, not unset: portable.sh's
    # ha_json_engine_init short-circuits on `[ -n "${HA_JSON_ENGINE:-}" ]`, so an
    # empty value forces the re-probe this test depends on. Written `=''` rather
    # than the bare form, which is SC1007 at warning severity and so fails the
    # lint gate in CI. (Do not start a comment line with the linter's own name —
    # it is read as a directive and errors out. That is SC1072/SC1073.)
    _out=$(cd "$FIXTURE" && printf '%s' "$_stdin" \
        | PATH="$WEDGED_PATH" HA_JSON_ENGINE='' HA_PY='' \
          bash "$_hook" 2>/dev/null)
    _rc=$?
    _t1=$(date +%s)
    _elapsed=$((_t1 - _t0))

    if [ "$_rc" -eq 0 ]; then
        ok "$_label: exit 0 (warn-only, never blocks)"
    else
        fail "$_label: exit $_rc — a hook must never fail the event"
    fi

    # 8s, not 5s: 5s watchdog + process teardown + slow CI filesystems. The point is
    # that it is bounded well under the 30s the stub would take unguarded.
    if [ "$_elapsed" -le 8 ]; then
        ok "$_label: bounded at ${_elapsed}s (cap 5s + slack; unguarded would be 30s)"
    else
        fail "$_label: took ${_elapsed}s — watchdog did not fire"
    fi

    if [ -z "$_out" ]; then
        ok "$_label: emitted nothing on timeout (no truncated JSON)"
    else
        printf '%s' "$_out" | ha_json_valid
        case $? in
            0) ok   "$_label: emitted valid JSON" ;;
            2) echo "  SKIP $_label json-validity (no JSON engine)" ;;
            *) fail "$_label: emitted TRUNCATED output: $(printf '%s' "$_out" | head -c 120)" ;;
        esac
    fi
}

echo "=== hooks/stop under a wedged engine ==="
run_timed "stop" "$PLUGIN_ROOT/hooks/stop" ""

echo ""
echo "=== hooks/user-prompt-submit under a wedged engine ==="
run_timed "user-prompt-submit" "$PLUGIN_ROOT/hooks/user-prompt-submit" \
    '{"prompt":"by the way, could you also refactor the parser"}'

echo ""
echo "==================================="
echo " Pass: $PASS    Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
