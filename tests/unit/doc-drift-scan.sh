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

# ---- 7. REGRESSION (C1): default (no --base) resolution must include the
#         working tree, both AWAY FROM and directly ON the default branch.
#         Every assertion above always passes --base HEAD~1 explicitly and so
#         never exercises the resolution path at all — that is exactly the
#         blind spot that let two independent bugs ship silently: (a)
#         merge-base(HEAD, main) resolves to HEAD itself when we ARE main, and
#         the HEAD~1 fallback was guarded on BASE being *empty*, not
#         *useless*; (b) the diff used "$BASE"..HEAD (commit-to-commit),
#         invisible to uncommitted changes — but /gc runs precisely on
#         uncommitted work (commands/gc.md: "after a batch of generated code,
#         before /session-end").

# ---- 7a. feature branch, one real commit ahead of main, PLUS an uncommitted
#          change on top — isolates bug (b): BASE != HEAD here (merge-base is
#          the branch point, not HEAD), so only the one-ref (not ..HEAD) diff
#          form catches the still-uncommitted drift. ----
ROOT2=$(mktemp -d); trap 'rm -rf "$ROOT" "$ROOT2"' EXIT
cd "$ROOT2" || exit 1
git init -q . && git config user.email t@t && git config user.name t
git symbolic-ref HEAD refs/heads/main >/dev/null 2>&1 || true
mkdir -p src
cat > src/scheduler.cpp <<'EOF'
bool Scheduler::cancel(JobId id) {
    mark_cancelled(id);
    return true;
}
EOF
cat > README.md <<'EOF'
# Notes

- Cancellation is safe to call at any time.
EOF
git add -A && git commit -qm base
git checkout -q -b feature/uncommitted
echo "// unrelated" >> src/scheduler.cpp
git add -A && git commit -qm "unrelated feature-branch commit"
cat > src/scheduler.cpp <<'EOF'
bool Scheduler::cancel(JobId id) {
    if (is_terminal(id)) return false;
    mark_cancelled(id);
    return true;
}
// unrelated
EOF
# (deliberately left UNCOMMITTED — this is the drift under test)

out2=$(bash "$SCAN" --target "$ROOT2" 2>/dev/null); rc2=$?
if [ "$rc2" -eq 0 ]; then echo "  OK   [default-base/feature-branch] exit 0"; PASS=$((PASS+1))
else echo "  FAIL [default-base/feature-branch] exit $rc2"; FAIL=$((FAIL+1)); fi
expect_contains "[default-base/feature-branch] uncommitted body-only change found with NO --base" \
  "${TAB}cancel${TAB}" "$out2"

# ---- 7b. directly ON main (no feature branch at all), an uncommitted change
#          — isolates bug (a): merge-base(HEAD, main) == HEAD here, so the
#          HEAD~1 fallback must actually fire (and then combine with fix (b)
#          to still see the working tree on top of it). ----
ROOT3=$(mktemp -d); trap 'rm -rf "$ROOT" "$ROOT2" "$ROOT3"' EXIT
cd "$ROOT3" || exit 1
git init -q . && git config user.email t@t && git config user.name t
git symbolic-ref HEAD refs/heads/main >/dev/null 2>&1 || true
echo "init" > NOTES.md
git add -A && git commit -qm init
mkdir -p src
cat > src/scheduler.cpp <<'EOF'
bool Scheduler::cancel(JobId id) {
    mark_cancelled(id);
    return true;
}
EOF
cat > README.md <<'EOF'
# Notes

- Cancellation is safe to call at any time.
EOF
git add -A && git commit -qm base
# still ON main (HEAD == main, no branch divergence); now an uncommitted
# body-only edit — the drift under test:
cat > src/scheduler.cpp <<'EOF'
bool Scheduler::cancel(JobId id) {
    if (is_terminal(id)) return false;
    mark_cancelled(id);
    return true;
}
EOF

branch3=$(git rev-parse --abbrev-ref HEAD)
out3=$(bash "$SCAN" --target "$ROOT3" 2>/dev/null); rc3=$?
if [ "$rc3" -eq 0 ]; then echo "  OK   [default-base/on-main, branch=$branch3] exit 0"; PASS=$((PASS+1))
else echo "  FAIL [default-base/on-main] exit $rc3"; FAIL=$((FAIL+1)); fi
if [ "$branch3" != "main" ]; then
  echo "  FAIL [default-base/on-main] fixture branch is '$branch3', not 'main' — test invalid"; FAIL=$((FAIL+1))
