#!/usr/bin/env bash
# Unit test for templates/cpp/lint.sh.tpl — the sysroot-aware clang-tidy wrapper.
#
# Pins the behaviours code review demanded of the template:
#   1. no compile_commands.json anywhere  -> clear generate-hint + exit 1
#   2. DB at repo root                    -> clang-tidy invoked with `-p .`
#   3. DB only in .build/                 -> `-p .build` (PostToolUse-hook search parity)
#   4. explicit file args                 -> bypass the git ls-files default set
#   5. Darwin + xcrun with an SDK         -> sysroot extra-args injected (skipped elsewhere)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0; FAIL=0
ok()   { echo "  OK   $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

# Fresh fixture: repo with one tracked source, the template as scripts/lint.sh,
# and a stub clang-tidy that echoes its argv.
make_fixture() {
    T=$(mktemp -d)
    mkdir -p "$T/scripts" "$T/bin" "$T/src"
    cp "$PLUGIN_ROOT/templates/cpp/lint.sh.tpl" "$T/scripts/lint.sh"
    chmod +x "$T/scripts/lint.sh"
    cat > "$T/bin/clang-tidy" <<'EOF'
#!/usr/bin/env bash
echo "STUB ARGS: $*"
EOF
    chmod +x "$T/bin/clang-tidy"
    (cd "$T" && git init -q && echo 'int main(){return 0;}' > src/a.cpp && git add src/a.cpp)
    printf '%s\n' "$T"
}

run_lint() {  # $1 = fixture dir; remaining args passed through
    local t="$1"; shift
    (cd "$t" && PATH="$t/bin:$PATH" bash scripts/lint.sh "$@" 2>&1)
}

echo "=== 1. no compile DB -> exit 1 + hint ==="
T=$(make_fixture)
out=$(run_lint "$T"); rc=$?
if [ "$rc" -eq 1 ]; then ok "exit 1"; else fail "expected rc=1, got rc=$rc"; fi
if printf '%s' "$out" | grep -q 'compile_commands.json not found'; then ok "generate-hint present"; else fail "missing hint: $out"; fi
rm -rf "$T"

echo "=== 2. DB at repo root -> -p . ==="
T=$(make_fixture)
echo '[]' > "$T/compile_commands.json"
out=$(run_lint "$T"); rc=$?
if [ "$rc" -eq 0 ]; then ok "exit 0"; else fail "rc=$rc: $out"; fi
if printf '%s' "$out" | grep -q -- '-p \. '; then ok "-p ."; else fail "wrong -p: $out"; fi
rm -rf "$T"

echo "=== 3. DB only in .build/ -> -p .build + tracked default set ==="
T=$(make_fixture)
mkdir -p "$T/.build"; echo '[]' > "$T/.build/compile_commands.json"
out=$(run_lint "$T")
if printf '%s' "$out" | grep -q -- '-p .build'; then ok "-p .build"; else fail "wrong -p: $out"; fi
if printf '%s' "$out" | grep -q 'src/a.cpp'; then ok "git ls-files default set used"; else fail "default set missing: $out"; fi
rm -rf "$T"

echo "=== 4. explicit file args bypass ls-files ==="
T=$(make_fixture)
echo '[]' > "$T/compile_commands.json"
echo 'int x;' > "$T/src/b.cpp"
out=$(run_lint "$T" src/b.cpp)
if printf '%s' "$out" | grep -q 'src/b.cpp'; then ok "explicit file passed through"; else fail "explicit file missing: $out"; fi
if printf '%s' "$out" | grep -q 'src/a.cpp'; then fail "ls-files default leaked into explicit run"; else ok "no default-set leakage"; fi
rm -rf "$T"

echo "=== 5. Darwin sysroot injection (conditional) ==="
if [ "$(uname -s)" = "Darwin" ] && command -v xcrun >/dev/null 2>&1 && [ -n "$(xcrun --show-sdk-path 2>/dev/null || true)" ]; then
    T=$(make_fixture)
    echo '[]' > "$T/compile_commands.json"
    out=$(run_lint "$T")
    if printf '%s' "$out" | grep -q -- '--extra-arg=-isysroot'; then ok "sysroot extra-args injected"; else fail "sysroot args missing: $out"; fi
    rm -rf "$T"
else
    echo "  SKIP: not Darwin with a reporting xcrun (covered on the macOS CI runner)"
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
