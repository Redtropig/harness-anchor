#!/usr/bin/env bash
# Contract test for the SessionStart meta-skill slimming (v0.10.0).
#
# The injected body must be the SLIMMED form of using-harness-anchor/SKILL.md:
# no YAML frontmatter, no cpp-only marker text ever, cpp-only regions present
# exactly when cpp-detect says the project is C/C++ — and the un-skipped
# remainder must be intact (anchor sections survive), within the cap.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0; FAIL=0
ok()  { echo "  OK   $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

decode_ctx() {
    printf '%s' "$1" | python3 -c "import json,sys; print(json.load(sys.stdin).get('hookSpecificOutput',{}).get('additionalContext',''))" 2>/dev/null || true
}
run_hook() {
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$1" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true
}

G=""; C=""
trap 'rm -rf "$G" "$C"' EXIT

echo "=== generic project -> cpp-only regions + frontmatter NOT injected ==="
G=$(mktemp -d)
git -C "$G" init -q
printf 'x\n' > "$G/README.md"
ctx=$(decode_ctx "$(run_hook "$G")")
[ -n "$ctx" ] && ok "hook produced context" || bad "no context"
if printf '%s' "$ctx" | grep -q 'cpp-build-systems'; then bad "cpp sibling lines injected in generic"; else ok "no cpp sibling lines"; fi
if printf '%s' "$ctx" | grep -q '/cpp-init'; then bad "/cpp-init line injected in generic"; else ok "no /cpp-init line"; fi
if printf '%s' "$ctx" | grep -q '/sanitize'; then bad "/sanitize line injected in generic"; else ok "no /sanitize line"; fi
if printf '%s' "$ctx" | grep -q 'name: using-harness-anchor'; then bad "frontmatter injected"; else ok "frontmatter stripped"; fi
if printf '%s' "$ctx" | grep -q 'cpp-only'; then bad "marker text leaked"; else ok "no marker text"; fi
# Skip-leak guard: content AFTER each cpp-only region must survive the filter.
printf '%s' "$ctx" | grep -q '## Hard Rules' && ok "Hard Rules section present" || bad "Hard Rules missing (skip leak?)"
printf '%s' "$ctx" | grep -q '/session-end' && ok "commands after cpp regions present" || bad "post-region command lines missing (skip leak?)"
len=${#ctx}
if [ "$len" -le 12000 ]; then ok "context ${len} <= 12000"; else bad "context ${len} > 12000"; fi

echo ""
echo "=== cpp project -> cpp-only regions ARE injected, markers still absent ==="
C=$(mktemp -d)
git -C "$C" init -q
printf 'cmake_minimum_required(VERSION 3.16)\nproject(s CXX)\n' > "$C/CMakeLists.txt"
printf 'int main(){return 0;}\n' > "$C/main.cpp"
ctx=$(decode_ctx "$(run_hook "$C")")
printf '%s' "$ctx" | grep -q 'Project type:     cpp' && ok "fixture detected as cpp" || bad "fixture NOT detected as cpp — cpp assertions below are vacuous"
printf '%s' "$ctx" | grep -q 'cpp-build-systems' && ok "cpp sibling lines injected" || bad "cpp sibling lines missing"
printf '%s' "$ctx" | grep -q '/cpp-init' && ok "/cpp-init line injected" || bad "/cpp-init line missing"
printf '%s' "$ctx" | grep -q '/sanitize' && ok "/sanitize line injected" || bad "/sanitize line missing"
if printf '%s' "$ctx" | grep -q 'cpp-only'; then bad "marker text leaked (cpp mode)"; else ok "no marker text (cpp mode)"; fi
len=${#ctx}
if [ "$len" -le 12000 ]; then ok "context ${len} <= 12000"; else bad "context ${len} > 12000"; fi

echo ""
echo "==================================="
echo " Pass: $PASS    Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
