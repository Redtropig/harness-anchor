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
