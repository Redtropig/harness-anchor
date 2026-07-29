#!/usr/bin/env bash
# Unit test for scripts/cpp-tool-discovery.sh — output contract, exit code,
# stdout purity, and the "unknown tool degrades to NOT_FOUND, never errors" rule.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DISC="$PLUGIN_ROOT/scripts/cpp-tool-discovery.sh"

PASS=0; FAIL=0
# Build the TAB separator programmatically — a literal tab inside this file is
# too easy for an editor to convert to spaces, which would fail confusingly.
TAB=$(printf '\t')
expect_contains() { # <label> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "  OK   $1"; PASS=$((PASS+1));;
    *)      echo "  FAIL $1 → missing '$2'"; printf '%s\n' "$3" | head -10; FAIL=$((FAIL+1));;
  esac
}
expect_not_contains() { # <label> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "  FAIL $1 → unexpected '$2'"; FAIL=$((FAIL+1));;
    *)      echo "  OK   $1"; PASS=$((PASS+1));;
  esac
}

# ---- 1. exit code is ALWAYS 0, even for a tool that cannot exist ----
out=$(bash "$DISC" definitely-not-a-real-tool-xyz 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ]; then echo "  OK   exit 0 on missing tool"; PASS=$((PASS+1));
else echo "  FAIL exit was $rc, must be 0"; FAIL=$((FAIL+1)); fi

# ---- 2. missing tool → NOT_FOUND line that ENUMERATES what was searched ----
expect_contains "missing tool emits NOT_FOUND" "NOT_FOUND" "$out"
expect_contains "missing tool names the tool" "definitely-not-a-real-tool-xyz" "$out"
expect_contains "NOT_FOUND carries searched: scope" "searched:" "$out"
expect_contains "searched: includes PATH" "PATH" "$out"

# ---- 3. a tool that definitely IS on PATH → FOUND via 'path' ----
out2=$(bash "$DISC" bash 2>/dev/null)
expect_contains "bash is FOUND" "FOUND" "$out2"
expect_contains "bash resolved via path" "${TAB}path" "$out2"

# ---- 4. stdout purity: every line starts with FOUND or NOT_FOUND ----
bad_lines=$(printf '%s\n' "$out2" | grep -cvE "^(FOUND|NOT_FOUND)${TAB}" || true)
if [ "$bad_lines" -eq 0 ]; then echo "  OK   stdout has no diagnostic noise"; PASS=$((PASS+1));
else echo "  FAIL $bad_lines non-contract lines on stdout"; FAIL=$((FAIL+1)); fi

# ---- 5. multiple tools → one line each ----
out3=$(bash "$DISC" bash definitely-not-a-real-tool-xyz 2>/dev/null)
n=$(printf '%s\n' "$out3" | grep -cE "^(FOUND|NOT_FOUND)${TAB}" || true)
if [ "$n" -eq 2 ]; then echo "  OK   two tools → two lines"; PASS=$((PASS+1));
else echo "  FAIL expected 2 contract lines, got $n"; FAIL=$((FAIL+1)); fi

# ---- 6. the wording constraint: script must never emit the banned phrasing ----
expect_not_contains "no 'not installed' phrasing" "not installed" "$out"
expect_not_contains "no 'on this machine' phrasing" "on this machine" "$out"

# ---- 7. no direct python3 (invariant #10) ----
if grep -qE '(^|[^a-zA-Z_-])python3([^a-zA-Z_-]|$)' "$DISC"; then
  echo "  FAIL script invokes python3 directly"; FAIL=$((FAIL+1))
else echo "  OK   no direct python3"; PASS=$((PASS+1)); fi

# ---- 8. §B4: versioned discovery must not depend on a hard-coded version
#         ladder. Through v0.16.0 the ladder topped out at 22, giving the script
#         a ~12-month fuse: LLVM 23 ships, the tool is installed, and discovery
#         reports NOT_FOUND — recreating the exact bug this script was written
#         to fix. `-99` is above any ladder anyone would have written. ----
FAKEDIR=$(mktemp -d); trap 'rm -rf "$FAKEDIR"' EXIT
printf '#!/bin/sh\necho fake\n' > "$FAKEDIR/ha-faketool-99"
chmod +x "$FAKEDIR/ha-faketool-99"
out8=$(PATH="$FAKEDIR:$PATH" bash "$DISC" ha-faketool 2>/dev/null)
expect_contains "[B4] version far above any ladder is found" "FOUND" "$out8"
expect_contains "[B4] found via the versioned label" "${TAB}versioned" "$out8"

# ---- 9. §B4: a non-numeric suffix is not a version and must not be mistaken
#         for one (clang-tidy-dev, clang-format-diff, ...). ----
FAKEDIR2=$(mktemp -d); trap 'rm -rf "$FAKEDIR" "$FAKEDIR2"' EXIT
printf '#!/bin/sh\necho fake\n' > "$FAKEDIR2/ha-othertool-dev"
chmod +x "$FAKEDIR2/ha-othertool-dev"
out9=$(PATH="$FAKEDIR2:$PATH" bash "$DISC" ha-othertool 2>/dev/null)
expect_contains "[B4] non-numeric suffix is not treated as a version" "NOT_FOUND" "$out9"

echo ""
echo "cpp-tool-discovery: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
