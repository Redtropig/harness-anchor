#!/usr/bin/env bash
# Unit test for scripts/index-builder.mjs — summary extraction + structural behavior.
#
# Black-box: builds a throwaway git repo whose files' FIRST lines exercise every
# comment-marker branch of extractSummary(), then asserts the generated
# PROJECT-TOC.md. Notably guards the js/bad-tag-filter fix (both `-->` AND `--!>`
# HTML comment-end forms) which the CI happy-path smoke (`// main.c`) never covers.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IB="$PLUGIN_ROOT/scripts/index-builder.mjs"

PASS=0; FAIL=0
ok()  { echo "  OK   $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

command -v node >/dev/null 2>&1 || { echo "SKIP: node not found"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
git init -q
git config user.email t@e.com
git config user.name t

# <file> first lines exercising each marker branch
printf '// C line summary\nint main(){}\n'                          > c_slashes.c
printf '# python line summary\nx=1\n'                               > hashed.py
printf '/* block summary */\nint x;\n'                              > block.c
printf ';; lisp summary\n(defun f ())\n'                           > lisp.el
printf '<!-- html dash summary -->\n# Title\n'                      > dash.md
printf '<!-- html bang summary --!>\n# Title\n'                     > bang.md   # js/bad-tag-filter fix
printf '#!/usr/bin/env bash\n# shebang-skipped summary\necho hi\n'  > shebang.sh
printf '// %s\n' "$(printf 'x%.0s' {1..120})"                       > longline.c

# Existing TOC with a human-edited Decisions section → must be preserved
printf '<!-- generated-at-commit: deadbeef -->\n# PROJECT TOC\n\n## Files\n\n## Decisions\n\n- KEEPME-DECISION-MARKER\n' > PROJECT-TOC.md

# binary (NUL byte) + lockfile → must be skipped (not indexed)
printf 'bin\0data' > blob.bin
printf '{}'        > package-lock.json

git add -A
git commit -qm init

node "$IB" --target "$TMP" >/dev/null 2>&1 || bad "index-builder exited non-zero"
toc="$TMP/PROJECT-TOC.md"

has() { if grep -qF -- "$1" "$toc"; then ok "summary present: $1"; else bad "missing summary: $1"; fi; }
has "C line summary"
has "python line summary"
has "block summary"
has "lisp summary"
has "html dash summary"
has "html bang summary"        # <-- regression guard: --!> comment-end form
has "shebang-skipped summary"

# truncation: 120-char line → 77 chars + "..."
if grep 'longline.c' "$toc" | grep -qE 'x{70,}[.]{3}'; then ok "long line truncated to 77+..."; else bad "truncation not applied"; fi

# Decisions section preserved verbatim
if grep -qF "KEEPME-DECISION-MARKER" "$toc"; then ok "Decisions section preserved"; else bad "Decisions section lost"; fi

# binary + lockfile excluded from the index
if grep -qF "blob.bin" "$toc"; then bad "binary file should be skipped"; else ok "binary skipped"; fi
if grep -qF "package-lock.json" "$toc"; then bad "lockfile should be skipped"; else ok "lockfile skipped"; fi

echo ""
echo " Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo " STATUS: PASSED"; exit 0; else echo " STATUS: FAILED"; exit 1; fi
