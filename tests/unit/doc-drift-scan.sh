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

# ---- 10. §B3: the rewrite must preserve prefix-matching semantics exactly.
#          The motivating case needs the symbol `cancel` to match the prose word
#          "Cancellation" — a leading \b only, never a trailing one. A rewrite
#          that "tidied" the regex into \bcancel\b would pass every other
#          assertion here and silently destroy the only case this script exists
#          for. Assertion 2 already covers it for the C++ fixture; this one
#          re-checks it AFTER the loop restructure, on the widened fixture. ----
expect_contains "[B3] prefix match survives the rewrite (cancel -> Cancellation)" \
  "${TAB}cancel${TAB}Cancellation is safe to call at any time." "$out4"

# ---- 11. §B3: chunking must be announced, not silent. A scan that quietly
#          covered only part of its symbol set, and then reported clean, is
#          strictly more dangerous than one that says it skipped. ----
ROOT7=$(mktemp -d); trap 'rm -rf "$ROOT" "$ROOT2" "$ROOT3" "$ROOT4" "$ROOT5" "$ROOT6" "$ROOT7"' EXIT
cd "$ROOT7" || exit 1
git init -q . && git config user.email t@t && git config user.name t
mkdir -p src
: > src/many.c
i=0; while [ "$i" -lt 450 ]; do printf 'void fn%03d(void) { }\n' "$i" >> src/many.c; i=$((i+1)); done
printf '# Doc\n\nfn001 does a thing.\n' > README.md
git add -A && git commit -qm base
i=0; while [ "$i" -lt 450 ]; do printf 'void fn%03d(void) { return; }\n' "$i" >> src/many.c; i=$((i+1)); done
git add -A && git commit -qm change
err8=$(bash "$SCAN" --base HEAD~1 --target "$ROOT7" 2>&1 >/dev/null)
expect_contains "[B3] chunking above 400 symbols is announced" "chunked into" "$err8"

# ---- 12. §B3 regression: a single doc line matching MULTIPLE symbols must
#          produce one candidate PER symbol, not just the first (leftmost)
#          match. Found empirically during Task 4's own performance
#          measurement (a real-repo scan silently dropped ~35% of candidates
#          once symbols were combined into one alternation): the old
#          per-symbol loop emitted one candidate per (symbol, line) pair,
#          independently per symbol, so an attribution step that stops at the
#          first match on a line silently drops every other symbol's
#          candidate for that same line — exactly the silent-miss failure this
#          script exists to prevent. ----
ROOT8=$(mktemp -d); trap 'rm -rf "$ROOT" "$ROOT2" "$ROOT3" "$ROOT4" "$ROOT5" "$ROOT6" "$ROOT7" "$ROOT8"' EXIT
cd "$ROOT8" || exit 1
git init -q . && git config user.email t@t && git config user.name t
mkdir -p src
cat > src/a.cpp <<'EOF'
bool cancel(JobId id) { return true; }
bool purge(JobId id) { return true; }
EOF
cat > README.md <<'EOF'
# Notes

- cancel and purge both run synchronously and return promptly.
EOF
git add -A && git commit -qm base
cat > src/a.cpp <<'EOF'
bool cancel(JobId id) { if (is_terminal(id)) return false; return true; }
bool purge(JobId id) { if (is_terminal(id)) return false; return true; }
EOF
git add -A && git commit -qm change
out9=$(bash "$SCAN" --base HEAD~1 --target "$ROOT8" 2>/dev/null)
expect_contains "[B3] multi-symbol line: cancel candidate is not dropped" "${TAB}cancel${TAB}" "$out9"
expect_contains "[B3] multi-symbol line: purge candidate is not dropped"  "${TAB}purge${TAB}"  "$out9"

# ---- 13. PORTABILITY: attribution must not depend on this box's awk.
#          v0.17.0 shipped an attribution stage that passed the symbol list via
#          `awk -v syms=...`. That value contains newlines, which POSIX does not
#          permit in a -v assignment — `gawk --posix` rejects it outright, and
#          macOS's one-true-awk silently attributed NOTHING. Every symbol
#          assertion above failed on macOS and Windows CI while this same file
#          reported 21/21 on a GNU-awk dev box: a green suite on one awk is not
#          evidence about any other.
#
#          Re-run the motivating case with awk forced into strict POSIX mode
#          where that is possible (gawk present), and with the system awk
#          otherwise — on a BSD-awk box the system awk IS the strict one, so the
#          check is meaningful either way and always runs. ----
POSIX_SHIM=$(mktemp -d)
if command -v gawk >/dev/null 2>&1; then
    printf '#!/bin/sh\nexec gawk --posix "$@"\n' > "$POSIX_SHIM/awk"
    chmod +x "$POSIX_SHIM/awk"
    shim_label="gawk --posix"
else
    shim_label="system awk (no gawk here)"
fi
out10=$(PATH="$POSIX_SHIM:$PATH" bash "$SCAN" --base HEAD~1 --target "$ROOT8" 2>/dev/null)
rm -rf "$POSIX_SHIM"
expect_contains "[portability/$shim_label] attribution survives a strict awk" \
  "${TAB}cancel${TAB}" "$out10"

