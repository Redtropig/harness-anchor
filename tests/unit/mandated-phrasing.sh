#!/usr/bin/env bash
# mandated-phrasing.sh — The negative-capability wording rule spans six files
# and was, through v0.16.0, held together by instruction alone. v0.16.0's own
# review found it drifted (finding M6: four sites, three wordings), and its
# release then drifted AGAIN between commands/cpp-init.md and the docs/ page
# that restates it (caadb8e -> 5963123). This makes it mechanical.
#
# docs/commands.md is on the list precisely because it is the site that has
# actually drifted twice. A checklist that omits the file with the worst track
# record certifies the wrong thing.
#
# The rule: a negative capability conclusion is written
#     searched <scope>, not found (as of <YYYY-MM-DD>)
# so it carries BOTH its search scope and its observation date. The literal
# `not found (as of ` is the anchor every site must share.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PLUGIN_ROOT" || exit 1

PASS=0; FAIL=0
ok()   { echo "  OK   $*"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

# ---- 1. every site carries the dated mandated form ----
# A plain `for` in the CURRENT shell — not `printf | while`, whose body runs in
# a subshell where PASS/FAIL increments are discarded and the summary silently
# reports 0 failures no matter what happened.
for f in commands/cpp-init.md \
         docs/commands.md \
         skills/cpp-static-analysis/SKILL.md \
         skills/cpp-formatting/SKILL.md \
         templates/AGENTS.md.tpl \
         skills/anti-hallucination-gates/SKILL.md
do
    if [ ! -f "$f" ]; then bad "site missing: $f"; continue; fi
    if grep -qF 'not found (as of ' "$f"; then ok "dated mandated form: $f"
    else bad "dated mandated form absent: $f"; fi
done

# ---- 2. the scaffolded artefacts must not EMIT banned phrasing ----
# Templates become someone else's committed files; a banned phrase there is a
# stale assertion frozen into their repo. (Prose that QUOTES the ban in order to
# state it is fine — that is why only templates/ is swept, not the skills.)
banned_hits=$(grep -rniE 'not installed|on this machine' templates/ 2>/dev/null || true)
if [ -z "$banned_hits" ]; then ok "templates/ emit no banned phrasing"
else bad "templates/ emit banned phrasing:"; printf '%s\n' "$banned_hits"; fi

# ---- 3. init-verification must actually reference the re-check ----
if grep -qF 'not found (as of ' skills/init-verification/SKILL.md; then
    ok "init-verification references the dated form it re-checks"
else
    bad "init-verification does not reference the dated form"
fi

echo ""
echo "mandated-phrasing: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
