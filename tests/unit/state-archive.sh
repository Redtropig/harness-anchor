#!/usr/bin/env bash
# Unit test for scripts/state-archive.mjs — checkpoint archival of hot state files.
#
# Pins the safety contract from the v0.9.0 design:
#   1. under-window files are untouched ("nothing to archive", byte-identical)
#   2. progress.md: keep newest 20 sections, move the rest (verbatim) to progress-archive.md
#   3. feature_list.json: keep non-pass + 10 newest pass, move the rest with evidence intact
#   4. --dry-run reports but writes nothing
#   5. idempotent: a second run is a no-op
#   6. malformed JSON -> exit 1, no writes
#   7. same id in archive with DIFFERENT content -> abort, no writes
#   8. crash residue (identical content already archived) -> converges (hot shrinks)
#   9. repeat archival prepends newer block above older archive content
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARCHIVE="$PLUGIN_ROOT/scripts/state-archive.mjs"

PASS=0; FAIL=0
ok()  { echo "  OK   $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

command -v node >/dev/null 2>&1 || { echo "SKIP: node not found"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not found"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# make_progress <dir> <n-sections>  — newest-first: Session <n> at top ... Session 1 at bottom
make_progress() {
    local dir="$1" n="$2"
    {
        echo '# Progress Log'
        echo ''
        echo '> Append-only history of agent sessions. Most-recent first.'
        echo ''
        echo '---'
        local i="$n"
        while [ "$i" -ge 1 ]; do
            printf '\n## 2026-06-%02d 10:00 — Session %d\n\n**Active feature**: f\n\n### Accomplished\n- work item %d\n' "$(( (i % 28) + 1 ))" "$i" "$i"
            i=$((i-1))
        done
    } > "$dir/progress.md"
}

# make_features <dir> <n-pass>  — plus 1 in-progress + 1 planned; pass completedAt ascending by index
make_features() {
    local dir="$1" npass="$2"
    N="$npass" python3 - "$dir/feature_list.json" <<'PY'
import json, os, sys
n = int(os.environ['N'])
feats = [
  {"id": "live-core", "name": "L", "description": "d", "status": "in-progress",
   "done_criteria": ["x"], "evidence": None, "createdAt": "2026-01-01T00:00:00Z", "completedAt": None},
  {"id": "todo-next", "name": "P", "description": "d", "status": "planned",
   "done_criteria": ["x"], "evidence": None, "createdAt": "2026-01-02T00:00:00Z", "completedAt": None},
]
for i in range(1, n + 1):
    feats.append({
        "id": f"done-{i:02d}", "name": f"D{i}", "description": "d", "status": "pass",
        "done_criteria": ["x"],
        "evidence": {"timestamp": f"2026-02-{(i % 28) + 1:02d}T00:00:00Z", "commit": "abc123",
                     "artifacts": [f"logs/run-{i}.txt"], "notes": f"n{i}"},
        "createdAt": "2026-01-01T00:00:00Z",
        "completedAt": f"2026-03-01T{i:02d}:00:00Z" if i <= 23 else f"2026-03-02T{i - 23:02d}:00:00Z",
    })
json.dump({"project": "t", "features": feats}, open(sys.argv[1], "w"), indent=2)
open(sys.argv[1], "a").write("\n")
PY
}

sha() { shasum "$1" | awk '{print $1}'; }

echo "=== 1. under window -> nothing to archive, byte-identical ==="
D="$TMP/u"; mkdir -p "$D"; make_progress "$D" 5; make_features "$D" 3
b1=$(sha "$D/progress.md"); b2=$(sha "$D/feature_list.json")
out=$(node "$ARCHIVE" --target "$D" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "exit 0" || bad "exit $rc: $out"
printf '%s' "$out" | grep -q 'nothing to archive' && ok "reports nothing to archive" || bad "missing marker: $out"
[ "$(sha "$D/progress.md")" = "$b1" ] && ok "progress.md untouched" || bad "progress.md changed"
[ "$(sha "$D/feature_list.json")" = "$b2" ] && ok "feature_list.json untouched" || bad "feature_list.json changed"
[ ! -f "$D/progress-archive.md" ] && ok "no archive created" || bad "archive created under window"

echo "=== 2+3. over window -> correct split, verbatim move ==="
D="$TMP/o"; mkdir -p "$D"; make_progress "$D" 25; make_features "$D" 15
out=$(node "$ARCHIVE" --target "$D" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "exit 0" || bad "exit $rc: $out"
grep -q '## .*Session 6$' "$D/progress.md" && ok "hot keeps Session 6 (20th newest)" || bad "Session 6 missing from hot"
grep -q '## .*Session 5$' "$D/progress.md" && bad "Session 5 still hot" || ok "Session 5 moved out"
grep -q '## .*Session 5$' "$D/progress-archive.md" && ok "archive has Session 5" || bad "archive missing Session 5"
grep -q '## .*Session 1$' "$D/progress-archive.md" && ok "archive has Session 1" || bad "archive missing Session 1"
grep -q 'work item 3' "$D/progress-archive.md" && ok "section bodies moved verbatim" || bad "section body lost"
grep -q 'progress-archive.md' "$D/progress.md" && ok "hot header gained pointer line" || bad "no pointer line"
python3 - "$D/feature_list.json" "$D/feature_archive.json" <<'PY' && ok "feature split correct" || bad "feature split wrong"
import json, sys
hot = json.load(open(sys.argv[1])); arch = json.load(open(sys.argv[2]))
hot_ids = [f["id"] for f in hot["features"]]
arch_ids = [f["id"] for f in arch["features"]]
assert "live-core" in hot_ids and "todo-next" in hot_ids, "non-pass lost"
assert sum(1 for f in hot["features"] if f["status"] == "pass") == 10, "hot pass != 10"
assert sorted(arch_ids) == [f"done-{i:02d}" for i in range(1, 6)], f"archived wrong set: {arch_ids}"
assert all(f["evidence"] is not None for f in arch["features"]), "evidence stripped"
assert arch["$schema"] == "./feature_list.schema.json" and arch["project"] == "t", "archive top-level shape"
PY

echo "=== 5. idempotent second run ==="
a1=$(sha "$D/progress.md"); a2=$(sha "$D/progress-archive.md"); a3=$(sha "$D/feature_list.json"); a4=$(sha "$D/feature_archive.json")
out=$(node "$ARCHIVE" --target "$D" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'nothing to archive'; then ok "second run is a no-op"; else bad "second run not clean: rc=$rc $out"; fi
[ "$(sha "$D/progress.md")" = "$a1" ] && [ "$(sha "$D/progress-archive.md")" = "$a2" ] \
  && [ "$(sha "$D/feature_list.json")" = "$a3" ] && [ "$(sha "$D/feature_archive.json")" = "$a4" ] \
  && ok "all four files byte-stable" || bad "second run produced a diff"

echo "=== 9. repeat archival prepends newer block above older ==="
# grow hot again: prepend 6 newer sections (Sessions 26..31) after the header
python3 - "$D/progress.md" <<'PY'
import sys
p = sys.argv[1]
text = open(p).read().split('\n')
sep = next(i for i, l in enumerate(text) if l.strip() == '---')
block = []
for s in range(31, 25, -1):
    block += [f'## 2026-07-01 10:00 — Session {s}', '', f'- newer work {s}', '']
out = text[:sep + 1] + [''] + block + text[sep + 1:]
open(p, 'w').write('\n'.join(out))
PY
node "$ARCHIVE" --target "$D" >/dev/null 2>&1
# now Sessions 6..11 (oldest of the 26 hot ones) moved; archive must have Session 6 ABOVE Session 5
l_new=$(grep -n 'Session 6$' "$D/progress-archive.md" | head -1 | cut -d: -f1)
l_old=$(grep -n 'Session 5$' "$D/progress-archive.md" | head -1 | cut -d: -f1)
if [ -n "$l_new" ] && [ -n "$l_old" ] && [ "$l_new" -lt "$l_old" ]; then
    ok "newer archived block sits above older (newest-archived-first)"
else
    bad "archive ordering wrong (Session 6 at ${l_new:-?}, Session 5 at ${l_old:-?})"
fi

echo "=== 4. --dry-run writes nothing ==="
D="$TMP/d"; mkdir -p "$D"; make_progress "$D" 25; make_features "$D" 15
b1=$(sha "$D/progress.md"); b2=$(sha "$D/feature_list.json")
out=$(node "$ARCHIVE" --dry-run --target "$D" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "dry-run exit 0" || bad "dry-run exit $rc"
printf '%s' "$out" | grep -q 'dry-run: no files written' && ok "dry-run marker" || bad "no dry-run marker: $out"
printf '%s' "$out" | grep -q 'keep 20' && ok "dry-run reports progress backlog" || bad "no progress report: $out"
[ "$(sha "$D/progress.md")" = "$b1" ] && [ "$(sha "$D/feature_list.json")" = "$b2" ] \
  && [ ! -f "$D/progress-archive.md" ] && [ ! -f "$D/feature_archive.json" ] \
  && ok "dry-run wrote nothing" || bad "dry-run mutated files"

echo "=== 6. malformed JSON -> exit 1, no writes ==="
D="$TMP/bad"; mkdir -p "$D"; make_progress "$D" 25
printf '{ not json' > "$D/feature_list.json"
b1=$(sha "$D/progress.md")
out=$(node "$ARCHIVE" --target "$D" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "exit 1 on bad JSON" || bad "expected exit 1, got $rc"
[ "$(sha "$D/progress.md")" = "$b1" ] && [ ! -f "$D/progress-archive.md" ] \
  && ok "nothing written on bad JSON (progress untouched too)" || bad "wrote despite bad JSON"

echo "=== 7. id conflict with different content -> abort ==="
D="$TMP/c"; mkdir -p "$D"; make_features "$D" 15
printf '{ "project": "t", "features": [ { "id": "done-01", "name": "DIFFERENT", "description": "d", "status": "pass", "done_criteria": ["x"], "evidence": {"timestamp": "2026-01-01T00:00:00Z", "commit": "zzz", "artifacts": ["a"]}, "createdAt": "2026-01-01T00:00:00Z", "completedAt": "2026-01-01T00:00:00Z" } ] }\n' > "$D/feature_archive.json"
b1=$(sha "$D/feature_list.json"); b2=$(sha "$D/feature_archive.json")
out=$(node "$ARCHIVE" --target "$D" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "exit 1 on content conflict" || bad "expected exit 1, got $rc: $out"
printf '%s' "$out" | grep -q 'done-01' && ok "conflict names the id" || bad "id not named: $out"
[ "$(sha "$D/feature_list.json")" = "$b1" ] && [ "$(sha "$D/feature_archive.json")" = "$b2" ] \
  && ok "no writes on conflict" || bad "conflict run mutated files"

echo "=== 8. crash residue (identical copy already archived) -> converges ==="
D="$TMP/r"; mkdir -p "$D"; make_features "$D" 15
node "$ARCHIVE" --target "$D" >/dev/null 2>&1          # normal archival
# simulate crash: restore the PRE-archival hot file (movers present in BOTH files now)
make_features "$D" 15
out=$(node "$ARCHIVE" --target "$D" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "recovery run exits 0" || bad "recovery exit $rc: $out"
python3 - "$D/feature_list.json" "$D/feature_archive.json" <<'PY' && ok "converged: hot shrunk, archive single-copy" || bad "recovery did not converge"
import json, sys
hot = json.load(open(sys.argv[1])); arch = json.load(open(sys.argv[2]))
assert sum(1 for f in hot["features"] if f["status"] == "pass") == 10
ids = [f["id"] for f in arch["features"]]
assert len(ids) == len(set(ids)) == 5, f"archive not single-copy: {ids}"
PY

echo "=== 10. duplicate-id ledger -> refuse (never operate on corrupt input) ==="
# Both copies of 'dup-x' are the oldest pass entries (=> both would move); unguarded
# archival would write a duplicate id into the archive. The tool must refuse instead.
D="$TMP/dup"; mkdir -p "$D"
python3 - "$D/feature_list.json" <<'PY'
import json, sys
feats = []
for i in range(1, 13):
    fid = "dup-x" if i in (1, 2) else f"done-{i:02d}"
    feats.append({"id": fid, "name": f"D{i}", "description": "d", "status": "pass",
                  "done_criteria": ["x"],
                  "evidence": {"timestamp": f"2026-02-{i:02d}T00:00:00Z", "commit": "c", "artifacts": ["a.log"]},
                  "createdAt": "2026-01-01T00:00:00Z", "completedAt": f"2026-03-01T{i:02d}:00:00Z"})
json.dump({"project": "adv", "features": feats}, open(sys.argv[1], "w"), indent=2)
PY
b1=$(sha "$D/feature_list.json")
out=$(node "$ARCHIVE" --target "$D" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "exit 1 on duplicate-id ledger" || bad "expected exit 1, got $rc: $out"
printf '%s' "$out" | grep -q 'dup-x' && ok "refusal names the duplicated id" || bad "id not named: $out"
[ "$(sha "$D/feature_list.json")" = "$b1" ] && [ ! -f "$D/feature_archive.json" ] \
  && ok "no writes on duplicate-id ledger" || bad "wrote despite corrupt ledger"

echo ""
echo "==================================="
echo " Pass: $PASS    Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
