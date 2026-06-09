#!/usr/bin/env bash
# Unit test for the `## Directory map` section in scripts/index-builder.mjs.
# Builds a throwaway git repo with nested dirs and asserts the map's structure + counts,
# that it precedes `## Files`, and that `## Files` is still present (additive change).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IB="$PLUGIN_ROOT/scripts/index-builder.mjs"

PASS=0; FAIL=0
ok()  { echo "  OK   $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

command -v node >/dev/null 2>&1 || { echo "SKIP: node not found"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
git init -q
git config user.email t@e.com
git config user.name t

mkdir -p scripts skills/docs-lookup skills/cpp
printf '# readme\n' > README.md
printf '# a\n'      > scripts/a.sh
printf '# docs\n'   > skills/docs-lookup/SKILL.md
printf '# cpp\n'    > skills/cpp/SKILL.md
git add -A
git commit -qm init

node "$IB" --target "$TMP" >/dev/null 2>&1 || bad "index-builder exited non-zero"
toc="$TMP/PROJECT-TOC.md"

hasline() { if grep -qF -- "$1" "$toc"; then ok "map line: $1"; else bad "missing map line: $1"; fi; }

if grep -qF '## Directory map' "$toc"; then ok "## Directory map present"; else bad "## Directory map missing"; fi
hasline "- \`.\` (root) — 1 file, 2 subdirs"
hasline "- \`scripts/\` — 1 file"
hasline "- \`skills/\` — 0 files, 2 subdirs"
hasline "- \`skills/cpp/\` — 1 file"
hasline "- \`skills/docs-lookup/\` — 1 file"

if grep -qF '## Files' "$toc"; then ok "## Files still present (additive)"; else bad "## Files lost"; fi

# Directory map must precede Files
dm=$(grep -n '## Directory map' "$toc" | head -1 | cut -d: -f1)
fl=$(grep -n '## Files' "$toc" | head -1 | cut -d: -f1)
if [ -n "$dm" ] && [ -n "$fl" ] && [ "$dm" -lt "$fl" ]; then ok "map precedes files"; else bad "map/files order (dm=$dm fl=$fl)"; fi

echo ""
echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
