---
description: On-demand code-drift / entropy scan (garbage collection) via a fresh-context drift-analyst subagent. Checks changed/active code against golden-rules.md + generic drift heuristics (dead code, duplication, doc-drift) and reports findings with an evidence path. Read-only — recommends, never auto-refactors. Not `git gc`.
allowed-tools: Task, Read, Bash
---

# /gc

Scan recent work for **drift / entropy / AI slop** — code that compiles and passes tests but has rotted
away from the project's conventions: duplicated helpers, dead code, inconsistent error handling, stale
docs, golden-rule violations. This is the **garbage-collection** sensor (Concept ⑥) — *not* `git gc`.

Like `/verify` and `/test-plan`, it uses a **fresh-context** subagent so the scan isn't biased by the
agent that wrote the code. It is **report-only** — it never refactors in bulk.

## Steps

1. **Dispatch `drift-analyst`** via the `Task` tool:

   ```
   Task tool with:
     subagent_type: drift-analyst
     prompt: Scan the changed/active code for drift against golden-rules.md plus the generic drift
             heuristics. Bound the scope to changed files (git diff vs HEAD) or the active feature.
             Follow the fixed report format. Read-only — recommend, do not refactor.
   ```
   If the user passed a path or feature id as an argument, name it in the prompt.

2. **Surface the report verbatim** — `### Golden-rule violations`, `### Generic drift findings`,
   `### Recommended actions`, `### Verdict`, `### Uncertainties`. The point of fresh-context analysis is
   that the user sees the analyst's actual words.

3. **If verdict is DRIFT FOUND**, offer (do not auto-apply):
   - **Fix specific findings within the current feature's scope** — transparently (show each change),
     highest-severity first. Do NOT bulk-refactor or wander outside the active feature (that's a
     scope-jump — confirm first).
   - **Capture a recurring finding as a golden rule** via the `capturing-golden-rules` skill, so `/gc`
     catches it automatically next time.
   - **Leave as-is** and note it in `session-handoff.md` (e.g. deliberate debt to pay later).

4. **If verdict is CLEAN**, report it with the `.harness-anchor/drift-<ts>.md` evidence path. Note that
   a clean scan is a floor, not a guarantee (the heuristics are partial).

## When to invoke

- After a batch of generated code, before `/session-end` (the disciplined-refactoring rhythm).
- Before merging, to catch slop the test suite can't see.
- When `golden-rules.md` has grown and you want to confirm recent changes honor it.

## When NOT to invoke

- Before any code is written (nothing to scan).
- Inside a subagent (subagents are single-level).
- As a substitute for `/verify` (build/test/lint) or `/test-plan` (coverage) — different sensors.

## Related

- `drift-analyst` agent — what this command dispatches.
- `capturing-golden-rules` skill — turn a finding into a durable rule.
- `/verify`, `/test-plan` — the other two read-only sensors; pair them.
- `/session-end` — run `/gc` before wrapping up.
