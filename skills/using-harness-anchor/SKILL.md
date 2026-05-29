---
name: using-harness-anchor
description: Use whenever working in a project. Establishes state/scope/verification discipline. Auto-loaded at session start. Complements superpowers.
---

# Using harness-anchor

You have the **harness-anchor** runtime layer. It is a companion to `superpowers` (process methodology) — harness-anchor handles **state persistence, scope boundaries, verification gates, and C/C++ engineering** at the environment level.

## Priority Order

1. **User's explicit instructions** (CLAUDE.md, direct requests) — highest
2. **superpowers skills** (brainstorming → plan → TDD → review)
3. **harness-anchor skills** (state/scope/verification/cpp)
4. Default system prompt — lowest

If superpowers and harness-anchor seem to conflict, prefer superpowers' process and use harness-anchor to **anchor** state/evidence around it.

## Project Navigation (read these BEFORE acting)

If they exist in the project root, read in this order:

1. `AGENTS.md` or `CLAUDE.md` — operating manual
2. `feature_list.json` — active feature + scope + done criteria
3. `PROJECT-TOC.md` — file-level index, one line per file
4. `session-handoff.md` — what previous session left

If none exist, the project is **un-anchored**. Suggest the user run `/anchor` to scaffold.

## Sibling Skills (load when triggered)

- `project-indexing` — when you need to find files; consult PROJECT-TOC.md before Glob
- `feature-state-keeper` — when feature work starts/finishes; updates feature_list.json + progress.md
- `init-verification` — at start of work; run `init.sh` health check
- `self-correction-loop` — after edits that fail lint/build; iterate with evidence
- `anti-hallucination-gates` — before claiming "done"; Default-FAIL evidence contract
- `context-budget-discipline` — when context fills up; SELECT/WRITE/COMPRESS/ISOLATE
- `docs-lookup` — when looking up unfamiliar tools/APIs/errors; Context7 → WebSearch → calibrated uncertainty fallback chain
- `cpp-build-systems` — CMake/Meson/Make/Bazel project
- `cpp-static-analysis` — clang-tidy / cppcheck / IWYU
- `cpp-formatting` — clang-format
- `cpp-sanitizers` — ASan / UBSan / TSan / valgrind

## Hard Rules

These are non-negotiable invariants:

1. **No "done" without evidence.** A feature is "pass" only when compile + tests + lint produce concrete output paths. Lacking evidence → status stays `in-progress`. Express uncertainty: *"I am uncertain whether X passes because <reason>."*
2. **One active feature at a time** unless explicit multi-feature plan. If the user adds an unrelated request mid-feature, surface the scope-jump and confirm before pivoting.
3. **State lives on disk, not in chat.** Update `feature_list.json` / `progress.md` / `session-handoff.md` rather than relying on conversation memory.
4. **PROJECT-TOC.md before Glob.** It is cheaper for both you and the user.
5. **Subagents are single-level.** Never invoke a subagent from within a subagent.
6. **When stuck, follow `docs-lookup`.** Never guess at unfamiliar tools/APIs/errors. The Context7 → WebSearch → calibrated-uncertainty fallback chain is canonical there.

## Commands

- `/anchor` — scaffold AGENTS.md / feature_list.json / init.sh into current project
- `/index-project` — (re)build PROJECT-TOC.md
- `/verify` — run full verification suite (build / lint / tests)
- `/session-end` — write structured handoff for next session
- `/status` — read-only project overview (active feature, counts, git tree, TOC freshness, handoff head)
- `/cpp-init` — initialize C/C++ project-specific config (clang-format/.clang-tidy)

## When to NOT use this

- Inside a subagent dispatched for a narrow task (the subagent's own prompt governs)
- When the user has explicitly disabled harness-anchor (CLAUDE.md override)
