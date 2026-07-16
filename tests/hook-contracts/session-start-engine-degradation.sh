#!/usr/bin/env bash
# Contract: session-start must not depend on python3 specifically.
#   Lane A (node-only): python3/python/py hidden, node present → banner still
#     shows the REAL plugin version and correct project type.
#   Lane B (no engines): all four hidden → banner still emitted; version still
#     real (bash tier greps our own plugin.json); active-feature line degrades
#     to "(needs python3 or node)"; cpp fixture still typed as cpp.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/session-start"

PASS=0; FAIL=0
ok()  { echo "  OK   $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
assert_contains() { case "$2" in *"$1"*) ok "contains: $1";; *) bad "missing: $1 (in: $(printf '%s' "$2" | head -c 200))";; esac; }

# Real version, extracted by the test itself (grep — independent of any engine).
REAL_VERSION=$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([0-9.]+)".*/\1/p' "$PLUGIN_ROOT/.claude-plugin/plugin.json" | head -1)
[ -n "$REAL_VERSION" ] || { echo "  FAIL cannot read plugin.json version"; exit 1; }

# Anchored fixture project with an in-progress feature + a C++ marker.
ROOT=$(mktemp -d); trap 'rm -rf "$ROOT" "$SHIM3" "$SHIM4"' EXIT
cat > "$ROOT/feature_list.json" <<'EOF'
{ "project": "fx", "features": [
  { "id": "feat-x", "name": "X", "description": "d", "status": "in-progress", "done_criteria": ["c"] }
] }
EOF
printf 'cmake_minimum_required(VERSION 3.20)\nproject(fx CXX)\n' > "$ROOT/CMakeLists.txt"
mkdir -p "$ROOT/src"; echo 'int main(){return 0;}' > "$ROOT/src/main.cpp"

mkshims() { local d="$1"; shift; local n; for n in "$@"; do printf '#!/bin/sh\nexit 127\n' > "$d/$n"; chmod +x "$d/$n"; done; }

echo "=== Lane A: python family hidden, node present ==="
SHIM3=$(mktemp -d); mkshims "$SHIM3" python3 python py
if command -v node >/dev/null 2>&1 && node -e 'console.log(1)' >/dev/null 2>&1; then
    outA=$(printf '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$ROOT" PATH="$SHIM3:$PATH" bash "$HOOK" 2>/dev/null || true)
    assert_contains "harness-anchor v$REAL_VERSION" "$outA"
    assert_contains "feat-x: X" "$outA"
    assert_contains "cpp (cmake" "$outA"
else
    echo "  SKIP lane A (no node on this machine)"
fi

echo "=== Lane B: all engines hidden ==="
SHIM4=$(mktemp -d); mkshims "$SHIM4" python3 python py node
outB=$(printf '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$ROOT" PATH="$SHIM4:$PATH" bash "$HOOK" 2>/dev/null || true)
[ -n "$outB" ] && ok "banner still emitted with zero engines" || bad "no output with zero engines"
assert_contains "harness-anchor v$REAL_VERSION" "$outB"
assert_contains "(needs python3 or node)" "$outB"
assert_contains "cpp (cmake" "$outB"

echo ""; echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
