#!/usr/bin/env bash
# Contract test for hooks/post-tool-use — context-fill flush sentinel (v0.12.0, Check 1d).
#
# transcript over threshold   -> ONE flush reminder (additionalContext) + marker written
# second call, marker present -> silent (warn-once)
# transcript under threshold  -> silent, no marker
# no transcript_path field    -> silent
# stdin held open (no EOF)    -> bounded, still silent — pins the hang/lag hazards.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0; FAIL=0
assert_contains() {
    if printf '%s' "$2" | grep -q "$1"; then
        echo "  OK   contains: $1"; PASS=$((PASS+1))
    else
        echo "  FAIL missing: $1 (in: $(printf '%s' "$2" | head -c 200))"; FAIL=$((FAIL+1))
    fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR" || exit 1

# Anchored fixture with NO pass features and a NON-source file target: every other
# post-tool-use check stays silent, so any output is attributable to Check 1d.
printf '{ "project": "flush-fixture", "features": [] }\n' > feature_list.json
echo 'body' > notes.txt

# Threshold read from the hook itself — the test must not drift from the constant.
THRESH=$(sed -n 's/^FLUSH_THRESHOLD_BYTES=\([0-9]*\).*/\1/p' "$PLUGIN_ROOT/hooks/post-tool-use")
[ -n "$THRESH" ] || THRESH=6291456

transcript="$TMPDIR/transcript.jsonl"
# Engine-free fixture write (v0.13.0): a python3 -c "open('$transcript',...)" here
# fails on Windows — a native-Windows interpreter can't open the MSYS-style path
# embedded in the -c string (the same trap the hooks avoid via stdin/argv).
head -c "$((THRESH + 1024))" /dev/zero | tr '\0' 'x' > "$transcript"

mkjson() { # $1 = transcript path ("" omits the field entirely)
    if [ -n "$1" ]; then
        printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/notes.txt"},"transcript_path":"%s","session_id":"sess-flush-1"}' "$TMPDIR" "$1"
    else
        printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/notes.txt"}}' "$TMPDIR"
    fi
}

echo "=== over threshold → flush reminder fires once ==="
out1=$(mkjson "$transcript" | bash "$PLUGIN_ROOT/hooks/post-tool-use" 2>/dev/null || true)
if [ -z "$out1" ]; then
    echo "  FAIL no output; expected flush reminder"; FAIL=$((FAIL+1))
else
    assert_contains "Context is filling" "$out1"
    assert_contains "flush it to disk" "$out1"
    assert_contains "additionalContext" "$out1"
fi
if [ -f "$TMPDIR/.harness-anchor/flush-warned-sess-flush-1" ]; then
    echo "  OK   warn-once marker written"; PASS=$((PASS+1))
else
    echo "  FAIL marker not written"; FAIL=$((FAIL+1))
fi

echo ""
echo "=== second call with marker present → silent ==="
out2=$(mkjson "$transcript" | bash "$PLUGIN_ROOT/hooks/post-tool-use" 2>/dev/null || true)
if printf '%s' "$out2" | grep -q "Context is filling"; then
    echo "  FAIL repeated flush reminder (warn-once broken)"; FAIL=$((FAIL+1))
else
    echo "  OK   warn-once respected"; PASS=$((PASS+1))
fi

echo ""
echo "=== under threshold → silent, no marker ==="
rm -rf "$TMPDIR/.harness-anchor"
small="$TMPDIR/small.jsonl"; printf 'tiny' > "$small"
out3=$(mkjson "$small" | bash "$PLUGIN_ROOT/hooks/post-tool-use" 2>/dev/null || true)
if printf '%s' "$out3" | grep -q "Context is filling"; then
    echo "  FAIL fired under threshold"; FAIL=$((FAIL+1))
else
    echo "  OK   silent under threshold"; PASS=$((PASS+1))
fi
if [ -e "$TMPDIR/.harness-anchor/flush-warned-sess-flush-1" ]; then
    echo "  FAIL marker written under threshold"; FAIL=$((FAIL+1))
else
    echo "  OK   no marker under threshold"; PASS=$((PASS+1))
fi

echo ""
echo "=== no transcript_path field → silent ==="
out4=$(mkjson "" | bash "$PLUGIN_ROOT/hooks/post-tool-use" 2>/dev/null || true)
if printf '%s' "$out4" | grep -q "Context is filling"; then
    echo "  FAIL fired without transcript_path"; FAIL=$((FAIL+1))
else
    echo "  OK   silent without transcript_path"; PASS=$((PASS+1))
fi

echo ""
echo "=== stdin held open (no EOF) → bounded, still silent ==="
# Millisecond clock (portable): integer date+%s flaked a legitimate ~2.5s Windows
# run across the old 3s bound; sub-second resolution + a 3500ms midpoint (correct
# read -t 1 path ≈ 2.5s, a hung read ≈ sleep 3 + work ≈ 4.5s) is stable. (v0.13.0)
_now_ms() {
    if command -v python3 >/dev/null 2>&1 && python3 -c 'print(1)' >/dev/null 2>&1; then
        python3 -c 'import time; print(int(time.time()*1000))'
    elif command -v node >/dev/null 2>&1; then
        node -e 'console.log(Date.now())'
    else
        echo $(( $(date +%s) * 1000 ))
    fi
}
t0=$(_now_ms)
out5=$(bash "$PLUGIN_ROOT/hooks/post-tool-use" < <(mkjson "$small"; sleep 3) 2>/dev/null || true)
t1=$(_now_ms)
elapsed_ms=$(( t1 - t0 ))
if [ "$elapsed_ms" -lt 3500 ]; then
    echo "  OK   bounded: ${elapsed_ms}ms < 3500ms (did not wait for pipe close)"; PASS=$((PASS+1))
else
    echo "  FAIL unbounded stdin wait: ${elapsed_ms}ms"; FAIL=$((FAIL+1))
fi
if printf '%s' "$out5" | grep -q "Context is filling"; then
    echo "  FAIL fired under threshold (held-open)"; FAIL=$((FAIL+1))
else
    echo "  OK   still silent under threshold (held-open)"; PASS=$((PASS+1))
fi

echo ""
echo "==================================="
echo " Pass: $PASS    Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
