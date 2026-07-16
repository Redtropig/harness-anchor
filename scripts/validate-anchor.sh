#!/usr/bin/env bash
# validate-anchor.sh — Self-consistency check for the harness-anchor plugin.
# Run inside the plugin root, or pass the plugin root as the first positional
# argument (validate-anchor.sh [plugin-root]); it defaults to the repo root.
#
# Checks (labelled [1/11]..[11/11] in the output):
#   [1/11]   Required top-level files exist (.claude-plugin/plugin.json, hooks/hooks.json, etc.)
#   [2/11]   JSON files parse; scripts/*.mjs pass node --check
#   [3-4/11] Every SKILL.md has name + description frontmatter (description ≤500 chars; see learn-harness gotchas #12)
#   [5/11]   Every agent has name + description frontmatter (≤500 chars) + ends with the single-level constraint line (invariant #3); every evidence-writing agent mkdir -p .harness-anchor before writing (fresh-dir contract — .harness-anchor/ is gitignored, invariant #4)
#   [6/11]   Every command has a description (≤500 chars) + a well-shaped allowed-tools list
#   [7/11]   SessionStart hook is executable and produces valid JSON when run; meta-skill cpp-only regions well-formed + flat (sequenced, non-nested)
#   [8/11]   Commands directory consistency (each commands/*.md is a usable /command)
#   [9/11]   Every template referenced from commands/anchor.md + cpp-init.md AND from scaffold.sh's template map exists
#   [10/11]  Command↔script wiring: the four mechanism scripts exist + executable + bash -n; every ${CLAUDE_PLUGIN_ROOT}/scripts/* referenced by a command/agent md resolves
#   [11/11]  Platform layer (v0.13.0): scripts/lib/portable.sh exists + bash -n; every hook sources it AND calls ha_platform_init (the Windows python3→python→py→node engine-chain wiring)

set -uo pipefail   # no -e so we report all failures, not abort on first

PLUGIN_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$PLUGIN_ROOT" || { echo "FATAL: cannot cd to $PLUGIN_ROOT"; exit 2; }

# Interpreter discovery (v0.13.0): python3 → python → py -3 via the shared lib.
# cwd is $PLUGIN_ROOT here (stable), so the relative lib path resolves. Dev-surface
# scripts REQUIRE an engine; a python-less machine gets a loud NOTE and the
# python-backed checks below fail visibly (intended — CI always has an engine).
HA_LIB_DIR="scripts/lib"
# shellcheck disable=SC1091
. "${HA_LIB_DIR}/portable.sh" 2>/dev/null || true
PYBIN=""
command -v ha_python >/dev/null 2>&1 && PYBIN=$(ha_python || true)
if [ -z "$PYBIN" ]; then
    echo "NOTE: no python interpreter (python3/python/py) found — python-backed checks will fail; install Python or rely on CI." >&2
fi

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
echo "[1/11] Required files..."
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
echo "[2/11] JSON parse + scripts/*.mjs syntax..."
while IFS= read -r f; do
    # shellcheck disable=SC2086
    if [ -n "$PYBIN" ] && $PYBIN -c "import json; json.load(open('$f'))" 2>/dev/null; then
        ok "parse $f"
    else
        fail "invalid JSON: $f"
    fi
done < <(find . -name '*.json' -not -path './node_modules/*' -not -path './.harness-anchor/*' -not -path './tests/manifest-fixtures/*' 2>/dev/null)
# 2c: the skill-local feature-list schema must stay byte-identical to the template.
# It was a git symlink until v0.13.0; symlinks materialize as broken text stubs on
# Windows (core.symlinks=false), so it is now a real copy guarded by this parity
# check instead of the filesystem link (mechanical guarantee replaces the symlink).
SCHEMA_TPL="templates/feature_list.schema.json"
SCHEMA_SKILL="skills/feature-state-keeper/feature-list.schema.json"
if [ -f "$SCHEMA_TPL" ] && [ -f "$SCHEMA_SKILL" ]; then
    if cmp -s "$SCHEMA_TPL" "$SCHEMA_SKILL"; then
        ok "schema parity: $SCHEMA_SKILL == $SCHEMA_TPL"
    else
        fail "schema drift: $SCHEMA_SKILL differs from $SCHEMA_TPL (re-copy the template)"
    fi
else
    fail "schema parity: one of $SCHEMA_TPL / $SCHEMA_SKILL missing"
fi
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
echo "[3-4/11] SKILL.md frontmatter (name + description, ≤500 chars desc)..."
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
echo "[5/11] Agent frontmatter + single-level constraint (invariant #3) + fresh-dir evidence contract (invariant #4)..."
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
echo "[6/11] Command frontmatter (description ≤500 chars + allowed-tools shape)..."
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
echo "[7/11] SessionStart hook smoke test..."
if [ -x hooks/session-start ]; then
    # shellcheck disable=SC2086
    if out=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash hooks/session-start 2>/dev/null) && [ -n "$PYBIN" ] && \
       echo "$out" | $PYBIN -c "import sys,json; d=json.load(sys.stdin); assert 'hookSpecificOutput' in d, 'missing hookSpecificOutput'; assert d['hookSpecificOutput'].get('hookEventName')=='SessionStart'" 2>/dev/null; then
        ok "session-start produces valid SessionStart JSON"
    else
        fail "session-start invalid output: $(echo "$out" | head -c 200)"
    fi
else
    fail "hooks/session-start not executable"
