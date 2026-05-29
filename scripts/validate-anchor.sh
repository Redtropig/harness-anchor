#!/usr/bin/env bash
# validate-anchor.sh — Self-consistency check for the harness-anchor plugin.
# Run inside the plugin root (or pass --plugin-root <path>).
#
# Checks:
#   1. Required top-level files exist (.claude-plugin/plugin.json, hooks/hooks.json, etc.)
#   2. JSON files parse
#   3. Every SKILL.md has YAML frontmatter with name + description
#   4. Description front-matter is ≤ 500 chars (per learn-harness gotchas #12)
#   5. SessionStart hook is executable and produces valid JSON when run
#   6. Every command referenced in commands/ exists as a file
#   7. Every template referenced from commands/anchor.md exists

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
echo "[2/9] JSON parse..."
for f in $(find . -name '*.json' -not -path './node_modules/*' -not -path './.harness-anchor/*' -not -path './tests/manifest-fixtures/*' 2>/dev/null); do
    if python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
        ok "parse $f"
    else
        fail "invalid JSON: $f"
    fi
done
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
echo "[5/9] Agent frontmatter (name + description, ≤500 chars desc)..."
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

# ---- 9. Templates referenced in /anchor exist ----
echo "[9/9] Templates referenced by /anchor..."
if [ -f commands/anchor.md ]; then
    while IFS= read -r tpl; do
        # Skip directory references (trailing slash) and empty matches
        case "$tpl" in
            */) continue ;;
            "") continue ;;
        esac
        if [ -f "$tpl" ]; then
            ok "$tpl"
        elif [ -d "$tpl" ]; then
            ok "$tpl (dir)"
        else
            fail "missing template: $tpl"
        fi
    done < <(grep -oE 'templates/[A-Za-z0-9._/-]+' commands/anchor.md | sort -u)
else
    warn "commands/anchor.md not present yet — skipping template cross-check"
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
