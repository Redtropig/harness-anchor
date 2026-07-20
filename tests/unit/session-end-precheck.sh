#!/usr/bin/env bash
# Unit test for scripts/session-end-precheck.sh — six fact sections:
# active feature, init.sh result (PASS/FAIL/absent/skip), archival dry-run
# relay, ledger validation relay (duplicate ids), two-column working tree,
# TOC structural-change list.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PC="$PLUGIN_ROOT/scripts/session-end-precheck.sh"

PASS=0; FAIL=0
expect_contains() {
  case "$3" in
    *"$2"*) echo "  OK   $1"; PASS=$((PASS+1));;
    *)      echo "  FAIL $1 → missing '$2'"; echo "---"; printf '%s\n' "$3" | head -30; echo "---"; FAIL=$((FAIL+1));;
  esac
}

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
mkproj() { # $1 = dir
  mkdir -p "$1"; ( cd "$1" || exit 1; git init -q; git config user.email t@e.com; git config user.name t; )
  cat > "$1/feature_list.json" <<'EOF'
{ "project": "p",
  "features": [ {"id":"f-x","name":"X","description":"d","status":"in-progress","createdAt":"2026-07-01T00:00:00Z"} ] }
EOF
  printf '# handoff\n' > "$1/session-handoff.md"
  printf '# Progress\n' > "$1/progress.md"
}

# ---- full pass path ----
mkproj "$ROOT/ok"
printf '#!/bin/sh\necho env ok\nexit 0\n' > "$ROOT/ok/init.sh"; chmod +x "$ROOT/ok/init.sh"
( cd "$ROOT/ok" && git add -A && git commit -qm init )
anchor=$(cd "$ROOT/ok" && git rev-parse HEAD)
printf '<!-- generated-at-commit: %s -->\n# TOC\n' "$anchor" > "$ROOT/ok/PROJECT-TOC.md"
( cd "$ROOT/ok" && git add -A && git commit -qm toc )
echo new > "$ROOT/ok/newfile.c"
echo touch >> "$ROOT/ok/progress.md"

out=$(bash "$PC" --target "$ROOT/ok")
expect_contains "header"        "## Session-end pre-check" "$out"
expect_contains "active id"     "f-x" "$out"
expect_contains "counts"        "in-progress 1" "$out"
expect_contains "init pass"     "init.sh: PASS" "$out"
expect_contains "tree state col"   "state files:" "$out"
expect_contains "tree state entry" "progress.md" "$out"
expect_contains "tree source col"  "source/other:" "$out"
expect_contains "tree source entry" "newfile.c" "$out"
expect_contains "toc changes"   "newfile.c" "$out"
if command -v node >/dev/null 2>&1; then
  expect_contains "archival relay" "nothing to archive" "$out"
  expect_contains "ledger ok"      "ledger: OK" "$out"
fi

# ---- init.sh FAIL + --skip-init ----
printf '#!/bin/sh\necho boom >&2\nexit 7\n' > "$ROOT/ok/init.sh"
out=$(bash "$PC" --target "$ROOT/ok")
expect_contains "init fail"     "init.sh: FAIL (exit 7)" "$out"
expect_contains "init fail tail" "boom" "$out"
out=$(bash "$PC" --target "$ROOT/ok" --skip-init)
expect_contains "init skipped"  "init.sh: SKIPPED (--skip-init)" "$out"

# ---- absent init.sh ----
mkproj "$ROOT/noinit"
out=$(bash "$PC" --target "$ROOT/noinit")
expect_contains "no init"       "(no init.sh)" "$out"
expect_contains "no toc anchor" "(no TOC anchor)" "$out"

# ---- duplicate id relay (needs node) ----
if command -v node >/dev/null 2>&1; then
  cat > "$ROOT/noinit/feature_list.json" <<'EOF'
{ "project": "p",
  "features": [ {"id":"dup","name":"A","description":"d","status":"pass"},
                {"id":"dup","name":"B","description":"d","status":"planned"} ] }
EOF
  out=$(bash "$PC" --target "$ROOT/noinit")
  expect_contains "dup relay"   "Duplicate feature id(s)" "$out"
fi

# ---- secrets scan + state hygiene (v0.15.0) ----
SEC="$ROOT/secproj"; mkproj "$SEC"
FAKE="ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"   # ghp_ + 36 chars -> github-token
printf '# handoff\ntoken %s\n' "$FAKE" > "$SEC/session-handoff.md"
out=$(bash "$PC" --target "$SEC" --skip-init)
expect_contains "secret flagged (file:line + label)" "SECRET? session-handoff.md:2 (github-token)" "$out"
case "$out" in
  *"$FAKE"*) echo "  FAIL secret value echoed in output"; FAIL=$((FAIL+1));;
  *)         echo "  OK   secret value never echoed"; PASS=$((PASS+1));;
esac
expect_contains "hygiene without golden-rules" "(no golden-rules.md)" "$out"

CLN="$ROOT/clnproj"; mkproj "$CLN"
out=$(bash "$PC" --target "$CLN" --skip-init)
expect_contains "secrets clean" "- (clean)" "$out"
printf '# GR\n\n### GR-1 — a\n- **Why / origin:** x\n- **Check:** manual review\n\n### GR-2 — b\n- **Why / origin:** y [user]\n- **Check:** manual review\n' > "$CLN/golden-rules.md"
out=$(bash "$PC" --target "$CLN" --skip-init)
expect_contains "golden-rules counted" "2 rule(s)" "$out"

echo ""; echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
