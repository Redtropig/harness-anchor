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
4. `golden-rules.md` — project-specific taste / anti-pattern rules to honor
5. `session-handoff.md` — what previous session left

If none exist, the project is **un-anchored**. Suggest the user run `/anchor` to scaffold.

## Sibling Skills (load when triggered)

- `project-indexing` — when you need to find files; consult PROJECT-TOC.md before Glob
- `feature-state-keeper` — when feature work starts/finishes; updates feature_list.json + progress.md
- `init-verification` — at start of work; run `init.sh` health check
- `self-correction-loop` — after edits that fail lint/build; iterate with evidence
- `anti-hallucination-gates` — before claiming "done"; Default-FAIL evidence contract
- `test-coverage-design` — what to test / is a feature really covered before "done"; dispatches `coverage-analyst`
- `capturing-golden-rules` — same mistake recurs / a review comment is really a convention; encode it as a durable rule in golden-rules.md (the feedback flywheel)
- `context-budget-discipline` — when context fills up; SELECT/WRITE/COMPRESS/ISOLATE
- `docs-lookup` — when looking up unfamiliar tools/APIs/errors; Context7 → WebSearch → calibrated uncertainty fallback chain
<!-- cpp-only-start -->
- `cpp-build-systems` — CMake/Meson/Make/Bazel project
- `cpp-static-analysis` — clang-tidy / cppcheck / IWYU
- `cpp-formatting` — clang-format
- `cpp-sanitizers` — ASan / UBSan / TSan / valgrind
<!-- cpp-only-end -->

## Hard Rules

These are non-negotiable invariants:

1. **No "done" without evidence.** A feature is "pass" only when compile + tests + lint produce concrete output paths. Lacking evidence → status stays `in-progress`. Express uncertainty: *"I am uncertain whether X passes because <reason>."*
2. **One active feature at a time** unless explicit multi-feature plan. If the user adds an unrelated request mid-feature, surface the scope-jump and confirm before pivoting. Scope is guarded on **two sides**: a prompt-side hook (scope-jump phrasing) and an action-side hook (a new code module created mid-feature) — both warn-only.
3. **State lives on disk, not in chat.** Update `feature_list.json` / `progress.md` / `session-handoff.md` rather than relying on conversation memory.
4. **PROJECT-TOC.md before Glob.** It is cheaper for both you and the user.
5. **Subagents are single-level.** Never invoke a subagent from within a subagent — so a dispatched worker (`superpowers:dispatching-parallel-agents` / `subagent-driven-development`) must not run the subagent-backed gates `/verify` · `/test-plan` · `/gc`; the parent runs them after the workers integrate.
6. **When stuck, follow `docs-lookup`.** Never guess at unfamiliar tools/APIs/errors. The Context7 → WebSearch → calibrated-uncertainty fallback chain is canonical there.

**Interop seams with superpowers** (contract in the named skill): parallel/subagent dispatch → `feature-state-keeper`; worktree setup → `init-verification`; sensor-finding triage → `self-correction-loop` (+ `receiving-code-review`).

## Commands — recommend them at the right moment

Commands are **user-invoked and never auto-trigger** (unlike skills, which you load by
description). Surfacing the right one at the right time is part of your job: suggest it,
say why in one line, and let the user run it.

- `/anchor` — project is un-anchored (no `feature_list.json`): scaffolds the state files.
<!-- cpp-only-start -->
- `/cpp-init` — a C/C++ project has no `.clang-format`/`.clang-tidy` (run right after `/anchor`): drops C/C++ config + sanitizer build, tunes `init.sh`.
<!-- cpp-only-end -->
- `/index-project` — `PROJECT-TOC.md` is absent or stale, or before a broad file search: (re)builds the one-line-per-file index.
- `/verify` — before you claim a feature passes or flip its status to `pass`: build + lint + tests in a fresh-context subagent. `--fix` runs a bounded (≤ 2-cycle) auto-fix loop.
- `/test-plan` — after implementing, before marking `pass`: fresh-context coverage-gap analysis (obligations, paths outside the run scope, minimal tests). Complements `/verify`.
- `/gc` — after a batch of generated code, before `/session-end`: fresh-context drift/entropy scan against `golden-rules.md` + slop heuristics (dead code, duplication, doc-drift). Read-only, report-only (not `git gc`).
<!-- cpp-only-start -->
- `/sanitize` — after a C/C++ source change, or before merging C/C++: ASan+UBSan run (TSan separately), findings in fixed sections with an evidence log.
<!-- cpp-only-end -->
- `/status` — whenever the user asks "where am I / what's the state": read-only snapshot, writes nothing.
- `/session-end` — at a stopping point or before ending: writes handoff, appends `progress.md`, offers over-budget state archival + a commit.

## When to NOT use this

- Inside a subagent dispatched for a narrow task (the subagent's own prompt governs)
- When the user has explicitly disabled harness-anchor (CLAUDE.md override)
