#!/usr/bin/env bash
# validate-anchor.sh — Self-consistency check for the harness-anchor plugin.
# Run inside the plugin root, or pass the plugin root as the first positional
# argument (validate-anchor.sh [plugin-root]); it defaults to the repo root.
#
# Checks (labelled [1/9]..[9/9] in the output):
#   [1/9]   Required top-level files exist (.claude-plugin/plugin.json, hooks/hooks.json, etc.)
#   [2/9]   JSON files parse; scripts/*.mjs pass node --check
#   [3-4/9] Every SKILL.md has name + description frontmatter (description ≤500 chars; see learn-harness gotchas #12)
#   [5/9]   Every agent has name + description frontmatter (≤500 chars) + ends with the single-level constraint line (invariant #3); every evidence-writing agent mkdir -p .harness-anchor before writing (fresh-dir contract — .harness-anchor/ is gitignored, invariant #4)
#   [6/9]   Every command has a description (≤500 chars) + a well-shaped allowed-tools list
#   [7/9]   SessionStart hook is executable and produces valid JSON when run; meta-skill cpp-only markers balanced
#   [8/9]   Commands directory consistency (each commands/*.md is a usable /command)
#   [9/9]   Every template referenced from commands/anchor.md exists

set -uo pipefail   # no -e so we report all failures, not abort on first

PLUGIN_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$PLUGIN_ROOT" || { echo "FATAL: cannot cd to $PLUGIN_ROOT"; exit 2; }

FAIL=0
PASS_COUNT=0
FAIL_COUNT=0

