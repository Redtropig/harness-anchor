#!/usr/bin/env bash
# Contract test for hooks/session-start.
#
# Happy path: emits valid SessionStart JSON with harness-anchor-state block.
# Negative: in a non-anchored dir, still emits valid JSON (session-start always emits).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0

assert_json_valid() {
    if printf '%s' "$1" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        echo "  OK   valid JSON"
        PASS=$((PASS+1))
    else
        echo "  FAIL invalid JSON output: $(printf '%s' "$1" | head -c 200)"
        FAIL=$((FAIL+1))
    fi
}

assert_contains() {
    if printf '%s' "$2" | grep -q "$1"; then
        echo "  OK   contains: $1"
        PASS=$((PASS+1))
    else
        echo "  FAIL missing: $1 (in: $(printf '%s' "$2" | head -c 200))"
        FAIL=$((FAIL+1))
    fi
}

# ---- Happy path: anchored project ----
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR" || exit 1
git init -q
git config user.email test@example.com
git config user.name test

# Minimal anchor files.
cat > feature_list.json <<'EOF'
{
  "project": "test",
  "features": [
    {
      "id": "feat-1",
      "name": "Feature One",
      "description": "test feature",
      "status": "in-progress",
      "done_criteria": ["build"]
    }
  ]
}
EOF

cat > PROJECT-TOC.md <<'EOF'
<!-- generated-at-commit: PLACEHOLDER_COMMIT_SHA -->
# PROJECT TOC

## Files

- `src/main.cpp` — entry point
EOF

cat > session-handoff.md <<'EOF'
# Session Handoff
Last updated: 2026-05-29
Active feature: feat-1
Next action: implement parser
EOF

git add -A
git commit -qm "init" 2>/dev/null || true

echo "=== session-start banner (happy path) ==="
output=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$TMPDIR" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true)

if [ -z "$output" ]; then
    echo "  FAIL no output emitted"
    FAIL=$((FAIL+1))
else
    assert_json_valid "$output"
    assert_contains "SessionStart" "$output"
    assert_contains "harness-anchor-state" "$output"
    assert_contains "feat-1" "$output"
fi

# ---- Negative: non-anchored dir ----
TMPDIR2=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2"' EXIT

echo ""
echo "=== session-start banner (non-anchored) ==="
output2=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$TMPDIR2" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true)

if [ -z "$output2" ]; then
    echo "  FAIL no output emitted; session-start should always emit"
    FAIL=$((FAIL+1))
else
    assert_json_valid "$output2"
    assert_contains "SessionStart" "$output2"
fi

# ---- /cpp-init recommendation: anchored C/C++ project missing clang config ----
# A C/C++ project that is anchored but has no .clang-format/.clang-tidy is exactly the
# state where /cpp-init is the right next step. The banner must surface it.
# Discriminator is the banner-only field "C/C++ setup:" — NOT the bare string "/cpp-init",
# which also appears in the injected meta-skill body regardless of the hint.
TMPDIR3=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2" "$TMPDIR3"' EXIT

cd "$TMPDIR3" || exit 1
printf '{ "project": "cpp-test", "features": [] }\n' > feature_list.json
printf 'cmake_minimum_required(VERSION 3.16)\nproject(cpp_test CXX)\n' > CMakeLists.txt
mkdir -p src
printf 'int main() { return 0; }\n' > src/main.cpp
# deliberately NO .clang-format / .clang-tidy → the un-initialized state

echo ""
echo "=== session-start (anchored C/C++ project, no clang config → expect /cpp-init hint) ==="
output3=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$TMPDIR3" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true)
if [ -z "$output3" ]; then
    echo "  FAIL no output emitted"
    FAIL=$((FAIL+1))
else
    assert_json_valid "$output3"
    assert_contains "C/C++ setup:" "$output3"
fi

# ---- negative: same project WITH clang config → banner hint must disappear ----
touch "$TMPDIR3/.clang-format" "$TMPDIR3/.clang-tidy"
echo ""
echo "=== session-start (C/C++ project WITH clang config → expect NO hint) ==="
output4=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$TMPDIR3" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true)
if printf '%s' "$output4" | grep -q "C/C++ setup:"; then
    echo "  FAIL cpp-init hint still present after clang config added"
    FAIL=$((FAIL+1))
