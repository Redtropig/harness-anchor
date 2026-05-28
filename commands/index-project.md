---
description: (Re)build PROJECT-TOC.md — one-line index of every git-tracked source file, with git-commit freshness anchor.
allowed-tools: Bash, Read, Write
---

# /index-project

Rebuild the project's PROJECT-TOC.md index by scanning git-tracked files and extracting a one-line summary per file.

## Steps

1. **Verify git repo.** If not in a git working tree, error out: *"PROJECT-TOC.md requires a git repository. Run `git init` first."*

2. **Run index-builder.**

   ```bash
   node ${CLAUDE_PLUGIN_ROOT}/scripts/index-builder.mjs --target "$(pwd)"
   ```

   The script:
   - Reads `git ls-files` for tracked text files
   - Skips binaries (magic-byte heuristic) and files >100KB
   - Skips `PROJECT-TOC.md` itself, `.harness-anchor/`, common build dirs
   - Extracts a one-line summary per file (first non-empty comment/docstring/first line of content, truncated to 80 chars)
   - Preserves the existing `## Decisions` section (human-edited)
   - Writes header `<!-- generated-at-commit: <current HEAD SHA> -->`

3. **Report diff.** Run `git diff PROJECT-TOC.md` and summarize: N files added / M removed / K summaries updated.

4. **Suggest commit.** Tell the user: *"Run `git add PROJECT-TOC.md && git commit -m 'chore: refresh project index'` when ready."* Do not auto-commit.

## When PROJECT-TOC.md doesn't exist yet

If the file is missing, the script bootstraps it from `templates/PROJECT-TOC.md.tpl`. The user can run `/anchor` first for a cleaner scaffold; `/index-project` will work either way.

## Performance

For a 10k-file repo, expect ~2-3 seconds. If it exceeds 10 seconds, the script will warn — likely indicating bloat (auto-generated files committed) that should be `.gitignore`d.

## When NOT to run

- Mid-feature, when you've only changed 1-2 files (the SessionStart hook will surface the stale-TOC warning; you can ignore it for short sessions and regenerate at `/session-end`).
- In CI (use a dedicated CI workflow if needed).
