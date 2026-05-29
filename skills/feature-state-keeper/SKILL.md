---
name: feature-state-keeper
description: Use when starting, advancing, finishing, or blocking a feature. Manages feature_list.json + progress.md + session-handoff.md. Default-FAIL enforced.
---

# Feature State Keeper

You maintain the **machine-readable scope record** of this project. Three files form the state trio:

| File | Role |
|---|---|
| `feature_list.json` | Scope boundary + done criteria + evidence |
| `progress.md` | Append-only session history |
| `session-handoff.md` | Single-page "what's the state right now" |

## When to use

- Starting a session: read all three, identify the active feature
- Finishing a unit of work: update them before stopping
- User asks "what are we working on?" / "what's the status?" → consult `feature_list.json` first
- User adds a request that doesn't match the active feature → use `scope-jump` flow below

## Reading order

```
session-handoff.md   →  what was just being done
feature_list.json    →  what's planned, in-progress, blocked
progress.md          →  recent history (only if needed for deep context)
```

Most sessions only need handoff + feature_list. Skip progress.md unless you genuinely need the longer view.

## Active-feature rule

**Exactly one feature has `status: "in-progress"` at a time** unless the project has an explicit multi-track plan documented in AGENTS.md.

If you discover work that doesn't match the active feature:

1. Add it to `feature_list.json` with `status: "planned"` and a description
2. Tell the user: *"This looks like new scope. I've recorded it as a planned feature. Should I finish <active feature> first, or pivot?"*
3. Wait for confirmation before changing status.

## Default-FAIL evidence contract

Before flipping `status` to `"pass"`:

| Criterion | Evidence requirement |
|---|---|
| Build passes | Build log path (e.g. `.build/last-build.log`) + exit code 0 |
| Type check passes | Command output captured |
| Tests pass | Test runner output showing N passed, 0 failed |
| Static analysis | Lint report file or empty-warnings confirmation |

Write evidence to `feature_list.json`:

```json
{
  "id": "...",
  "status": "pass",
  "evidence": {
    "timestamp": "2026-05-28T13:00:00Z",
    "commit": "abc123...",
    "artifacts": [
      ".build/last-build.log",
      "test-results/run-42.txt",
      "lint-report.txt"
    ],
    "notes": "Optional human-readable summary"
  },
  "completedAt": "2026-05-28T13:00:00Z"
}
```

**If any criterion lacks evidence**: do NOT mark pass. State explicitly:

> "I am uncertain whether <feature> is fully done because <criterion> lacks evidence. Recommend running `<command>` to verify."

This is the calibrated-uncertainty pattern. Bluffing breaks user trust.

## Updating progress.md

At every `/session-end` (or when you reach a meaningful stopping point):

1. Read current `progress.md`
2. **Prepend** a new section (most recent first) using the template format already there
3. Keep entries concise: 5-10 lines max per session
4. Never delete past entries (append-only)

## Updating session-handoff.md

This file is **overwritten** at end of session — it should reflect *current* state only.

Required fields:
- Last updated timestamp
- Active feature id
- What's in flight (2-5 bullets)
- Build/test/lint state (pass/fail/not-run + timestamp)
- The ONE concrete next action
- Risks / things to avoid

Aim for ≤ 300 words. The next session should be able to resume from this alone.

## Schema validation

`feature_list.json` validates against `feature_list.schema.json` (JSON Schema draft-07). When you edit feature_list.json:

- Required: `project`, `features` (array)
- Per feature: `id`, `name`, `description`, `status`, `done_criteria`
- `id` is kebab-case, never rename once set
- `status` ∈ `planned | in-progress | pass | blocked`
- `evidence` MUST be non-null when `status == "pass"` (Default-FAIL invariant)

If the schema file is present, an external validator (e.g. `ajv-cli`) can verify. The agent need not run it — write valid JSON the first time by following the shape above.

## Looking up JSON Schema constraints

For non-trivial schema constructs (`allOf`, `oneOf`, `if/then`, regex patterns) — invoke the `docs-lookup` skill. Don't guess schema syntax; `feature_list.schema.json` validation must stay correct, and a malformed schema silently disables enforcement.

Typical entry query: `json schema <construct>` (e.g. `json schema if then else`).

## Related

- For evidence-gathering procedure → `anti-hallucination-gates` skill
- For end-of-session ritual → `/session-end` command
- For project index → `project-indexing` skill
- For quick read-only overview → `/status` command

## Committing as features advance

Each feature status flip (planned → in-progress → pass / blocked) should be its own commit:

1. **Commit on status change.** When you update `feature_list.json` to flip a feature's status, commit immediately with a message like `feat(engine-init): start` or `feat(engine-init): mark pass`.
2. **Never bundle unrelated changes.** A status-flip commit should only contain `feature_list.json` + `progress.md` (if updated). Code changes go in their own commits. (Mirrors CLAUDE.md: "never bundle unrelated layers in one commit".)
3. **Branch/PR discipline is superpowers' domain.** Don't reinvent — defer to superpowers' `requesting-code-review` and `finishing-a-development-branch` skills for branching, PRs, and merge strategies.
4. **Unfamiliar git commands?** Use `docs-lookup` skill — don't guess flags or syntax.