# ---- 14. v0.17.1: the payload is BOUNDED, and every bound is announced.
#          Through v0.17.0 HARD_CAP bounded the symbol set and nothing bounded
#          the candidate ROWS — the units the consumer actually pays for. The
#          harness-anchor repo's own v0.16.0..v0.17.0 range emitted 4765 rows /
#          759 KB, which no tool hands to a subagent intact: drift-analyst was
#          adjudicating a list the harness had already truncated, silently, with
#          no note either end could see.
#
#          Three separate facts must reach stderr, because each one means a
#          different thing was NOT looked at:
#            a) tokens under SYM_MINLEN were never searched (named individually);
#            b) a symbol's rows were cut to the per-symbol cap (PARTIAL);
#            c) the whole list was cut to the total cap (PARTIAL).
#          Assertion (a) also pins stdout: a dropped token must not appear there,
#          or the "we didn't look" note contradicts the payload.
ROOT9=$(mktemp -d)
trap 'rm -rf "$ROOT" "$ROOT2" "$ROOT3" "$ROOT4" "$ROOT5" "$ROOT6" "$ROOT7" "$ROOT8" "$ROOT9"' EXIT
cd "$ROOT9" || exit 1
git init -q . && git config user.email t@t && git config user.name t
mkdir -p src
# 40 call-shaped symbols + one 2-character token (`at`), all on added lines.
{
    i=0; while [ "$i" -lt 40 ]; do printf 'void sym%02d(void) { }\n' "$i"; i=$((i+1)); done
    printf 'int at(void) { return 0; }\n'
} > src/many.c
# 15 doc lines, each naming every symbol: 40 symbols x 15 lines = 600 candidate
# rows before capping, 15 per symbol (> the 12 per-symbol cap), 40 x 12 = 480
# after it (> the 400 total cap). One fixture trips both bounds.
{
    printf '# Doc\n\n'
    j=0
    while [ "$j" -lt 15 ]; do
        printf -- '- line %02d:' "$j"
        i=0; while [ "$i" -lt 40 ]; do printf ' sym%02d' "$i"; i=$((i+1)); done
        printf ' at are all fine.\n'
        j=$((j+1))
    done
} > README.md
git add -A && git commit -qm base
{
    i=0; while [ "$i" -lt 40 ]; do printf 'void sym%02d(void) { return; }\n' "$i"; i=$((i+1)); done
    printf 'int at(void) { return 1; }\n'
} > src/many.c
git add -A && git commit -qm change

out11=$(bash "$SCAN" --base HEAD~1 --target "$ROOT9" 2>/dev/null)
err11=$(bash "$SCAN" --base HEAD~1 --target "$ROOT9" 2>&1 >/dev/null)

expect_contains     "[bound] sub-minimum token is named, not silently dropped" "not searched — at" "$err11"
expect_not_contains "[bound] a token we did not search never reaches stdout"   "${TAB}at${TAB}"    "$out11"
expect_contains     "[bound] per-symbol cap is announced"                      "per-symbol cap 12 hit by" "$err11"
expect_contains     "[bound] per-symbol cap says PARTIAL"                      "PARTIAL"           "$err11"
expect_contains     "[bound] total cap is announced"                           "truncated to 400 of 480" "$err11"
expect_contains     "[bound] summary separates matched from shown"             ", 400 shown"       "$err11"
expect_not_contains "[bound] cap diagnostics stay off stdout"                  "doc-drift-scan:"   "$out11"
n_rows=$(printf '%s\n' "$out11" | grep -c . || true)
if [ "$n_rows" -eq 400 ]; then echo "  OK   [bound] stdout is exactly the announced 400 rows"; PASS=$((PASS+1))
else echo "  FAIL [bound] stdout has $n_rows rows, announced 400"; FAIL=$((FAIL+1)); fi
# The cap must keep a REPRESENTATIVE slice, not amputate whole symbols: every
# symbol that had hits must still be visible. A cap that silently erased symbols
# would reintroduce the exact miss this script exists to prevent.
n_syms=$(printf '%s\n' "$out11" | cut -f2 | sort -u | grep -c . || true)
if [ "$n_syms" -ge 33 ]; then echo "  OK   [bound] $n_syms/40 symbols survive the cap (none amputated wholesale)"; PASS=$((PASS+1))
else echo "  FAIL [bound] only $n_syms/40 symbols survive the cap"; FAIL=$((FAIL+1)); fi

# 14b. the all-dropped case gets its OWN sentence — "nothing was extracted" and
#      "everything extracted was filtered out" are different facts.
ROOT10=$(mktemp -d)
trap 'rm -rf "$ROOT" "$ROOT2" "$ROOT3" "$ROOT4" "$ROOT5" "$ROOT6" "$ROOT7" "$ROOT8" "$ROOT9" "$ROOT10"' EXIT
cd "$ROOT10" || exit 1
git init -q . && git config user.email t@t && git config user.name t
mkdir -p src
printf 'int at(void) { return 0; }\n' > src/tiny.c
printf '# Doc\n\nat is fast.\n' > README.md
git add -A && git commit -qm base
printf 'int at(void) { return 1; }\n' > src/tiny.c
git add -A && git commit -qm change
err12=$(bash "$SCAN" --base HEAD~1 --target "$ROOT10" 2>&1 >/dev/null)
expect_contains "[bound] all-symbols-dropped is its own skip reason" \
  "every extracted symbol was under 3 chars" "$err12"

echo ""
echo "doc-drift-scan: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
