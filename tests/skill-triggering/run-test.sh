#!/usr/bin/env bash
# Test whether a naive user prompt triggers the expected skill.
#
# Usage: ./run-test.sh <skill-name> <prompt-file> [max-turns]
#
# Inspired by superpowers/tests/skill-triggering/run-test.sh
set -euo pipefail

SKILL_NAME="${1:-}"
PROMPT_FILE="${2:-}"
MAX_TURNS="${3:-3}"

if [ -z "$SKILL_NAME" ] || [ -z "$PROMPT_FILE" ]; then
    echo "Usage: $0 <skill-name> <prompt-file> [max-turns]"
    echo ""
    echo "Available prompts:"
    ls "$(dirname "$0")/prompts/" 2>/dev/null
    exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
    echo "ERROR: claude CLI not found. Install Claude Code first."
    exit 2
fi

if [ ! -f "$PROMPT_FILE" ]; then
    echo "ERROR: prompt file not found: $PROMPT_FILE"
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
. "$PLUGIN_DIR/scripts/lib/portable.sh" 2>/dev/null || true
PYBIN=""
command -v ha_python >/dev/null 2>&1 && PYBIN=$(ha_python || true)

TIMESTAMP=$(date +%s)
OUTPUT_DIR="/tmp/harness-anchor-tests/${TIMESTAMP}/skill-triggering/${SKILL_NAME}"
mkdir -p "$OUTPUT_DIR"
cp "$PROMPT_FILE" "$OUTPUT_DIR/prompt.txt"

LOG_FILE="$OUTPUT_DIR/claude-output.json"
PROMPT=$(cat "$PROMPT_FILE")

echo "=== Skill Triggering Test ==="
echo "Skill:        $SKILL_NAME"
echo "Prompt file:  $PROMPT_FILE"
echo "Plugin dir:   $PLUGIN_DIR"
echo "Output:       $OUTPUT_DIR"
echo ""

cd "$OUTPUT_DIR"
timeout 300 claude -p "$PROMPT" \
    --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --max-turns "$MAX_TURNS" \
    --output-format stream-json \
    > "$LOG_FILE" 2>&1 || true

# Match either "skill":"name" or "skill":"namespace:name"
SKILL_PATTERN='"skill":"([^"]*:)?'"${SKILL_NAME}"'"'

echo "=== Results ==="
if grep -q '"name":"Skill"' "$LOG_FILE" 2>/dev/null && grep -qE "$SKILL_PATTERN" "$LOG_FILE" 2>/dev/null; then
    echo "PASS: skill '$SKILL_NAME' was triggered"
    TRIGGERED=true
else
    echo "FAIL: skill '$SKILL_NAME' was NOT triggered"
    TRIGGERED=false
fi

echo ""
echo "Skills triggered in this run:"
grep -o '"skill":"[^"]*"' "$LOG_FILE" 2>/dev/null | sort -u || echo "  (none detected)"

echo ""
echo "First assistant response (truncated):"
# shellcheck disable=SC2086
grep '"type":"assistant"' "$LOG_FILE" 2>/dev/null | head -1 | $PYBIN -c "
import json, sys
try:
    d = json.loads(sys.stdin.readline())
    c = d.get('message', {}).get('content', [])
    if isinstance(c, list) and c:
        print(c[0].get('text', str(c))[:400])
    else:
        print(str(c)[:400])
except Exception as e:
    print('(could not parse: ', e, ')')
" 2>/dev/null || echo "(could not extract)"

echo ""
echo "Full log: $LOG_FILE"

[ "$TRIGGERED" = "true" ] && exit 0 || exit 1