fi
# Injection-source sanity: cpp-only regions in the meta-skill must be FLAT —
# properly ordered, non-nested, closed. The session-start filter is a single
# on/off boolean: a nested pair lets the inner 'end' clear the skip early and
# leak the rest of the outer region into generic injections, and a stray 'end'
# before 'start' swallows the file tail — in both cases raw start/end COUNTS
# still match, so this scan subsumes a plain count balance (miscounts surface
# as "unclosed region" / "end without start").
ms="skills/using-harness-anchor/SKILL.md"
if [ -f "$ms" ]; then
    seq_err=$(awk '
        /^<!-- cpp-only-start -->$/ { if (inr) { printf "nested start at line %d", NR; bad=1; exit } inr=1; n++; next }
        /^<!-- cpp-only-end -->$/   { if (!inr) { printf "end without start at line %d", NR; bad=1; exit } inr=0; next }
        END { if (!bad) { if (inr) printf "unclosed region at EOF"; else printf "OK %d", n } }
    ' "$ms")
    case "$seq_err" in
        OK*) ok "meta-skill cpp-only regions properly sequenced (${seq_err#OK } region(s), flat)" ;;
        *)   fail "meta-skill cpp-only region sequencing: ${seq_err}" ;;
    esac
    # Well-formedness: any line containing 'cpp-only' must be EXACTLY one of the two
    # markers, alone on its line. A malformed variant (e.g. a bare '<!-- cpp-only -->'
    # copied from prose) matches neither awk pattern — it leaks into the injection as
    # text — and the balance count above stays blind to it.
    malformed=$(grep -n 'cpp-only' "$ms" | grep -vE '^[0-9]+:<!-- cpp-only-(start|end) -->$' || true)
    if [ -z "$malformed" ]; then
        ok "meta-skill cpp-only lines are well-formed (exact markers, own line)"
    else
        fail "meta-skill malformed cpp-only line(s) — would slip past the awk filter: $(printf '%s' "$malformed" | head -1)"
    fi
fi
echo ""

# ---- 8. Commands referenced ----
echo "[8/11] Commands directory consistency..."
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
echo "[9/11] Templates referenced by /anchor + /cpp-init..."
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
# 9b: templates referenced by scaffold.sh's map — the thin /anchor + /cpp-init
# no longer name template paths (the map moved into the script), so the
# existence cross-check follows the map or it checks nothing.
if [ -f scripts/scaffold.sh ]; then
    while IFS= read -r tpl; do
        [ -n "$tpl" ] || continue
        if [ -f "templates/$tpl" ]; then
            ok "templates/$tpl (scaffold.sh map)"
        else
            fail "missing template: templates/$tpl (scaffold.sh map)"
        fi
    done < <(grep -oE '[A-Za-z0-9._/-]+\.tpl\|' scripts/scaffold.sh | sed 's/|$//' | sort -u)
    if grep -q 'feature_list\.schema\.json|' scripts/scaffold.sh; then
        if [ -f templates/feature_list.schema.json ]; then
            ok "templates/feature_list.schema.json (scaffold.sh map)"
        else
            fail "missing template: templates/feature_list.schema.json (scaffold.sh map)"
        fi
    fi
fi
echo ""

# ---- 10. Command↔script wiring (thin-wrapper single point) ----
echo "[10/11] Command↔script wiring..."
for s in \
    scripts/golden-rules-check.sh \
    scripts/status-report.sh \
    scripts/scaffold.sh \
    scripts/session-end-precheck.sh
do
    if [ -x "$s" ]; then ok "$s executable"; else fail "$s missing or not executable"; fi
    if [ -f "$s" ] && bash -n "$s" 2>/dev/null; then ok "$s bash -n"; else fail "$s fails bash -n"; fi
done
# Every scripts/* path referenced from commands/ or agents/ must exist —
# a thin wrapper whose script reference rots is a dead command.
while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    if [ -f "$ref" ]; then ok "referenced $ref"; else fail "dangling script reference: $ref (from commands/ or agents/)"; fi
done < <(grep -rhoE '\{CLAUDE_PLUGIN_ROOT\}/scripts/[A-Za-z0-9._-]+' commands/ agents/ 2>/dev/null | sed 's|.*{CLAUDE_PLUGIN_ROOT}/||' | sort -u)
echo ""

# ---- 11. Platform layer wiring (v0.13.0 Windows compatibility) ----
echo "[11/11] Platform layer (scripts/lib/portable.sh) wiring..."
LIB="scripts/lib/portable.sh"
if [ -f "$LIB" ]; then
    ok "$LIB present"
    if bash -n "$LIB" 2>/dev/null; then ok "$LIB bash -n"; else fail "$LIB fails bash -n"; fi
    # portable.sh is the SINGLE source of the engine chain (python3→python→py→node)
    # + platform init. Every automatic hook must route through it — source the lib
    # AND call ha_platform_init — or the Windows engine-agnostic path is not wired
    # and the hook silently reverts to bare `python3`, which fails where only
    # `python`/`py`/`node` exist. Static presence is the invariant; the runtime
    # source is graceful (|| true), but the wiring must be in the file.
    for h in hooks/session-start hooks/post-tool-use hooks/stop hooks/user-prompt-submit; do
        if [ ! -f "$h" ]; then
            fail "missing hook: $h"
            continue
        fi
        if grep -q 'scripts/lib/portable\.sh' "$h"; then ok "$h sources portable.sh"; else fail "$h does not source portable.sh (engine chain unwired)"; fi
        if grep -q 'ha_platform_init' "$h"; then ok "$h calls ha_platform_init"; else fail "$h missing ha_platform_init call"; fi
    done
else
    fail "$LIB missing — the v0.13.0 platform layer is not installed"
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