else
    echo "  OK   hint correctly suppressed when clang config present"
    PASS=$((PASS+1))
fi

# ---- Deep repo → directory-map injection + budget-at-scale (piece 4b/4c) ----
# A TOC whose ## Files and ## Directory map BOTH exceed the Tier-1 leftover (~7K under
# the 12000 cap) forces the adaptive degradation. The map (not the file list) must be
# injected, and — crucially — the decoded context must stay within the 12000-char cap.
# The TOC is hand-built at 600 entries (Files ~16KB, map ~11KB — both over budget with
# margin): the degradation logic consumes only this file + budget arithmetic, and a REAL
# 600-dir tree's git/find cost pushed pessimal macOS CI runners past the hook's 5s
# watchdog ("no output emitted") — a latency artifact, not the contract under test.
# index-builder's real output format is pinned by tests/unit/index-builder-dirmap.sh
# and exercised through the hook by the e2e fixture (measure-context, happy path).
TMPDIR4=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2" "$TMPDIR3" "$TMPDIR4"' EXIT
cd "$TMPDIR4" || exit 1
git init -q
git config user.email test@example.com
git config user.name test
printf '{ "project": "big", "features": [] }\n' > feature_list.json
printf 'x\n' > seed.txt
git add -A >/dev/null 2>&1
git commit -qm init >/dev/null 2>&1 || true
anchor4=$(git rev-parse HEAD 2>/dev/null | cut -c1-12)
{
    printf '<!-- generated-at-commit: %s -->\n' "$anchor4"
    echo '# PROJECT TOC'
    echo ''
    echo '## Directory map'
    echo ''
    echo '- `.` (root) — 2 files, 600 subdirs'
    i=0
    while [ "$i" -lt 600 ]; do printf -- '- `d%03d/` — 1 file\n' "$i"; i=$((i+1)); done
    echo ''
    echo '## Files'
    echo ''
    echo '- `feature_list.json` — { "project": "big", "features": [] }'
    echo '- `seed.txt` — x'
    i=0
    while [ "$i" -lt 600 ]; do printf -- '- `d%03d/f.txt` — d%03d file\n' "$i" "$i"; i=$((i+1)); done
} > PROJECT-TOC.md

echo ""
echo "=== session-start (deep repo → directory-map injected, budget held) ==="
output5=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$TMPDIR4" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true)
ctx5=$(printf '%s' "$output5" | python3 -c "import json,sys; print(json.load(sys.stdin).get('hookSpecificOutput',{}).get('additionalContext',''))" 2>/dev/null || true)
if [ -z "$output5" ]; then
    echo "  FAIL no output emitted"; FAIL=$((FAIL+1))
else
    assert_json_valid "$output5"
    assert_contains "(root)" "$ctx5"        # the "(root)" line is map-only — proves map injection
    assert_contains "for the full" "$ctx5"  # a "see ... for the full ..." pointer (degraded view)
    # CHARACTER count, not bash ${#}: under a C/POSIX locale (Git Bash's default)
    # ${#} counts BYTES, so multibyte chars (—, etc.) inflate it past the 12000-CHAR
    # cap the budget targets (macOS/Linux CI run UTF-8, where ${#} already = chars).
    len5=$(printf '%s' "$output5" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('hookSpecificOutput',{}).get('additionalContext','')))" 2>/dev/null || echo 999999)
    if [ "$len5" -le 12000 ]; then
        echo "  OK   budget held at scale: ${len5} <= 12000"; PASS=$((PASS+1))
    else
        echo "  FAIL budget blown at scale: ${len5} > 12000"; FAIL=$((FAIL+1))
    fi
fi

