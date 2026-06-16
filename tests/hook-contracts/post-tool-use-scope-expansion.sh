#!/usr/bin/env bash
# Contract test for hooks/post-tool-use — agent-initiated scope-expansion check (issue #6).
#
# Happy path: Write of a NEW untracked code module while a feature is in-progress -> warn.
# Negatives (precision): tracked-file overwrite, Edit event, new test-dir file, new non-code
#   file, git-ignored file, and "no in-progress feature" all stay silent.
#
# Requires git (the "new = untracked" signal is git-derived); the temp projects are real repos.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
ok()   { echo "  OK   $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

assert_json_valid() {
    if printf '%s' "$1" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        ok "valid JSON"
    else
        fail "invalid JSON output: $(printf '%s' "$1" | head -c 200)"
    fi
}
assert_contains() {
    if printf '%s' "$2" | grep -q "$1"; then
        ok "contains: $1"
    else
        fail "missing: $1 (in: $(printf '%s' "$2" | head -c 200))"
    fi
}
run_hook() { printf '%s' "$1" | bash "$PLUGIN_ROOT/hooks/post-tool-use" 2>/dev/null || true; }

# git-gated by design: skip cleanly where git is unavailable.
if ! command -v git >/dev/null 2>&1; then
    echo "git not available - skipping scope-expansion contract test (git-gated by design)"
    exit 0
fi

# ---- Project A: anchored, one in-progress feature, one tracked source file ----
TMPA=$(mktemp -d)
TMPB=""
trap 'rm -rf "$TMPA" "$TMPB"' EXIT
cd "$TMPA" || exit 1
git init -q
git config user.email "t@example.com"
git config user.name "t"
cat > feature_list.json <<'EOF'
{
  "project": "scope-detect-test",
  "features": [
    { "id": "feat-current", "name": "Current Feature", "description": "in-progress",
      "status": "in-progress", "done_criteria": ["build"] }
  ]
}
EOF
mkdir -p src tests
echo "x = 1" > src/existing.py
git add feature_list.json src/existing.py
git commit -qm "init"
printf 'generated/\n' > .gitignore
git add .gitignore
git commit -qm "gitignore"

echo "=== (a) new untracked code module + in-progress feature -> WARN ==="
echo "def widget(): pass" > src/widget.py     # left untracked
out_a=$(run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMPA/src/widget.py\"}}")
if [ -n "$out_a" ]; then
    assert_json_valid "$out_a"
    assert_contains "PostToolUse" "$out_a"
    assert_contains "feat-current" "$out_a"
    assert_contains "New module" "$out_a"
    assert_contains "src/widget.py" "$out_a"
else
    fail "(a) expected a scope-expansion warning, got nothing"
fi

echo ""
echo "=== (b) overwrite a TRACKED file -> quiet ==="
echo "x = 2" > src/existing.py
out_b=$(run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMPA/src/existing.py\"}}")
if [ -z "$out_b" ]; then ok "(b) silent for tracked-file overwrite"; else fail "(b) expected silence, got: $(printf '%s' "$out_b" | head -c 120)"; fi

echo ""
echo "=== (c) new untracked file under tests/ -> quiet ==="
echo "def test_x(): pass" > tests/test_widget.py
out_c=$(run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMPA/tests/test_widget.py\"}}")
if [ -z "$out_c" ]; then ok "(c) silent for new test-dir file"; else fail "(c) expected silence, got: $(printf '%s' "$out_c" | head -c 120)"; fi

echo ""
echo "=== (d) new untracked non-code file -> quiet ==="
echo "notes" > notes.md
out_d=$(run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMPA/notes.md\"}}")
if [ -z "$out_d" ]; then ok "(d) silent for new non-code file"; else fail "(d) expected silence, got: $(printf '%s' "$out_d" | head -c 120)"; fi

echo ""
echo "=== (f) Edit event on a tracked file -> quiet (Write-gate) ==="
out_f=$(run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPA/src/existing.py\"}}")
if [ -z "$out_f" ]; then ok "(f) silent for Edit event"; else fail "(f) expected silence, got: $(printf '%s' "$out_f" | head -c 120)"; fi

echo ""
echo "=== (g) new untracked but GIT-IGNORED code module -> quiet ==="
mkdir -p generated
echo "def gen(): pass" > generated/thing.py
out_g=$(run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMPA/generated/thing.py\"}}")
if [ -z "$out_g" ]; then ok "(g) silent for git-ignored new module"; else fail "(g) expected silence, got: $(printf '%s' "$out_g" | head -c 120)"; fi

# ---- Project B: anchored, NO in-progress feature (only planned) ----
TMPB=$(mktemp -d)
cd "$TMPB" || exit 1
git init -q
git config user.email "t@example.com"
git config user.name "t"
cat > feature_list.json <<'EOF'
{
  "project": "no-active",
  "features": [
    { "id": "feat-planned", "name": "Planned Feature", "description": "planned",
      "status": "planned", "done_criteria": ["build"] }
  ]
}
EOF
git add feature_list.json
git commit -qm "init"
mkdir -p src

echo ""
echo "=== (e) new untracked code module, NO in-progress feature -> quiet ==="
echo "def other(): pass" > src/other.py
out_e=$(run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMPB/src/other.py\"}}")
if [ -z "$out_e" ]; then ok "(e) silent when no in-progress feature"; else fail "(e) expected silence, got: $(printf '%s' "$out_e" | head -c 120)"; fi

echo ""
echo "==================================="
echo " Pass: $PASS    Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
