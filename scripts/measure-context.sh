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

# Interpreter discovery (v0.13.0): python3 → python → py -3 via the shared chain.
# SCRIPT_DIR is already absolute (no cd follows), so the lib path is stable.
HA_LIB_DIR="$SCRIPT_DIR/lib"
# shellcheck disable=SC1091
. "${HA_LIB_DIR}/portable.sh" 2>/dev/null || true
PYBIN=""
command -v ha_python >/dev/null 2>&1 && PYBIN=$(ha_python || true)
if [ -z "$PYBIN" ]; then
    echo "NOTE: no python interpreter (python3/python/py) found — this tool needs Python to decode the hook JSON; install it or rely on CI." >&2
fi

echo "=== measure-context ==="
echo ""

# ---- 1. Bootstrap the e2e fixture ----
FIXTURE_DIR=$(bash "${PLUGIN_ROOT}/tests/e2e-cpp-fixture/bootstrap.sh" 2>/dev/null)
if [ -z "$FIXTURE_DIR" ] || [ ! -d "$FIXTURE_DIR" ]; then
    echo "FAIL: bootstrap.sh did not produce a temp dir"
    exit 1
fi
GEN_DIR=""
trap 'rm -rf "$FIXTURE_DIR" "$GEN_DIR"' EXIT
echo "Fixture: $FIXTURE_DIR (C/C++ — cpp-only regions injected)"

# ---- 2. Invoke session-start hook ----
OUTPUT=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$FIXTURE_DIR" \
    bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true)

if [ -z "$OUTPUT" ]; then
    echo "FAIL: session-start produced no output"
    exit 1
fi

# ---- 3. Decode the additionalContext field ----
# shellcheck disable=SC2086
CONTEXT=$(printf '%s' "$OUTPUT" | $PYBIN -c "
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

RC=0
if [ "$TOTAL" -gt "$CAP" ]; then
    echo "FAIL: total ${TOTAL} chars exceeds ${CAP} char cap (invariant #2)"
    RC=1
elif [ "$TOTAL" -ge "$WARN" ]; then
    echo "WARN: total ${TOTAL} chars is ≥ 90% of cap (${WARN} chars)"
else
    echo "OK: within budget"
fi

# ---- 5. Second pass: bare generic fixture (the per-project fixed cost) ----
# The e2e fixture above is a C/C++ project, so its injection includes the
# cpp-only regions. A generic project is the slimmer, more common shape —
# measure it too, so the generic fixed-cost baseline stays visible.
GEN_DIR=$(mktemp -d)
git -C "$GEN_DIR" init -q 2>/dev/null
printf '# scratch\n' > "$GEN_DIR/README.md"
OUTPUT2=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$GEN_DIR" \
    bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true)
# shellcheck disable=SC2086
CONTEXT2=$(printf '%s' "$OUTPUT2" | $PYBIN -c "
import json, sys
try:
    print(json.load(sys.stdin).get('hookSpecificOutput', {}).get('additionalContext', ''))
except Exception:
    pass
" 2>/dev/null)
TOTAL2=${#CONTEXT2}
echo ""
echo "Generic fixture (no TOC/handoff, cpp-only regions dropped):"
echo "  Total:                   ${TOTAL2} chars"
if [ "$TOTAL2" -le 0 ]; then
    echo "FAIL: generic pass produced no context"
    RC=1
elif [ "$TOTAL2" -gt "$CAP" ]; then
    echo "FAIL: generic total ${TOTAL2} chars exceeds ${CAP} char cap (invariant #2)"
    RC=1
elif [ "$TOTAL2" -ge "$WARN" ]; then
    echo "WARN: generic total ${TOTAL2} chars is ≥ 90% of cap (${WARN} chars)"
else
    echo "OK: generic within budget"
fi
exit $RC
