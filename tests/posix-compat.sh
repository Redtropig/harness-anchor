#!/usr/bin/env bash
# posix-compat.sh — Verify harness-anchor scripts avoid GNU-only flags.
#
# Runs on both macOS (BSD) and Linux (GNU) in CI. Flags that differ between
# BSD and GNU coreutils are the most common portability pitfall.
#
# Exit 1 if any incompatibility is found.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

ok()   { echo "  OK   $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

echo "=== POSIX compatibility check ==="
echo "Root: $PLUGIN_ROOT"
echo ""

# ---- 1. No GNU-only wc flags (e.g., --bytes) ----
echo "[1/4] No GNU-only wc flags..."
grep -rn 'wc\s\+--' "$PLUGIN_ROOT"/hooks/ "$PLUGIN_ROOT"/scripts/ 2>/dev/null | grep -v '\.bak' || true
if grep -rn 'wc\s\+--' "$PLUGIN_ROOT"/hooks/ "$PLUGIN_ROOT"/scripts/ 2>/dev/null | grep -v '\.bak' | grep -q .; then
    fail "GNU-only wc flags found (use 'wc -c' not 'wc --bytes')"
else
    ok "no GNU-only wc flags"
fi
echo ""

# ---- 2. No GNU-only find flags (e.g., -printf, -regextype) ----
echo "[2/4] No GNU-only find flags..."
gnu_find_flags='\-printf\|\-regextype\|\-fstype'
if grep -rn "$gnu_find_flags" "$PLUGIN_ROOT"/hooks/ "$PLUGIN_ROOT"/scripts/ 2>/dev/null | grep -v '\.bak' | grep -q .; then
    fail "GNU-only find flags found"
else
    ok "no GNU-only find flags"
fi
echo ""

# ---- 3. No GNU-only sed flags (e.g., -r without -E equivalence) ----
echo "[3/4] No GNU-only sed -r (use -E instead)..."
# -r is GNU-only; -E is POSIX/BSD/GNU-portable
if grep -rn "sed[^|]* -r[^E]" "$PLUGIN_ROOT"/hooks/ "$PLUGIN_ROOT"/scripts/ 2>/dev/null | grep -v '\.bak' | grep -q .; then
    fail "GNU-only sed -r found (use sed -E instead)"
else
    ok "no GNU-only sed -r"
fi
echo ""

# ---- 4. No GNU-only date flags (e.g., -d, --date) ----
echo "[4/4] No GNU-only date flags..."
if grep -rn 'date\s\+--\|date\s\+-d' "$PLUGIN_ROOT"/hooks/ "$PLUGIN_ROOT"/scripts/ 2>/dev/null | grep -v '\.bak' | grep -q .; then
    fail "GNU-only date flags found"
else
    ok "no GNU-only date flags"
fi
echo ""

# ---- Summary ----
echo "==================================="
echo " Pass: $PASS    Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo " STATUS: PASSED"
    exit 0
else
    echo " STATUS: FAILED"
    exit 1
fi
