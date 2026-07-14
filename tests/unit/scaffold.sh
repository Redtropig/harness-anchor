#!/usr/bin/env bash
# Unit test for scripts/scaffold.sh — fresh write + substitution, rerun
# conflict inertness (byte-identical), --overwrite allowlist, --render,
# --cpp drops (incl. dotfiles), refusal exit codes, not-git fact.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SC="$PLUGIN_ROOT/scripts/scaffold.sh"

PASS=0; FAIL=0
expect_contains() {
  case "$3" in
    *"$2"*) echo "  OK   $1"; PASS=$((PASS+1));;
    *)      echo "  FAIL $1 → missing '$2'"; echo "---"; printf '%s\n' "$3" | head -25; echo "---"; FAIL=$((FAIL+1));;
  esac
}
expect_true() { if eval "$2"; then echo "  OK   $1"; PASS=$((PASS+1)); else echo "  FAIL $1"; FAIL=$((FAIL+1)); fi; }
expect_eq() { # <label> <a> <b>
  if [ "$2" = "$3" ]; then echo "  OK   $1"; PASS=$((PASS+1)); else echo "  FAIL $1 → values differ"; FAIL=$((FAIL+1)); fi
}

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
mkgit() { mkdir -p "$1"; ( cd "$1" || exit 1; git init -q; git config user.email t@e.com; git config user.name t; echo seed > seed.txt; git add -A; git commit -qm init; ); }

# ---- 1. fresh generic scaffold ----
mkgit "$ROOT/fresh-proj"
out=$(bash "$SC" --target "$ROOT/fresh-proj")
expect_contains "report header"   "## Scaffold report" "$out"
expect_contains "git yes"         "git repo: yes" "$out"
expect_contains "written lists AGENTS" "AGENTS.md" "$out"
for f in AGENTS.md golden-rules.md feature_list.json feature_list.schema.json init.sh progress.md session-handoff.md PROJECT-TOC.md context-budget.md; do
  expect_true "wrote $f" "[ -s '$ROOT/fresh-proj/$f' ]"
done
expect_true "init.sh executable"  "[ -x '$ROOT/fresh-proj/init.sh' ]"
expect_true "no name placeholder" "! grep -rq 'PROJECT_NAME_PLACEHOLDER' '$ROOT/fresh-proj/feature_list.json' '$ROOT/fresh-proj/golden-rules.md'"
expect_contains "name substituted" '"project": "fresh-proj"' "$(cat "$ROOT/fresh-proj/feature_list.json")"
expect_true "createdAt substituted" "! grep -q '2026-05-28T00:00:00Z' '$ROOT/fresh-proj/feature_list.json'"
head_sha=$(cd "$ROOT/fresh-proj" && git rev-parse HEAD)
expect_contains "toc anchor = HEAD" "generated-at-commit: $head_sha" "$(head -1 "$ROOT/fresh-proj/PROJECT-TOC.md")"

# ---- 2. rerun → conflicts, byte-inert ----
sum_before=$(cd "$ROOT/fresh-proj" && cksum AGENTS.md init.sh progress.md)
out=$(bash "$SC" --target "$ROOT/fresh-proj")
sum_after=$(cd "$ROOT/fresh-proj" && cksum AGENTS.md init.sh progress.md)
expect_contains "kept-by-default"  "kept (skip-by-default): golden-rules.md, feature_list.json" "$out"
expect_contains "conflicts listed" "conflicts (need decision):" "$out"
expect_contains "AGENTS in conflicts" "AGENTS.md" "$out"
expect_eq "rerun byte-inert"       "$sum_before" "$sum_after"
expect_contains "written none"     "written: (none)" "$out"

# ---- 3. --overwrite allowlist only ----
echo custom > "$ROOT/fresh-proj/AGENTS.md"
sum_init=$(cksum < "$ROOT/fresh-proj/init.sh")
out=$(bash "$SC" --target "$ROOT/fresh-proj" --overwrite AGENTS.md)
expect_contains "overwrite written" "written: AGENTS.md" "$out"
expect_true "AGENTS re-templated"  "grep -q 'Operating Manual' '$ROOT/fresh-proj/AGENTS.md'"
expect_eq "init untouched"         "$sum_init" "$(cksum < "$ROOT/fresh-proj/init.sh")"

# ---- 4. --render matches on-disk fresh content ----
r=$(bash "$SC" --target "$ROOT/fresh-proj" --render golden-rules.md)
expect_eq "render = disk"          "$r" "$(cat "$ROOT/fresh-proj/golden-rules.md")"

# ---- 5. not-git target ----
mkdir -p "$ROOT/nogit"
out=$(bash "$SC" --target "$ROOT/nogit")
expect_contains "not-git fact"     "git repo: not-git" "$out"
expect_contains "sha placeholder"  "generated-at-commit: uninitialized" "$(head -1 "$ROOT/nogit/PROJECT-TOC.md")"

# ---- 6. --cpp: refusals then drops ----
mkgit "$ROOT/cppless"
( cd "$ROOT/cppless" && printf '{ "project": "x", "features": [] }\n' > feature_list.json )
bash "$SC" --target "$ROOT/cppless" --cpp >/dev/null 2>&1; rc=$?
expect_true "--cpp non-cpp exit 3" "[ $rc -eq 3 ]"

mkgit "$ROOT/cpp-proj"
( cd "$ROOT/cpp-proj" && printf 'cmake_minimum_required(VERSION 3.20)\nproject(x)\n' > CMakeLists.txt && printf 'int main(){}\n' > main.cpp && git add -A && git commit -qm cpp )
bash "$SC" --target "$ROOT/cpp-proj" --cpp >/dev/null 2>&1; rc=$?
expect_true "--cpp unanchored exit 4" "[ $rc -eq 4 ]"

printf '{ "project": "x", "features": [] }\n' > "$ROOT/cpp-proj/feature_list.json"
out=$(bash "$SC" --target "$ROOT/cpp-proj" --cpp)
expect_contains "cpp mode header"  "(cpp)" "$out"
for f in .clang-format .clang-tidy init.sh scripts/lint.sh scripts/sanitizer-build.sh; do
  expect_true "cpp wrote $f" "[ -s '$ROOT/cpp-proj/$f' ]"
done
expect_true "lint.sh executable"   "[ -x '$ROOT/cpp-proj/scripts/lint.sh' ]"
# rerun cpp → init.sh now a conflict, dotfiles conflicts too, nothing rewritten
sum_cf=$(cksum < "$ROOT/cpp-proj/.clang-format")
out=$(bash "$SC" --target "$ROOT/cpp-proj" --cpp)
expect_contains "cpp rerun conflicts" "conflicts (need decision):" "$out"
expect_eq "cpp rerun inert"        "$sum_cf" "$(cksum < "$ROOT/cpp-proj/.clang-format")"

echo ""; echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
