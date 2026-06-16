---
description: Scaffold harness-anchor state files (AGENTS.md, feature_list.json, init.sh, progress.md, session-handoff.md, PROJECT-TOC.md) into the current project.
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion, Glob
---

# /anchor

Initialize harness-anchor state files in the current project. Implements the **Initializer Agent** pattern from Anthropic's Nov 2025 harness guidance.

## Steps

1. **Detect project type.** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/cpp-detect.sh` if it exists (Phase 4+). If it returns `is_cpp_project: true`, prefer C/C++ templates from `templates/cpp/` where applicable.

2. **List target files.** These templates exist (drop the `.tpl` suffix on write):

   | Template | Target in user project |
   |---|---|
   | `templates/AGENTS.md.tpl` | `AGENTS.md` |
   | `templates/golden-rules.md.tpl` | `golden-rules.md` |
   | `templates/feature_list.json.tpl` | `feature_list.json` |
   | `templates/feature_list.schema.json` | `feature_list.schema.json` (copied as-is) |
   | `templates/init.sh.tpl` | `init.sh` (chmod +x) |
   | `templates/progress.md.tpl` | `progress.md` |
   | `templates/session-handoff.md.tpl` | `session-handoff.md` |
   | `templates/PROJECT-TOC.md.tpl` | `PROJECT-TOC.md` |
   | `templates/context-budget.md.tpl` | `context-budget.md` |

3. **For each target file, check existence.**
   - **Not present (or empty)** → write the template content, substituting placeholders (project name, current ISO timestamp, current git SHA if available).
   - **Present and non-empty** → invoke `AskUserQuestion` with options `[Overwrite, Skip, Show diff]`. **Never silently overwrite.** This is a hard rule from `learn-harness-engineering` gotchas: destructive behaviour must be explicit.

4. **After all files are placed:** print a concise next-step list:

   ```
   ✓ harness-anchor scaffold complete.

   Next:
   1. Edit AGENTS.md "Project Context" and "Verification Commands" sections.
   2. Replace the example entry in feature_list.json with a real first feature.
   3. Run `bash init.sh` to verify it executes.
   4. (Optional) Run /index-project to generate PROJECT-TOC.md from your sources.
   5. (Optional, C/C++ only) Run /cpp-init to add clang-format/.clang-tidy.
   6. Leave golden-rules.md empty for now — add your first rule when a pattern recurs (see the capturing-golden-rules skill).
   ```

5. **Do NOT auto-commit.** Let the user review the diff first.

## Placeholder substitution

When writing templates:
- `PROJECT_NAME_PLACEHOLDER` → directory basename (e.g., `my-project`)
- `2026-05-28T00:00:00Z` → current ISO-8601 UTC timestamp
- `PLACEHOLDER_COMMIT_SHA` (in PROJECT-TOC.md.tpl) → `git rev-parse HEAD` if inside a repo, else `uninitialized`

## Refusal cases

If the current directory is **not a git repository**, surface this and ask whether to:
- Continue anyway (TOC freshness can't be verified — reports `not-git`)
- Run `git init` first (recommended)

If `feature_list.json` exists and is **already valid**: skip it by default, mention to the user.

If `golden-rules.md` exists and is **non-empty**: **skip by default** (like `feature_list.json`) — it accumulates the project's hard-won rules, so overwriting it with the empty template would wipe the feedback flywheel's value.

## Verification

After completion, the user should be able to:

```bash
bash init.sh    # Reports OK or specific missing pieces
```

And starting a new Claude Code session should show `<harness-anchor-state>` in the SessionStart banner (Phase 3+ shows feature id; Phase 1 still shows skeleton banner).
