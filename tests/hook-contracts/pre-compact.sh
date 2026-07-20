#!/usr/bin/env bash
# Contract test for hooks/pre-compact (v0.15.0): forensics marker + stale-handoff
# systemMessage. Warn-only: never blocks, silent on unanchored/malformed input.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/pre-compact"

PASS=0; FAIL=0
ok()  { echo "  OK   $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }
assert_contains() {
    if printf '%s' "$2" | grep -q "$1"; then ok "contains: $1"
    else bad "missing: $1 (in: $(printf '%s' "$2" | head -c 200))"; fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR" || exit 1
git init -q .; git config user.email t@e.com; git config user.name t
printf '{ "project": "pc-fixture", "features": [] }\n' > feature_list.json
tr="$TMPDIR/tr.jsonl"; printf 'transcript-body\n' > "$tr"

mkev() { # $1 = trigger
    printf '{"session_id":"s-pc","transcript_path":"%s","cwd":"%s","hook_event_name":"PreCompact","trigger":"%s"}' "$tr" "$TMPDIR" "$1"
}
META="$TMPDIR/.harness-anchor/last-compact.meta"

echo "=== no handoff file -> meta written + systemMessage (absent) ==="
o1=$(mkev auto | bash "$HOOK" 2>/dev/null || true)
assert_contains "systemMessage" "$o1"
assert_contains "absent" "$o1"
assert_contains "compaction imminent (auto)" "$o1"
if [ -f "$META" ]; then
    ok "meta written"
    for k in ts epoch trigger tbytes branch dirty handoff_age_min; do
        grep -q "^${k}=" "$META" && ok "meta has $k" || bad "meta missing $k"
    done
    grep -q '^trigger=auto$' "$META" && ok "trigger recorded" || bad "trigger wrong: $(grep '^trigger=' "$META")"
    grep -q '^handoff_age_min=absent$' "$META" && ok "handoff absent recorded" || bad "handoff_age_min wrong"
else
    bad "meta not written"
fi

echo ""
echo "=== fresh handoff -> meta updated, NO systemMessage ==="
printf '# handoff\n' > session-handoff.md
o2=$(mkev manual | bash "$HOOK" 2>/dev/null || true)
if [ -z "$o2" ]; then ok "silent on fresh handoff"; else bad "unexpected output: $(printf '%s' "$o2" | head -c 200)"; fi
grep -q '^trigger=manual$' "$META" && ok "meta overwritten (manual)" || bad "meta not overwritten"
grep -q '^handoff_age_min=0$' "$META" && ok "age 0 recorded" || bad "age wrong: $(grep '^handoff_age_min=' "$META")"

echo ""
echo "=== stale handoff (mtime pushed back) -> systemMessage with N min stale ==="
touch -t 202601010000 session-handoff.md
o3=$(mkev auto | bash "$HOOK" 2>/dev/null || true)
assert_contains "min stale" "$o3"

echo ""
echo "=== unanchored cwd -> silent, no meta ==="
UN=$(mktemp -d)
o4=$(printf '{"session_id":"s-un","transcript_path":"","cwd":"%s","trigger":"auto"}' "$UN" | bash "$HOOK" 2>/dev/null || true)
if [ -z "$o4" ]; then ok "unanchored silent"; else bad "unanchored emitted"; fi
[ ! -e "$UN/.harness-anchor/last-compact.meta" ] && ok "no meta in unanchored dir" || bad "meta created in unanchored dir"
rm -rf "$UN"

echo ""
echo "=== malformed stdin -> exit 0, silent ==="
o5=$(printf '{oops' | bash "$HOOK" 2>/dev/null || true)
if [ -z "$o5" ]; then ok "malformed silent"; else bad "malformed emitted"; fi

echo ""
echo "==================================="
echo " Pass: $PASS    Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
