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

# Every prompt must be ADVERSARIAL: it must not name the skill it targets.
# Registration + file existence were the only things checked until v0.18.0, so a
# prompt that said "use the docs-lookup skill" would have satisfied the guard while
# testing nothing — the run would pass because the user named the skill, not because
# the description front-loaded the right keywords. That is the property invariant #6
# is actually about, and the reason its enforcement is an eval rather than a grep;
# leaving the eval's own input unchecked would have made it quietly vacuous.
# Both spellings are rejected: the hyphenated name and its space-separated form
# ("docs lookup"), since either one hands the answer to the model.
#
# MATCHER SELF-TEST FIRST. The loop concludes "this prompt is clean" from a grep
# returning non-zero — and a grep that CRASHES also returns non-zero. This MSYS2
# grep aborts (exit 134) on `-i` with multiple `-e` patterns, the same class
# tests/windows-compat.sh documents for `-i` combined with `-F`, and it writes
# nothing to stderr, so the abort is indistinguishable from "no match". The first
# version of this check used that form and reported 15 clean prompts having matched
# nothing at all. Single `-E` alternation is crash-free here; the probe below is
# what proves it, on whatever grep is actually running.
_probe=$(mktemp)
printf 'this line mentions docs-lookup explicitly\n' > "$_probe"
if grep -qiE 'docs-lookup|docs lookup' "$_probe"; then
    echo "  OK   matcher self-test: pattern found in a known-positive"
    PASS=$((PASS+1))
else
    echo "  FAIL matcher self-test: grep failed to match a string that contains the pattern — every verdict below would be a false clean"
    FAIL=$((FAIL+1))
fi
rm -f "$_probe"

ADVERSARIAL_CHECKED=0
while IFS= read -r entry; do
    pair=$(printf '%s' "$entry" | tr -d '"')
    skill=${pair%%:*}
    prompt=${pair#*:}
    [ -f "$SCRIPT_DIR/prompts/$prompt" ] || continue
    spaced=$(printf '%s' "$skill" | tr '-' ' ')
    ADVERSARIAL_CHECKED=$((ADVERSARIAL_CHECKED+1))
    if grep -qiE "$skill|$spaced" "$SCRIPT_DIR/prompts/$prompt"; then
        echo "  FAIL prompts/$prompt names its own skill ('$skill') — not adversarial"
        FAIL=$((FAIL+1))
    else
        echo "  OK   adversarial (never names '$skill'): $prompt"
        PASS=$((PASS+1))
    fi
done < <(grep -oE '"[a-z][a-z-]*:[a-z0-9-]+\.txt"' "$RUN_ALL")

# Non-vacuity: if the registration pattern ever stops matching, the loop above is
# a no-op and this suite reports all-pass having checked nothing.
if [ "$ADVERSARIAL_CHECKED" -eq 0 ]; then
    echo "  FAIL no registered case was adversarial-checked — the parse found nothing"
    FAIL=$((FAIL+1))
fi

echo ""
echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo " STATUS: PASSED — every sibling skill has an adversarial triggering case"
    exit 0
else
    # `missing` covers only the first loop. Naming it unconditionally reported
    # "skills missing a case:" with an empty list whenever the failure was a
    # non-adversarial prompt instead — a status line that misdescribes its own run.
    if [ -n "$missing" ]; then
        echo " STATUS: FAILED — skills missing a case:${missing}"
    else
        echo " STATUS: FAILED — see the FAIL lines above (coverage is complete; a prompt or the matcher failed)"
    fi
    exit 1
fi
