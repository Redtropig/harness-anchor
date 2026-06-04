#!/usr/bin/env bash
# Skill-triggering COVERAGE check — structural, NO Claude/LLM required (CI-safe).
#
# Enforces the CLAUDE.md authoring rule: every sibling skill must have at least
# one adversarial triggering case registered in run-all.sh, and every registered
# case must point at a prompt file that exists. The actual triggering assertions
# (run-all.sh) need a live Claude session and run manually before a release; this
# guard just makes sure coverage never silently regresses.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUN_ALL="$SCRIPT_DIR/run-all.sh"

# Meta-skill is auto-injected by SessionStart (never model-pulled), so it is
# exempt from a triggering prompt.
EXEMPT="using-harness-anchor"

PASS=0; FAIL=0; missing=""

# Skills present on disk (portable; no `mapfile` — macOS ships bash 3.2).
skills=$(cd "$PLUGIN_ROOT/skills" && for d in */; do printf '%s\n' "${d%/}"; done | sort)

# Skill names registered in run-all.sh CASES entries ("skill:prompt.txt").
registered=$(grep -oE '"[a-z][a-z-]*:[a-z0-9-]+\.txt"' "$RUN_ALL" | sed -E 's/^"//; s/:.*$//' | sort -u)

for s in $skills; do
    case " $EXEMPT " in
        *" $s "*) echo "  --   $s (exempt: meta-skill, auto-injected)"; continue;;
    esac
    if printf '%s\n' "$registered" | grep -qx "$s"; then
        echo "  OK   $s has a triggering case"
        PASS=$((PASS+1))
    else
        echo "  FAIL $s has NO triggering case in run-all.sh"
        FAIL=$((FAIL+1)); missing="$missing $s"
    fi
done

# Every registered prompt file must exist.
while IFS= read -r entry; do
    prompt=$(printf '%s' "$entry" | sed -E 's/^"[a-z][a-z-]*://; s/"$//')
    [ -z "$prompt" ] && continue
    if [ -f "$SCRIPT_DIR/prompts/$prompt" ]; then
        echo "  OK   prompt file exists: $prompt"
        PASS=$((PASS+1))
    else
        echo "  FAIL registered prompt file missing: prompts/$prompt"
        FAIL=$((FAIL+1))
    fi
done < <(grep -oE '"[a-z][a-z-]*:[a-z0-9-]+\.txt"' "$RUN_ALL")

echo ""
echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo " STATUS: PASSED — every sibling skill has a triggering case"
    exit 0
else
    echo " STATUS: FAILED — skills missing a case:${missing}"
    exit 1
fi
