#!/usr/bin/env bash
# measure-context.sh — Measure SessionStart hook context output vs the 12000-char cap.
#
# Bootstraps the e2e fixture, invokes hooks/session-start with it, decodes the
# JSON additionalContext, and prints a byte breakdown per section.
# Exit 1 if total exceeds 12000 chars; warn at ≥ 10800 chars (90%).
#
# Usage: bash scripts/measure-context.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== measure-context ==="
echo ""

# ---- 1. Bootstrap the e2e fixture ----
FIXTURE_DIR=$(bash "${PLUGIN_ROOT}/tests/e2e-cpp-fixture/bootstrap.sh" 2>/dev/null)
if [ -z "$FIXTURE_DIR" ] || [ ! -d "$FIXTURE_DIR" ]; then
    echo "FAIL: bootstrap.sh did not produce a temp dir"
    exit 1
fi
trap 'rm -rf "$FIXTURE_DIR"' EXIT
echo "Fixture: $FIXTURE_DIR"

# ---- 2. Invoke session-start hook ----
OUTPUT=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$FIXTURE_DIR" \
    bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true)

if [ -z "$OUTPUT" ]; then
    echo "FAIL: session-start produced no output"
    exit 1
fi

# ---- 3. Decode the additionalContext field ----
CONTEXT=$(printf '%s' "$OUTPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ctx = d.get('hookSpecificOutput', {}).get('additionalContext', '')
    print(ctx)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)

if [ -z "$CONTEXT" ]; then
    echo "FAIL: could not decode additionalContext from hook output"
    exit 1
fi

# ---- 4. Measure per-section byte counts ----
TOTAL=${#CONTEXT}
CAP=12000
WARN=$((CAP * 90 / 100))  # 10800

# Extract sections by marker tags
STATE_SECTION=$(printf '%s' "$CONTEXT" | awk '/<harness-anchor-state>/,/<\/harness-anchor-state>/' || true)
TOC_SECTION=$(printf '%s' "$CONTEXT" | awk '/<project-toc>/,/<\/project-toc>/' || true)
# Skill body = everything after the last closing tag
SKILL_LEN=$((TOTAL - ${#STATE_SECTION} - ${#TOC_SECTION}))
[ "$SKILL_LEN" -lt 0 ] && SKILL_LEN=0

echo ""
echo "Section breakdown:"
echo "  <harness-anchor-state>:  ${#STATE_SECTION} chars"
echo "  <project-toc>:           ${#TOC_SECTION} chars"
echo "  Skill body (remainder):  ${SKILL_LEN} chars"
echo "  ─────────────────────────────────"
echo "  Total:                   ${TOTAL} chars"
echo "  Cap:                     ${CAP} chars"
echo "  Usage:                   $(( TOTAL * 100 / CAP ))%"
echo ""

if [ "$TOTAL" -gt "$CAP" ]; then
    echo "FAIL: total ${TOTAL} chars exceeds ${CAP} char cap (invariant #2)"
    exit 1
elif [ "$TOTAL" -ge "$WARN" ]; then
    echo "WARN: total ${TOTAL} chars is ≥ 90% of cap (${WARN} chars)"
    exit 0
else
    echo "OK: within budget"
    exit 0
fi
