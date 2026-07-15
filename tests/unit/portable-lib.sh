#!/usr/bin/env bash
# Unit test for scripts/lib/portable.sh — engine chain (incl. degradation via
# PATH shims), path normalization, fixed-point project-root walk, escaping.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$PLUGIN_ROOT/scripts/lib/portable.sh"

PASS=0; FAIL=0
ok()  { echo "  OK   $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1${2:+ → got '$2'}"; FAIL=$((FAIL+1)); }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2 (want $3)"; fi; }

[ -f "$LIB" ] || { echo "  FAIL lib missing: $LIB"; echo " STATUS: FAILED"; exit 1; }
# shellcheck disable=SC1090
. "$LIB"

# ---- normalization ----
expect_eq "backslashes"        "$(ha_normalize_path 'C:\Users\x\proj\a.cpp')" "C:/Users/x/proj/a.cpp"
expect_eq "already forward"    "$(ha_normalize_path '/tmp/x/y')" "/tmp/x/y"
expect_eq "mixed"              "$(ha_normalize_path 'C:/Users\x')" "C:/Users/x"

# ---- fixed-point walk-up ----
ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/proj/src/deep"
: > "$ROOT/proj/feature_list.json"
expect_eq "walk finds root"    "$(ha_find_project_root "$ROOT/proj/src/deep")" "$ROOT/proj"
if ha_find_project_root "/nonexistent-hf-$$/a/b" >/dev/null; then
    bad "walk no-match should fail"
else
    ok "walk no-match exits 1"
fi
# Windows-shaped path on any platform: must TERMINATE fast (fixed point), no match.
start=$(date +%s)
ha_find_project_root 'C:/no-such-drive-path/x/y' >/dev/null 2>&1 || true
ha_find_project_root 'C:\no-such\win\path' >/dev/null 2>&1 || true
end=$(date +%s)
if [ $((end - start)) -le 2 ]; then ok "windows-shaped walk terminates fast"; else bad "windows-shaped walk too slow ($((end-start))s)"; fi

# ---- engine chain: whatever engine this machine has ----
ha_json_engine_init
echo "  (engine on this machine: $HA_JSON_ENGINE)"
if [ "$HA_JSON_ENGINE" != "none" ]; then
    expect_eq "field string"   "$(printf '{"a":{"b":"v1"},"source":"compact"}' | ha_json_field a.b)" "v1"
    expect_eq "field top"      "$(printf '{"a":{"b":"v1"},"source":"compact"}' | ha_json_field source)" "compact"
    expect_eq "field bool"     "$(printf '{"is_cpp_project": true}' | ha_json_field is_cpp_project)" "true"
    expect_eq "field missing"  "$(printf '{"a":1}' | ha_json_field nope)" ""
    expect_eq "escape"         "$(printf 'a"b\\c' | ha_json_escape)" 'a\"b\\c'
    printf '{"x":1}' | ha_json_valid && ok "valid json" || bad "valid json"
    if printf 'not json' | ha_json_valid; then bad "invalid json accepted"; else ok "invalid json rejected"; fi
    multi=$(printf '{"tool_name":"Write","transcript_path":"/t/p.jsonl","session_id":"s-1"}' | ha_json_fields tool_name transcript_path session_id)
    expect_eq "fields line1"   "$(printf '%s\n' "$multi" | sed -n 1p)" "Write"
    expect_eq "fields line2"   "$(printf '%s\n' "$multi" | sed -n 2p)" "/t/p.jsonl"
    expect_eq "fields line3"   "$(printf '%s\n' "$multi" | sed -n 3p)" "s-1"
fi

# ---- windows-path payload through the field extractor (backslash unescape) ----
if [ "$HA_JSON_ENGINE" != "none" ]; then
    win=$(printf '{"tool_input":{"file_path":"C:\\\\Users\\\\x\\\\a.cpp"}}' | ha_json_field tool_input.file_path)
    expect_eq "win path extract" "$(ha_normalize_path "$win")" "C:/Users/x/a.cpp"
fi

# ---- degradation lanes via PATH shims ----
make_shims() { # $1=dir, then names... — each shim fails (simulates broken/missing tool)
    local d="$1"; shift
    local n; for n in "$@"; do printf '#!/bin/sh\nexit 127\n' > "$d/$n"; chmod +x "$d/$n"; done
}
SHIM=$(mktemp -d)
make_shims "$SHIM" python3 python py
( # subshell: engine re-detection under shimmed PATH
  PATH="$SHIM:$PATH"; unset HA_JSON_ENGINE HA_PY
  # shellcheck disable=SC1090
  . "$LIB"; ha_json_engine_init
  if command -v node >/dev/null 2>&1 && node -e 'console.log(1)' >/dev/null 2>&1; then
      [ "$HA_JSON_ENGINE" = "node" ] && echo "  OK   chain falls to node" || { echo "  FAIL chain expected node, got $HA_JSON_ENGINE"; exit 9; }
      v=$(printf '{"version":"9.9.9"}' | ha_json_field version)
      [ "$v" = "9.9.9" ] && echo "  OK   node-tier field" || { echo "  FAIL node-tier field → '$v'"; exit 9; }
  fi
) || FAIL=$((FAIL+1))
ALLSHIM=$(mktemp -d)
make_shims "$ALLSHIM" python3 python py node
( PATH="$ALLSHIM:$PATH"; unset HA_JSON_ENGINE HA_PY
  # shellcheck disable=SC1090
  . "$LIB"; ha_json_engine_init
  [ "$HA_JSON_ENGINE" = "none" ] && echo "  OK   chain exhausts to none" || { echo "  FAIL expected none, got $HA_JSON_ENGINE"; exit 9; }
  # bash tier still extracts our controlled formats:
  v=$(printf '{"version":"0.13.0"}' | ha_json_field version)
  [ "$v" = "0.13.0" ] && echo "  OK   bash-tier version" || { echo "  FAIL bash-tier version → '$v'"; exit 9; }
  c=$(printf '{"is_cpp_project": true,"build_system":"cmake"}' | ha_json_field build_system)
  [ "$c" = "cmake" ] && echo "  OK   bash-tier string" || { echo "  FAIL bash-tier string → '$c'"; exit 9; }
  b=$(printf '{"is_cpp_project": true,"build_system":"cmake"}' | ha_json_field is_cpp_project)
  [ "$b" = "true" ] && echo "  OK   bash-tier bool" || { echo "  FAIL bash-tier bool → '$b'"; exit 9; }
  e=$(printf 'x"y' | ha_json_escape)
  [ "$e" = 'x\"y' ] && echo "  OK   bash-tier escape" || { echo "  FAIL bash-tier escape → '$e'"; exit 9; }
  a=$(ha_flist_active /dev/null 2>/dev/null || true)
  [ -z "$a" ] && echo "  OK   flist degrades empty (no engine)" || { echo "  FAIL flist should be empty, got '$a'"; exit 9; }
  printf '{"x":1}' | ha_json_valid; rc=$?
  [ "$rc" -eq 2 ] && echo "  OK   ha_json_valid returns 2 (no engine)" || { echo "  FAIL ha_json_valid rc=$rc (want 2)"; exit 9; }
) || FAIL=$((FAIL+1))
rm -rf "$SHIM" "$ALLSHIM"

# ---- mtime ----
t=$(ha_mtime "$LIB")
case "$t" in (*[!0-9]*|'') bad "ha_mtime numeric" "$t" ;; (*) ok "ha_mtime numeric" ;; esac

echo ""; echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