# ---- Old-style TOC (no ## Directory map) → legacy files-truncation fallback (piece 4d) ----
TMPDIR5=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2" "$TMPDIR3" "$TMPDIR4" "$TMPDIR5"' EXIT
cd "$TMPDIR5" || exit 1
git init -q
git config user.email test@example.com
git config user.name test
printf '{ "project": "legacy", "features": [] }\n' > feature_list.json
{
    echo '<!-- generated-at-commit: PLACEHOLDER_COMMIT_SHA -->'
    echo '# PROJECT TOC'
    echo ''
    echo '## Files'
    echo ''
    j=0
    while [ "$j" -lt 400 ]; do printf -- '- `src/file%03d.cpp` — one-line summary for file %03d\n' "$j" "$j"; j=$((j+1)); done
} > PROJECT-TOC.md
git add -A >/dev/null 2>&1
git commit -qm init >/dev/null 2>&1 || true

echo ""
echo "=== session-start (old TOC, no dir-map → legacy truncation, budget held) ==="
output6=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$TMPDIR5" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true)
ctx6=$(printf '%s' "$output6" | python3 -c "import json,sys; print(json.load(sys.stdin).get('hookSpecificOutput',{}).get('additionalContext',''))" 2>/dev/null || true)
if [ -z "$output6" ]; then
    echo "  FAIL no output emitted"; FAIL=$((FAIL+1))
else
    assert_json_valid "$output6"
    assert_contains "file000.cpp" "$ctx6"                        # head of the list present
    assert_contains "see PROJECT-TOC.md for full index" "$ctx6"  # legacy pointer
    # CHARACTER count (see the len5 note above — C-locale ${#} counts bytes).
    len6=$(printf '%s' "$output6" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('hookSpecificOutput',{}).get('additionalContext','')))" 2>/dev/null || echo 999999)
    if [ "$len6" -le 12000 ]; then
        echo "  OK   legacy budget held: ${len6} <= 12000"; PASS=$((PASS+1))
    else
        echo "  FAIL legacy budget blown: ${len6} > 12000"; FAIL=$((FAIL+1))
    fi
fi

# ---- Golden-rules count (v0.6.0 banner field): real rules counted, commented example NOT ----
# Guards the count pattern ^### GR-[0-9]: a freshly-scaffolded golden-rules.md (only the
# commented ### GR-N example) must read 0, not 1; absence → no banner line.
TMPDIR6=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2" "$TMPDIR3" "$TMPDIR4" "$TMPDIR5" "$TMPDIR6"' EXIT
cd "$TMPDIR6" || exit 1
printf '{ "project": "gr", "features": [] }\n' > feature_list.json
cat > golden-rules.md <<'EOF'
# Golden Rules

<!-- Example shape (delete and replace):
### GR-N — placeholder example that must NOT be counted
-->

## Rules

### GR-1 — real rule one
- **Check:** manual review

### GR-2 — real rule two
- **Check:** manual review
EOF

echo ""
echo "=== session-start (2 real rules + commented example → expect 2) ==="
output7=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$TMPDIR6" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true)
if [ -z "$output7" ]; then
    echo "  FAIL no output emitted"; FAIL=$((FAIL+1))
else
    assert_json_valid "$output7"
    assert_contains "Golden rules: *2 rule" "$output7"
fi

# as-shipped empty template → must read 0, not the commented example (the bug guard)
cp "$PLUGIN_ROOT/templates/golden-rules.md.tpl" "$TMPDIR6/golden-rules.md"
echo ""
echo "=== session-start (as-shipped empty template → expect 0 rules) ==="
output8=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$TMPDIR6" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true)
assert_contains "Golden rules: *0 rule" "$output8"

# absence → no "Golden rules:" banner line
rm -f "$TMPDIR6/golden-rules.md"
echo ""
echo "=== session-start (no golden-rules.md → expect NO 'Golden rules:' line) ==="
output9=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$TMPDIR6" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true)
if printf '%s' "$output9" | grep -q "Golden rules:"; then
    echo "  FAIL 'Golden rules:' line present when golden-rules.md absent"; FAIL=$((FAIL+1))
else
    echo "  OK   'Golden rules:' line correctly absent"; PASS=$((PASS+1))
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
