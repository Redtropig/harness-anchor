#!/usr/bin/env bash
# check-allowed-tools.sh — Validate the `allowed-tools` frontmatter of slash-command
# files (R4). SHAPE validation only.
#
# It asserts that a command declares an `allowed-tools:` line whose value is a
# comma-separated list of tool-name-shaped tokens. It deliberately does NOT check
# tokens against a hard-coded tool registry: that list changes constantly, so a
# registry check would falsely fail the day a new built-in tool ships. Shape, not
# membership, is the durable invariant.
#
# A "tool-name-shaped token" is an identifier (letter/underscore start, then
# letters/digits/underscores — covers `Read`, `AskUserQuestion`, and MCP names
# like `mcp__server__tool`) with an OPTIONAL parenthesised scope suffix that
# Claude Code permits in allowed-tools (e.g. `Bash(git diff:*)`).
#
# Known limitation: the separator is a literal comma, so a scope that itself
# contains a comma (rare, e.g. `Bash(git diff a,b)`) would be mis-split. The
# plan defines allowed-tools as a comma-separated list, so this is by design.
#
# SINGLE SOURCE OF TRUTH: both scripts/validate-anchor.sh (real commands) and the
# negative-fixture CI step call this script, so the rule can never drift.
#
# Usage:
#   check-allowed-tools.sh <command.md>      # validate one file: prints PASS or "FAIL: <reason>"
#   check-allowed-tools.sh --fixtures <dir>  # validate every *.md: bad-*.md must FAIL, others must PASS
#
# Exit 0 = OK, 1 = a violation (or, in --fixtures mode, a fixture behaved unexpectedly).

set -uo pipefail

# ---- Validate a single command file's allowed-tools shape. ----
# Echoes "PASS" or "FAIL: <reason>"; returns 0 / 1.
check_one() {
    local file="$1"

    if [ ! -f "$file" ]; then
        echo "FAIL: not a file: $file"
        return 1
    fi

    # Frontmatter must open with --- on line 1 (mirrors validate-anchor.sh).
    if ! head -1 "$file" | grep -q '^---$'; then
        echo "FAIL: missing frontmatter opener"
        return 1
    fi

    # Presence: is there an allowed-tools line inside the first frontmatter block?
    local has_line
    has_line=$(awk '/^---$/{c++; next} c==1 && /^allowed-tools:/{print "yes"; exit}' "$file")
    if [ -z "$has_line" ]; then
        echo "FAIL: missing allowed-tools"
        return 1
    fi

    # Value: everything after the colon (mirrors the description extractor).
    local value
    value=$(awk '/^---$/{c++; next} c==1 && /^allowed-tools:/{sub(/^allowed-tools:[[:space:]]*/,""); print; exit}' "$file")
    value="${value%$'\r'}"                       # strip trailing CR (CRLF files)
    value="${value%"${value##*[![:space:]]}"}"   # strip trailing whitespace

    if [ -z "$value" ]; then
        echo "FAIL: empty allowed-tools"
        return 1
    fi

    # Split on commas (read -ra does NOT glob-expand, so a `*` in a scope is safe).
    local toks raw tok
    local IFS=','
    read -ra toks <<< "$value"
    for raw in "${toks[@]}"; do
        tok="${raw#"${raw%%[![:space:]]*}"}"     # ltrim
        tok="${tok%"${tok##*[![:space:]]}"}"     # rtrim
        if [ -z "$tok" ]; then
            echo "FAIL: empty token (stray/trailing comma) in '$value'"
            return 1
        fi
        if [[ ! "$tok" =~ ^[A-Za-z_][A-Za-z0-9_]*(\(.*\))?$ ]]; then
            echo "FAIL: malformed tool token '$tok'"
            return 1
        fi
    done

    echo "PASS"
    return 0
}

# ---- --fixtures mode: bad-*.md must be rejected, everything else must pass. ----
run_fixtures() {
    local dir="$1"
    local pass_count=0 fail_count=0 status=0

    echo "=== check-allowed-tools (fixture test) ==="
    echo "Root: $dir"
    echo ""

    if [ ! -d "$dir" ]; then
        echo "  FAIL  fixtures dir not found: $dir"
        echo "==================================="
        echo " STATUS: FAILED"
        return 1
    fi

    local f base result
    for f in "$dir"/*.md; do
        [ -e "$f" ] || continue
        base=$(basename "$f")
        result=$(check_one "$f")
        case "$base" in
            bad-*)
                if printf '%s' "$result" | grep -q '^FAIL'; then
                    echo "  OK    $base correctly rejected ($result)"
                    pass_count=$((pass_count+1))
                else
                    echo "  FAIL  $base should be rejected but passed"
                    fail_count=$((fail_count+1)); status=1
                fi
                ;;
            *)
                if printf '%s' "$result" | grep -q '^PASS'; then
                    echo "  OK    $base correctly accepted"
                    pass_count=$((pass_count+1))
                else
                    echo "  FAIL  $base should pass but: $result"
                    fail_count=$((fail_count+1)); status=1
                fi
                ;;
        esac
    done

    echo ""
    echo "==================================="
    echo " Pass: $pass_count    Fail: $fail_count"
    if [ "$status" -eq 0 ]; then echo " STATUS: PASSED"; else echo " STATUS: FAILED"; fi
    return $status
}

# ---- Dispatch ----
case "${1:-}" in
    --fixtures)
        [ $# -ge 2 ] || { echo "usage: check-allowed-tools.sh --fixtures <dir>"; exit 2; }
        run_fixtures "$2"
        ;;
    "")
        echo "usage: check-allowed-tools.sh <command.md> | --fixtures <dir>"
        exit 2
        ;;
    *)
        check_one "$1"
        ;;
esac
