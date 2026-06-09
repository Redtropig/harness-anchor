#!/usr/bin/env bash
# Unit test for scripts/progress-prepend.mjs — newest-first insert after the header block,
# existing entries intact (append-only), graceful on a headerless file, stdin mode.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PP="$PLUGIN_ROOT/scripts/progress-prepend.mjs"

PASS=0; FAIL=0
ok()  { echo "  OK   $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

command -v node >/dev/null 2>&1 || { echo "SKIP: node not found"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PM="$TMP/progress.md"

cat > "$PM" <<'EOF'
# Progress Log

> Append-only history. Most-recent first.

---

## 2026-01-01 00:00 — Session 1
OLD-ENTRY-MARKER
EOF

printf '## 2026-05-01 12:00 — Session 2\nNEW-ENTRY-MARKER\n' > "$TMP/entry.md"
node "$PP" "$PM" "$TMP/entry.md" || bad "progress-prepend exited non-zero"

# 1. header preserved
if head -1 "$PM" | grep -qF '# Progress Log'; then ok "header preserved"; else bad "header lost"; fi

new_line=$(grep -n 'NEW-ENTRY-MARKER' "$PM" | head -1 | cut -d: -f1)
old_line=$(grep -n 'OLD-ENTRY-MARKER' "$PM" | head -1 | cut -d: -f1)
sep_line=$(grep -n '^---$' "$PM" | head -1 | cut -d: -f1)

# 2. new entry above old (most-recent-first)
if [ -n "$new_line" ] && [ -n "$old_line" ] && [ "$new_line" -lt "$old_line" ]; then
    ok "new entry above old (most-recent-first)"; else bad "ordering wrong (new=$new_line old=$old_line)"; fi

# 3. old entry intact (append-only — nothing deleted)
if grep -qF 'OLD-ENTRY-MARKER' "$PM"; then ok "existing entry intact"; else bad "existing entry dropped"; fi

# 4. new entry sits after the header separator
if [ -n "$sep_line" ] && [ -n "$new_line" ] && [ "$new_line" -gt "$sep_line" ]; then
    ok "entry after header separator"; else bad "entry not after separator (sep=$sep_line new=$new_line)"; fi

# 5. headerless file: safe top-prepend, original content intact
P2="$TMP/p2.md"
printf 'no header here\njust text\n' > "$P2"
printf '## NEWEST\nSTDIN-MARKER\n' | node "$PP" "$P2" - || bad "stdin mode exited non-zero"
sm=$(grep -n 'STDIN-MARKER' "$P2" | head -1 | cut -d: -f1)
nh=$(grep -n 'no header here' "$P2" | head -1 | cut -d: -f1)
if [ -n "$sm" ] && [ -n "$nh" ] && [ "$sm" -lt "$nh" ]; then
    ok "headerless: safe top-prepend, content intact"; else bad "headerless handling wrong (stdin=$sm orig=$nh)"; fi

echo ""
echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
