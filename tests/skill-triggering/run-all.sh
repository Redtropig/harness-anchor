#!/usr/bin/env bash
# Run every skill-triggering test case. Slow: ~30s-5min per case, 15 cases.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

declare -a CASES=(
    "feature-state-keeper:state-drift.txt"
    "anti-hallucination-gates:claim-without-evidence.txt"
    "cpp-build-systems:cpp-build-failure.txt"
    "docs-lookup:docs-lookup.txt"
    "project-indexing:project-indexing.txt"
    "init-verification:init-verification.txt"
    "self-correction-loop:self-correction-loop.txt"
    "context-budget-discipline:context-budget.txt"
    "cpp-static-analysis:cpp-static-analysis.txt"
    "cpp-static-analysis:cpp-static-analysis-tool-missing.txt"
    "cpp-formatting:cpp-formatting.txt"
    "cpp-sanitizers:cpp-sanitizers.txt"
    "test-coverage-design:test-coverage-design.txt"
    "capturing-golden-rules:capturing-golden-rules.txt"
    # Measured 2026-07-29 — a registered case is not necessarily a reliably
    # passing one. This case held 2/3 PASS against the v0.17.0 bidirectional
    # description; claim-without-evidence.txt held 3/3 in the same session.
    #
    # Read those numbers with the baseline, or they imply a causal claim the
    # data does not support: the SAME negative prompt also triggered against
    # the v0.16.0 description, which contained no negative keyword at all
    # (N=1, PASS). So 2/3 is not evidence that adding negative triggers to the
    # description improved triggering — whatever selects this skill on a
    # negative prompt, these runs do not show it to be the description's
    # keywords. Deciding that needs an eval far larger than 3 runs per arm;
    # until someone runs one, do not re-tune this description on a mechanistic
    # hypothesis (CLAUDE.md rule 2).
    "anti-hallucination-gates:negative-claim-unverified.txt"
)
# scope-jump.txt tests the UserPromptSubmit hook rather than skill invocation
# (it doesn't map cleanly to a single skill).

PASS=0
FAIL=0
SKIP=0

for case in "${CASES[@]}"; do
    skill="${case%%:*}"
    prompt="${case##*:}"
    prompt_path="$SCRIPT_DIR/prompts/$prompt"

    echo ""
    echo "================================================================"
    echo " Case: $skill ← $prompt"
    echo "================================================================"

    if [ ! -f "$prompt_path" ]; then
        echo "[SKIP] prompt file missing: $prompt_path"
        SKIP=$((SKIP+1))
        continue
    fi

    if bash "$SCRIPT_DIR/run-test.sh" "$skill" "$prompt_path"; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
    fi
done

echo ""
echo "================================================================"
echo " Summary: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
echo "================================================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
