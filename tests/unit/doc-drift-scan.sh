#!/usr/bin/env bash
# Unit test for scripts/doc-drift-scan.sh — the MiniSched-shaped case (a
# function whose BODY changed while its signature did not) must be caught, and
# the documented residual blind spot must stay documented (a doc sentence with
# no symbol name in it is NOT expected to be caught).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCAN="$PLUGIN_ROOT/scripts/doc-drift-scan.sh"

PASS=0; FAIL=0
expect_contains() { case "$3" in *"$2"*) echo "  OK   $1"; PASS=$((PASS+1));; *) echo "  FAIL $1 → missing '$2'"; printf '%s\n' "$3" | head -10; FAIL=$((FAIL+1));; esac; }
expect_not_contains() { case "$3" in *"$2"*) echo "  FAIL $1 → unexpected '$2'"; FAIL=$((FAIL+1));; *) echo "  OK   $1"; PASS=$((PASS+1));; esac; }

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
cd "$ROOT" || exit 1
git init -q . && git config user.email t@t && git config user.name t

# ---- baseline commit: a function + a README claiming something about it ----
mkdir -p src
cat > src/scheduler.cpp <<'EOF'
bool Scheduler::cancel(JobId id) {
    mark_cancelled(id);
    return true;
}
EOF
# A plain global variable — NOT call/definition-shaped (no identifier is
# immediately followed by `(`) — so it never enters SYMS. Fixture for
# assertion 5 (finding-3 blind spot: non-function symbols aren't reached).
cat > src/config.cpp <<'EOF'
int max_retries = 3;
EOF
cat > README.md <<'EOF'
# Notes

- Cancellation is safe to call at any time.
- The worker pool uses 4 threads by default.
- Throughput is generally excellent.
- max_retries defaults to 3.
EOF
git add -A && git commit -qm base

# ---- the change: cancel()'s BODY changes, its SIGNATURE does not; the same
#      commit also changes max_retries' VALUE (not its shape) ----
cat > src/scheduler.cpp <<'EOF'
bool Scheduler::cancel(JobId id) {
    if (is_terminal(id)) return false;
    mark_cancelled(id);
    return true;
}
EOF
cat > src/config.cpp <<'EOF'
int max_retries = 10;
EOF
git add -A && git commit -qm change

out=$(bash "$SCAN" --base HEAD~1 --target "$ROOT" 2>/dev/null); rc=$?

# ---- 1. exit code contract ----
if [ "$rc" -eq 0 ]; then echo "  OK   exit 0"; PASS=$((PASS+1)); else echo "  FAIL exit $rc"; FAIL=$((FAIL+1)); fi

# ---- 2. THE motivating case: body-only change must still attribute to 'cancel',
#         and the file:line, symbol, and claim text must co-occur on ONE
#         tab-separated record — not merely appear somewhere in $out
#         independently, which would let a regression that scattered them
#         across unrelated lines pass silently. ----
TAB="$(printf '\t')"
expect_contains "cancel + README.md:3 + claim co-occur on one tab-separated record" \
  "README.md:3${TAB}cancel${TAB}Cancellation is safe to call at any time." "$out"

# ---- 3. unrelated doc lines must NOT be reported (noise control) ----
expect_not_contains "does not flag unrelated 4-threads line" "4 threads" "$out"

# ---- 4. RESIDUAL BLIND SPOT, deliberately frozen as a test:
#         a claim with no symbol name in it is NOT caught. If this ever starts
#         passing, update agents/drift-analyst.md's blind-spot note too. ----
expect_not_contains "symbol-less claim is a KNOWN miss" "generally excellent" "$out"

# ---- 5. RESIDUAL BLIND SPOT #2, deliberately frozen as a test: symbol
#         extraction only recognizes call/definition-shaped tokens (identifier
#         immediately followed by `(`). max_retries is a plain variable whose
#         VALUE changed (3 -> 10) and the README names it by name, but it is
#         NOT caught, because it never produces a symbol to reverse-grep for
#         in the first place. If this ever starts passing, update the
#         blind-spot note in both scripts/doc-drift-scan.sh's header and
#         agents/drift-analyst.md too. ----
expect_not_contains "variable-only change claim is a KNOWN miss" "max_retries defaults to 3" "$out"

# ---- 6. invariant #10 parity with cpp-tool-discovery's test: this script is
#         NOT a hook, so tests/windows-compat.sh's hook-only python3 sweep
#         ([1/5], $HOOKS) never sees it — assert it here or nowhere. ----
if grep -qE '(^|[^a-zA-Z_-])python3([^a-zA-Z_-]|$)' "$SCAN"; then
  echo "  FAIL script invokes python3 directly"; FAIL=$((FAIL+1))
else echo "  OK   no direct python3"; PASS=$((PASS+1)); fi

echo ""
echo "doc-drift-scan: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