fi
expect_contains "[default-base/on-main] uncommitted body-only change found with NO --base" \
  "${TAB}cancel${TAB}" "$out3"

# ---- 8. §B1: pathspec is no longer C/C++-only. Python / Go / Rust definitions
#         are exactly as call-shaped as the C++ case this script was built
#         around; before v0.17.0 they were invisible for a reason that had
#         nothing to do with symbol shape. ----
ROOT4=$(mktemp -d); trap 'rm -rf "$ROOT" "$ROOT2" "$ROOT3" "$ROOT4"' EXIT
cd "$ROOT4" || exit 1
git init -q . && git config user.email t@t && git config user.name t
mkdir -p src
printf 'def cancel(job_id):\n    return True\n' > src/sched.py
printf 'func Retry(n int) bool {\n    return true\n}\n' > src/retry.go
printf 'fn purge(id: u32) -> bool {\n    true\n}\n' > src/purge.rs
cat > README.md <<'EOF'
# Notes

- Cancellation is safe to call at any time.
- Retry gives up after 3 attempts.
- Purge removes the entry immediately.
EOF
git add -A && git commit -qm base
printf 'def cancel(job_id):\n    if terminal(job_id):\n        return False\n    return True\n' > src/sched.py
printf 'func Retry(n int) bool {\n    if n > 10 { return false }\n    return true\n}\n' > src/retry.go
printf 'fn purge(id: u32) -> bool {\n    if pinned(id) { return false }\n    true\n}\n' > src/purge.rs
git add -A && git commit -qm change
out4=$(bash "$SCAN" --base HEAD~1 --target "$ROOT4" 2>/dev/null)
expect_contains "[B1] Python def is reached"  "${TAB}cancel${TAB}" "$out4"
expect_contains "[B1] Go func is reached"     "${TAB}Retry${TAB}"  "$out4"
expect_contains "[B1] Rust fn is reached"     "${TAB}purge${TAB}"  "$out4"

# ---- 9. §B2: "did not scan" and "scanned, found nothing" must be
#         distinguishable at runtime. Before v0.17.0 both were exit 0 with
#         empty stdout — which is precisely why this script's own total
#         blindness on the harness-anchor repo went unnoticed through a whole
#         release. stdout stays contract-pure; diagnostics go to stderr. ----

# 9a. changed files, none in a scanned language
ROOT5=$(mktemp -d); trap 'rm -rf "$ROOT" "$ROOT2" "$ROOT3" "$ROOT4" "$ROOT5"' EXIT
cd "$ROOT5" || exit 1
git init -q . && git config user.email t@t && git config user.name t
printf 'a\n' > notes.txt && printf '# Doc\n\ncancel is safe.\n' > README.md
git add -A && git commit -qm base
printf 'b\n' > notes.txt
git add -A && git commit -qm change
err5=$(bash "$SCAN" --base HEAD~1 --target "$ROOT5" 2>&1 >/dev/null)
expect_contains "[B2] no-scanned-language skip is announced" \
  "none in scanned languages" "$err5"

# 9b. not a git repository
ROOT6=$(mktemp -d); trap 'rm -rf "$ROOT" "$ROOT2" "$ROOT3" "$ROOT4" "$ROOT5" "$ROOT6"' EXIT
err6=$(bash "$SCAN" --target "$ROOT6" 2>&1 >/dev/null)
expect_contains "[B2] non-git skip is announced" "not a git repository" "$err6"

# 9c. a real scan announces its own size — "clean" must state what it covered
err7=$(bash "$SCAN" --base HEAD~1 --target "$ROOT4" 2>&1 >/dev/null)
expect_contains "[B2] completed scan reports coverage" "scanned " "$err7"

# 9d. stdout purity is preserved: diagnostics must NOT leak into stdout, or
#     every caller parsing candidate lines breaks.
expect_not_contains "[B2] diagnostics stay off stdout" "doc-drift-scan:" "$out4"

echo ""
echo "doc-drift-scan: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
