---
description: Scaffold harness-anchor state files (AGENTS.md, feature_list.json, init.sh, progress.md, session-handoff.md, PROJECT-TOC.md) into the current project.
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion, Glob
---

# /anchor

Initialize harness-anchor state files in the current project. The mechanical
work (existence checks, placeholder substitution, writes, chmod) is done by
`scripts/scaffold.sh` — the **single source of truth**. Your job is the
decisions the script refuses to make.

## Steps

1. **If the directory is not a git repository**, ask first: continue anyway
   (TOC freshness will report `not-git`) or run `git init` (recommended)?
   The script itself only reports the fact; this decision is yours to ask.

2. **Run the scaffold:**

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.sh --target "$(pwd)"
   ```

   The report lists `written:` / `kept (skip-by-default):` /
   `conflicts (need decision):` and prints the next-steps block.

3. **Resolve conflicts — never silently overwrite.** For each file under
   `conflicts (need decision):`, AskUserQuestion with options
   `[Overwrite / Skip / Show diff]`.
   - **Show diff** → run
     `diff "$(pwd)/<file>" <(bash ${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.sh --target "$(pwd)" --render <file>)`
     and show it, then re-ask.
   - Collect the approved files and apply them in ONE call:
     `bash ${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.sh --target "$(pwd)" --overwrite <f1,f2>`
   - `kept (skip-by-default)` files (feature_list.json, golden-rules.md) hold
     accumulated value — only overwrite if the user explicitly asks; mention
     they were kept.

4. **Print the script's next-steps block verbatim** (it is the report tail).

5. **Do NOT auto-commit.** Let the user review the diff first.

6. **Hand off to `/cpp-init` if this is a C/C++ project missing its config.**

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/cpp-detect.sh --target "$(pwd)"
   ```

   If `is_cpp_project` is `true` and either `has_clang_format` or `has_clang_tidy`
   is `false`, make **the last line of your reply** a concrete recommendation:

   > Next: run `/cpp-init` — this is a `<build_system>` project with no
   > `.clang-format`/`.clang-tidy` yet, and `/cpp-init` drops those plus a
   > per-build-system `init.sh`, `scripts/lint.sh`, and the sanitizer build.

   Recommend it *here*, at the moment of maximum relevance, rather than relying on
   the agent to recall it from the SessionStart command list — a real run read that
   list, ran `/anchor`, and still never reached `/cpp-init`.

   Note the field names mean *config file present*, not *tool installed* — tool
   availability is `scripts/cpp-tool-discovery.sh`'s question, and `/cpp-init`
   asks it in its own step 1.

## Refusal / edge cases

- Existing state files over their hot-window budgets (the report's facts or
  the SessionStart sentinel say so) → point at `/session-end`, whose budget
  step offers deterministic archival. Do **not** archive during scaffolding.
- If the script itself fails, report its error verbatim. Do not hand-copy
  templates as a substitute — scaffolding writes state and must stay
  deterministic (only /status has a manual degraded path).

## Verification

After completion the user should be able to run `bash init.sh` (reports OK or
specific missing pieces), and a new session should show `<harness-anchor-state>`
in the SessionStart banner.