ok()   { echo "  OK    $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "  FAIL  $*"; FAIL_COUNT=$((FAIL_COUNT+1)); FAIL=1; }
warn() { echo "  WARN  $*"; }

echo "=== harness-anchor validate ==="
echo "Root: $PLUGIN_ROOT"
echo ""

# ---- 1. Required files ----
echo "[1/9] Required files..."
for f in \
    .claude-plugin/plugin.json \
    .claude-plugin/marketplace.json \
    hooks/hooks.json \
    hooks/run-hook.cmd \
    hooks/session-start \
    skills/using-harness-anchor/SKILL.md \
    README.md \
    CLAUDE.md \
    LICENSE \
    .gitignore
do
    if [ -f "$f" ]; then ok "$f"; else fail "missing $f"; fi
done
echo ""

# ---- 2. JSON validity ----
echo "[2/9] JSON parse + scripts/*.mjs syntax..."
while IFS= read -r f; do
    if python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
        ok "parse $f"
    else
        fail "invalid JSON: $f"
    fi
done < <(find . -name '*.json' -not -path './node_modules/*' -not -path './.harness-anchor/*' -not -path './tests/manifest-fixtures/*' 2>/dev/null)
# 2b: Node tools must at least parse (glob, not an enumerated list — enumeration rots).
if command -v node >/dev/null 2>&1; then
    while IFS= read -r mjs; do
        if node --check "$mjs" >/dev/null 2>&1; then
            ok "node --check $mjs"
        else
            fail "syntax error: $mjs (node --check)"
        fi
    done < <(find scripts -name '*.mjs' 2>/dev/null | sort)
else
    warn "node not found — skipping scripts/*.mjs syntax checks"
fi
echo ""

# ---- 3 & 4. SKILL.md frontmatter ----
echo "[3-4/9] SKILL.md frontmatter (name + description, ≤500 chars desc)..."
while IFS= read -r skill; do
    if ! head -1 "$skill" | grep -q '^---$'; then
        fail "$skill: missing frontmatter opener"
        continue
    fi
    name=$(awk '/^---$/{c++; next} c==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$skill")
    desc=$(awk '/^---$/{c++; next} c==1 && /^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$skill")
    if [ -z "$name" ]; then
        fail "$skill: name missing"
    else
        ok "$skill name=$name"
    fi
    if [ -z "$desc" ]; then
        fail "$skill: description missing"
    elif [ "${#desc}" -gt 500 ]; then
        fail "$skill: description ${#desc} chars > 500"
    else
        ok "$skill description ${#desc} chars"
    fi
done < <(find skills -name SKILL.md 2>/dev/null)
echo ""

# ---- 5. Agent frontmatter (name + description) ----
echo "[5/9] Agent frontmatter + single-level constraint (invariant #3) + fresh-dir evidence contract (invariant #4)..."
if [ -d agents ]; then
    while IFS= read -r agent; do
        [ -e "$agent" ] || continue
        if ! head -1 "$agent" | grep -q '^---$'; then
            fail "$agent: missing frontmatter opener"
            continue
        fi
        name=$(awk '/^---$/{c++; next} c==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$agent")
        desc=$(awk '/^---$/{c++; next} c==1 && /^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$agent")
        if [ -z "$name" ]; then
            fail "$agent: name missing"
        else
            ok "$agent name=$name"
        fi
        if [ -z "$desc" ]; then
            fail "$agent: description missing"
        elif [ "${#desc}" -gt 500 ]; then
            fail "$agent: description ${#desc} chars > 500"
        else
            ok "$agent description ${#desc} chars"
        fi
        # Invariant #3: every subagent prompt must end with the single-level constraint.
        if grep -q 'Do not invoke other subagents from this one' "$agent"; then
            ok "$agent single-level constraint"
        else
            fail "$agent: missing single-level constraint line (invariant #3)"
        fi
        # Fresh-dir contract: .harness-anchor/ is gitignored (invariant #4) and no hook
        # creates it, so any agent that writes evidence there must `mkdir -p` it first —
        # otherwise the redirect breaks when that agent runs first in a fresh clone/worktree.
        if grep -q '\.harness-anchor/' "$agent"; then
            if grep -q 'mkdir -p \.harness-anchor' "$agent"; then
                ok "$agent creates .harness-anchor before writing evidence"
            else
                fail "$agent: writes .harness-anchor/ but no 'mkdir -p .harness-anchor' guard (fresh-dir contract)"
            fi
        fi
    done < <(find agents -name '*.md' 2>/dev/null)
else
    warn "no agents/ directory"
fi
echo ""

# ---- 6. Command frontmatter (description, no name required) ----
echo "[6/9] Command frontmatter (description ≤500 chars + allowed-tools shape)..."
if [ -d commands ]; then
    while IFS= read -r cmd; do
        [ -e "$cmd" ] || continue
        if ! head -1 "$cmd" | grep -q '^---$'; then
            fail "$cmd: missing frontmatter opener"
            continue
        fi
        # Commands do NOT have a `name` field — the filename IS the name.
        desc=$(awk '/^---$/{c++; next} c==1 && /^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$cmd")
        if [ -z "$desc" ]; then
            fail "$cmd: description missing"
        elif [ "${#desc}" -gt 500 ]; then
            fail "$cmd: description ${#desc} chars > 500"
        else
            ok "$cmd description ${#desc} chars"
        fi
        # allowed-tools shape (R4) — delegate to the shared single-source validator
        # so the rule can never drift from the negative-fixture CI check.
        at_result=$(bash scripts/check-allowed-tools.sh "$cmd" 2>/dev/null)
        if printf '%s' "$at_result" | grep -q '^PASS'; then
            ok "$cmd allowed-tools shape"
        else
            fail "$cmd allowed-tools: ${at_result#FAIL: }"
        fi
    done < <(find commands -name '*.md' 2>/dev/null)
else
    warn "no commands/ directory"
fi
echo ""

# ---- 7. SessionStart hook smoke test ----
echo "[7/9] SessionStart hook smoke test..."
if [ -x hooks/session-start ]; then
    if out=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash hooks/session-start 2>/dev/null) && \
       echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'hookSpecificOutput' in d, 'missing hookSpecificOutput'; assert d['hookSpecificOutput'].get('hookEventName')=='SessionStart'" 2>/dev/null; then
        ok "session-start produces valid SessionStart JSON"
    else
        fail "session-start invalid output: $(echo "$out" | head -c 200)"
    fi
else
    fail "hooks/session-start not executable"
fi
# Injection-source sanity: cpp-only marker pairs in the meta-skill must balance —
# an unmatched start marker would make the session-start awk filter's skip state
# swallow everything after it in generic projects.
ms="skills/using-harness-anchor/SKILL.md"
if [ -f "$ms" ]; then
    starts=$(grep -c '<!-- cpp-only-start -->' "$ms")
    ends=$(grep -c '<!-- cpp-only-end -->' "$ms")
    if [ "$starts" -eq "$ends" ]; then
        ok "meta-skill cpp-only markers balanced (${starts} region(s))"
    else
        fail "meta-skill cpp-only markers unbalanced: ${starts} start vs ${ends} end"
    fi
fi
echo ""

# ---- 8. Commands referenced ----
echo "[8/9] Commands directory consistency..."
if [ -d commands ]; then
    for cmd in commands/*.md; do
        [ -e "$cmd" ] || continue
        cmd_name=$(basename "$cmd" .md)
        ok "command /$cmd_name"
    done
else
    warn "no commands/ directory (Phase 1 only — OK)"
fi
echo ""

# ---- 9. Templates referenced in /anchor + /cpp-init exist ----
echo "[9/9] Templates referenced by /anchor + /cpp-init..."
found_any_cmd=0
for src in commands/anchor.md commands/cpp-init.md; do
    [ -f "$src" ] || continue
    found_any_cmd=1
    while IFS= read -r tpl; do
        # Skip directory references (trailing slash) and empty matches
        case "$tpl" in
            */) continue ;;
            "") continue ;;
        esac
        if [ -f "$tpl" ]; then
            ok "$tpl ($src)"
        elif [ -d "$tpl" ]; then
            ok "$tpl (dir, $src)"
        else
            fail "missing template: $tpl (referenced by $src)"
        fi
    done < <(grep -oE 'templates/[A-Za-z0-9._/-]+' "$src" | sort -u)
done
if [ "$found_any_cmd" -eq 0 ]; then
    warn "commands/anchor.md and commands/cpp-init.md not present yet — skipping template cross-check"
fi
echo ""

# ---- Summary ----
echo "==================================="
echo " Pass: $PASS_COUNT    Fail: $FAIL_COUNT"
if [ "$FAIL" -eq 0 ]; then
    echo " STATUS: PASSED"
    exit 0
else
    echo " STATUS: FAILED"
    exit 1
fi
