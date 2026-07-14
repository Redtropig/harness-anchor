#!/usr/bin/env bash
# Unit test for scripts/status-report.sh — all 7 sections, unanchored line,
# archive suffix, over-budget marker, and the python3+node degraded path.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SR="$PLUGIN_ROOT/scripts/status-report.sh"

PASS=0; FAIL=0
expect_contains() {
  case "$3" in
    *"$2"*) echo "  OK   $1"; PASS=$((PASS+1));;
    *)      echo "  FAIL $1 → missing '$2'"; echo "---"; printf '%s\n' "$3" | head -30; echo "---"; FAIL=$((FAIL+1));;
  esac
}

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
mkgit() { mkdir -p "$1"; ( cd "$1" || exit 1; git init -q; git config user.email t@e.com; git config user.name t; ); }

# ---- unanchored ----
mkdir -p "$ROOT/bare"
expect_contains "unanchored" "Project not anchored — run /anchor first" "$(bash "$SR" --target "$ROOT/bare")"

# ---- anchored, full state ----
mkgit "$ROOT/proj"
cat > "$ROOT/proj/feature_list.json" <<'EOF'
{ "project": "proj-x",
  "features": [
    {"id":"f-a","name":"Alpha","description":"first","status":"pass"},
    {"id":"f-b","name":"Beta","description":"second thing","status":"in-progress","createdAt":"2026-07-01T00:00:00Z"},
    {"id":"f-c","name":"Gamma","description":"third","status":"planned"}
  ] }
EOF
printf '{ "features": [ {"id":"old-1"}, {"id":"old-2"} ] }\n' > "$ROOT/proj/feature_archive.json"
printf '# Handoff\nline2\n' > "$ROOT/proj/session-handoff.md"
cat > "$ROOT/proj/golden-rules.md" <<'EOF'
## Rules
### GR-1 — a
- **Check:** `true`
### GR-2 — b
- **Check:** manual review.
EOF
mkdir -p "$ROOT/proj/.harness-anchor"
printf '## Drift Report\n\n### Verdict\n- CLEAN — no drift in scope\n' > "$ROOT/proj/.harness-anchor/drift-20260713.md"
( cd "$ROOT/proj" && git add -A && git commit -qm init )
echo dirty > "$ROOT/proj/wip.txt"

out=$(bash "$SR" --target "$ROOT/proj")
expect_contains "header"          "## Status — proj-x" "$out"
expect_contains "active feature"  "- **f-b**: Beta (second thing) — status: in-progress" "$out"
expect_contains "counts planned"  "- planned: 1" "$out"
expect_contains "counts archived" "- pass: 1 (+2 archived)" "$out"
expect_contains "counts blocked"  "- blocked: 0" "$out"
expect_contains "git dirty"       "?? wip.txt" "$out"
expect_contains "toc absent"      "absent" "$out"
expect_contains "handoff head"    "# Handoff" "$out"
expect_contains "gr count"        "- golden rules: 2 rule(s) (1 mechanical)" "$out"
expect_contains "drift verdict"   "— CLEAN" "$out"
expect_contains "feature age"     "day(s) ago" "$out"
expect_contains "budget line"     "feature_list.json" "$out"

# ---- over-budget marker ----
i=0; while [ $i -lt 700 ]; do printf 'padding line to grow the file well past its budget cap....\n'; i=$((i+1)); done >> "$ROOT/proj/session-handoff.md"
out=$(bash "$SR" --target "$ROOT/proj")
expect_contains "over marker" "OVER — /session-end offers archival/trim" "$out"

# ---- degraded: python3 AND node both fail → JSON sections degrade, rest stays ----
SHIM=$(mktemp -d)
printf '#!/bin/sh\nexit 3\n' > "$SHIM/python3"; cp "$SHIM/python3" "$SHIM/node"; chmod +x "$SHIM/python3" "$SHIM/node"
out=$(PATH="$SHIM:$PATH" bash "$SR" --target "$ROOT/proj")
expect_contains "degraded active"  "(needs python3 or node)" "$out"
expect_contains "degraded keeps git section"  "?? wip.txt" "$out"
expect_contains "degraded keeps gr" "- golden rules: 2 rule(s) (1 mechanical)" "$out"
rm -rf "$SHIM"

echo ""; echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
