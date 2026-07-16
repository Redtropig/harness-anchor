#!/usr/bin/env bash
# Contract: post-tool-use must terminate promptly and behave correctly on
# Windows-shaped file paths. Windows path bugs are string bugs — lanes 1-2 run
# on every platform; lane 3 (real Windows path round-trip) runs where cygpath exists.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/post-tool-use"

PASS=0; FAIL=0
ok()  { echo "  OK   $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "=== Lane 1: forward-slash Windows path, non-existent → fast + silent ==="
SECONDS=0
out1=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"C:/nonexistent-hf-path/src/a.cpp"}}' | bash "$HOOK" 2>/dev/null || true)
d1=$SECONDS
[ -z "$out1" ] && ok "silent (no anchored root)" || bad "expected silence, got: $(printf '%s' "$out1" | head -c 120)"
[ "$d1" -lt 4 ] && ok "returned in ${d1}s (<4s — no watchdog burn)" || bad "took ${d1}s (walk-up burn back?)"

echo "=== Lane 2: backslash Windows path, non-existent → fast + silent ==="
SECONDS=0
out2=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"C:\\\\nonexistent-hf\\\\src\\\\a.cpp"}}' | bash "$HOOK" 2>/dev/null || true)
d2=$SECONDS
[ -z "$out2" ] && ok "silent (no anchored root)" || bad "expected silence, got: $(printf '%s' "$out2" | head -c 120)"
[ "$d2" -lt 4 ] && ok "returned in ${d2}s (<4s)" || bad "took ${d2}s"

echo "=== Lane 3: real Windows-form path round-trip (needs cygpath) ==="
if command -v cygpath >/dev/null 2>&1; then
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
    mkdir -p "$TMP/src"
    cat > "$TMP/feature_list.json" <<'EOF'
{ "project": "fx", "features": [
  { "id": "feat-w", "name": "W", "description": "d", "status": "pass",
    "done_criteria": ["c"],
    "evidence": { "timestamp": "2026-01-01T00:00:00Z", "commit": "abc", "artifacts": [".build/log"] } }
] }
EOF
    echo 'int main(){return 0;}' > "$TMP/src/main.cpp"
    winpath=$(cygpath -w "$TMP/src/main.cpp")
    winpath_json=${winpath//\\/\\\\}
    out3=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$winpath_json" | bash "$HOOK" 2>/dev/null || true)
    case "$out3" in
        *"feat-w"*) ok "backslash path resolved to anchored root (warning names feat-w)";;
        *) bad "no regression warning for Windows-form path (got: $(printf '%s' "$out3" | head -c 200))";;
    esac
else
    echo "  SKIP lane 3 (no cygpath — not a Windows Git Bash)"
fi

echo ""; echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
