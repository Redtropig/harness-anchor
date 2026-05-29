#!/usr/bin/env bash
# toc-freshness.sh — Check freshness of PROJECT-TOC.md against git state.
#
# Extracted from hooks/session-start (DD5) so /status and other consumers
# can share the same logic without divergence.
#
# Usage: bash toc-freshness.sh <project-dir>
#
# Output: one line — <status-word> [<detail>]
#   absent         — no PROJECT-TOC.md found
#   no-anchor      — TOC exists but lacks a valid commit anchor
#   not-git        — project dir is not a git repo
#   fresh (<sha>)  — anchor commit matches HEAD, no working-tree changes
#   stale (<N> file(s) changed since anchor <sha>)
#
# Exit 0 always (non-blocking by design).

set -uo pipefail

PROJECT_DIR="${1:-.}"

toc_file="$PROJECT_DIR/PROJECT-TOC.md"

if [ ! -f "$toc_file" ]; then
    echo "absent"
    exit 0
fi

# Extract the commit SHA from the TOC header.
# Pattern allows underscores for placeholder SHAs (e.g. PLACEHOLDER_COMMIT_SHA).
anchor_commit=$(grep -oE 'generated-at-commit:[[:space:]]*[A-Za-z0-9_]+' "$toc_file" 2>/dev/null | head -1 | awk '{print $NF}' || true)

if [ -z "$anchor_commit" ] || [ "$anchor_commit" = "PLACEHOLDER_COMMIT_SHA" ]; then
    echo "no-anchor"
    exit 0
fi

if ! (cd "$PROJECT_DIR" && git rev-parse --git-dir >/dev/null 2>&1); then
    echo "not-git"
    exit 0
fi

# Verify the anchor commit exists in this repo before diffing.
if ! (cd "$PROJECT_DIR" && git cat-file -t "$anchor_commit" >/dev/null 2>&1); then
    echo "no-anchor"
    exit 0
fi

# Count committed changes since anchor + working-tree changes.
cc=$(cd "$PROJECT_DIR" && git diff --name-only "$anchor_commit" HEAD 2>/dev/null | wc -l | tr -d ' ') || cc=0
wc_=$(cd "$PROJECT_DIR" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ') || wc_=0
# Sanitize: ensure numeric-only (strip stray whitespace/newlines).
cc=$(printf '%s' "$cc" | tr -cd '0-9') ; cc="${cc:-0}"
wc_=$(printf '%s' "$wc_" | tr -cd '0-9') ; wc_="${wc_:-0}"
total=$((cc + wc_))

if [ "$total" -eq 0 ]; then
    echo "fresh ($anchor_commit)"
else
    echo "stale ($total file(s) changed since anchor $anchor_commit)"
fi

exit 0
