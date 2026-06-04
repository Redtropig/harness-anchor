#!/usr/bin/env bash
# bootstrap.sh — Create an isolated git repo from the e2e-cpp-fixture template.
#
# Copies the fixture into a temp directory, git-inits, makes an initial commit,
# regenerates PROJECT-TOC.md via index-builder.mjs, and commits it.
#
# Note on TOC freshness: the anchor in PROJECT-TOC.md will point to the
# commit BEFORE the TOC was committed, so `toc-freshness.sh` will report
# "stale (1 file changed)" — this is an inherent limitation of the
# commit-then-anchor approach (committing the TOC advances HEAD past the
# anchor it records). The CI structural checks verify file existence and
# JSON validity, not TOC freshness. For a genuinely fresh TOC, the user
# would run `/index-project` after committing, which updates the anchor.
#
# Usage: bash tests/e2e-cpp-fixture/bootstrap.sh
#   Prints the temp directory path to stdout.
#
# Cleanup: the caller is responsible for removing the temp dir.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Create a temp directory with a meaningful prefix
TARGET=$(mktemp -d "${TMPDIR:-/tmp}/harness-anchor-e2e.XXXXXX")

# Copy fixture files (exclude bootstrap.sh and .DS_Store).
# dotglob is REQUIRED: the default glob '*' skips names beginning with '.',
# which would silently drop dotfiles the fixture ships (.clang-format,
# .clang-tidy) and make the CI E2E structural check fail. nullglob guards
# against a literal '*' if the directory were ever empty.
shopt -s dotglob nullglob
for f in "$SCRIPT_DIR"/*; do
    case "$(basename "$f")" in
        bootstrap.sh|.DS_Store) continue ;;
    esac
    cp -R "$f" "$TARGET/"
done
shopt -u dotglob nullglob

# Initialize git repo
cd "$TARGET" || exit 1
git init -q
git config user.email test@example.com
git config user.name test

# Remove stale anchor lines from copied PROJECT-TOC.md
if [ -f PROJECT-TOC.md ]; then
    sed -i.bak '/generated-at-commit/d' PROJECT-TOC.md && rm -f PROJECT-TOC.md.bak
fi

# Make initial commit (without TOC — it gets regenerated below)
git add -A
git commit -qm "initial fixture state" 2>/dev/null

# Regenerate PROJECT-TOC.md so anchor commit points to the initial commit.
# The TOC itself is committed as a second commit, so the anchor will be
# 1 commit behind HEAD (inherent limitation — see header comment).
if command -v node >/dev/null 2>&1; then
    node "${PLUGIN_ROOT}/scripts/index-builder.mjs" --target "$TARGET" >/dev/null 2>/dev/null || true
    git add -A
    git commit -qm "add PROJECT-TOC.md" 2>/dev/null
fi

# Make init.sh executable
chmod +x init.sh 2>/dev/null || true

# Print the path for the caller
printf '%s\n' "$TARGET"
