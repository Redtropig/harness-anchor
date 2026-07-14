#!/usr/bin/env bash
# Unit test for scripts/golden-rules-check.sh — tier precedence, three-state
# verdicts (CLEAN / FINDINGS / CHECK-ERROR incl. timeout), --count, edge files.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GRC="$PLUGIN_ROOT/scripts/golden-rules-check.sh"

PASS=0; FAIL=0
expect_contains() { # <label> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "  OK   $1"; PASS=$((PASS+1));;
    *)      echo "  FAIL $1 → missing '$2' in output"; echo "---"; printf '%s\n' "$3" | head -20; echo "---"; FAIL=$((FAIL+1));;
  esac
}
expect_not_contains() { # <label> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "  FAIL $1 → unexpected '$2'"; FAIL=$((FAIL+1));;
    *)      echo "  OK   $1"; PASS=$((PASS+1));;
  esac
}

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT

# ---- fixture: 7 rules covering every tier/verdict ----
mkdir -p "$ROOT/proj/src"
printf 'clean code\n' > "$ROOT/proj/src/ok.txt"
i=1; while [ $i -le 12 ]; do echo "line $i: TODO fix" >> "$ROOT/proj/notes.txt"; i=$((i+1)); done
cat > "$ROOT/proj/golden-rules.md" <<'EOF'
# Golden Rules — proj

## Rules

### GR-1 — no forbidden token in src
- **Why / origin:** shipped one once.
- **Check:** `grep -rn "FORBIDDEN" src/` returns nothing unexpected.

### GR-2 — no TODO pileup
- **Why / origin:** TODOs rotted.
- **Check:** `grep -n "TODO" notes.txt` should stay empty.

### GR-3 — tool must exist
- **Why / origin:** broken check once.
- **Check:** `nonexistent-cmd-xyz --scan`

### GR-4 — bounded check runtime
- **Why / origin:** a hung check.
- **Check:** `sleep 10`

### GR-5 — error handling style
- **Why / origin:** inconsistent handlers.
- **Check:** manual review of changed handlers.

### GR-6 — precedence pin
- **Why / origin:** backticks inside a manual note.
- **Check:** Manual review of `foo()` call sites.

### GR-7 — no check command
- **Why / origin:** eyeball rule.
- **Check:** eyeball the diff.
EOF

t0=$(date +%s)
out=$(bash "$GRC" --target "$ROOT/proj")
t1=$(date +%s)

expect_contains "header counts"        "## Golden-rules check — 7 rule(s), 4 mechanical" "$out"
expect_contains "GR-1 clean"           'GR-1 [MECH] CLEAN' "$out"
expect_contains "GR-2 findings count"  'GR-2 [MECH] FINDINGS(12 line(s), first 10 shown)' "$out"
expect_contains "GR-2 evidence line"   '    1:line 1: TODO fix' "$out"
expect_not_contains "GR-2 truncated"   'line 11: TODO fix' "$out"
expect_contains "GR-3 check-error"     'GR-3 [MECH] CHECK-ERROR (exit 127)' "$out"
expect_contains "GR-4 timeout"         'GR-4 [MECH] CHECK-ERROR (timeout >5s)' "$out"
expect_contains "GR-5 manual"          'GR-5 [MANUAL] error handling style' "$out"
expect_contains "GR-6 manual beats backticks" 'GR-6 [MANUAL] precedence pin' "$out"
expect_contains "GR-7 no-span manual"  'GR-7 [MANUAL] no check command' "$out"
# timeout bounded: whole run must finish well under GR-4's sleep 10
if [ $((t1 - t0)) -lt 9 ]; then echo "  OK   watchdog bounds GR-4"; PASS=$((PASS+1)); else echo "  FAIL watchdog: run took $((t1-t0))s"; FAIL=$((FAIL+1)); fi

expect_contains "--count" "7 4" "$(bash "$GRC" --target "$ROOT/proj" --count)"

# ---- absent file ----
mkdir -p "$ROOT/none"
expect_contains "absent file"        "no golden-rules.md" "$(bash "$GRC" --target "$ROOT/none")"
expect_contains "absent file count"  "0 0" "$(bash "$GRC" --target "$ROOT/none" --count)"

# ---- template state: file exists, zero GR entries ----
mkdir -p "$ROOT/tpl"
printf '# Golden Rules — x\n\n## Rules\n\n_No rules yet._\n' > "$ROOT/tpl/golden-rules.md"
expect_contains "zero rules header"  "0 rule(s), 0 mechanical" "$(bash "$GRC" --target "$ROOT/tpl")"
expect_contains "zero rules count"   "0 0" "$(bash "$GRC" --target "$ROOT/tpl" --count)"

echo ""; echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
