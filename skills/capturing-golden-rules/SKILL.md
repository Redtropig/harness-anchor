---
name: capturing-golden-rules
description: Use when the same mistake or bad pattern recurs, when a code-review comment is really a convention worth enforcing, or when you catch AI-generated drift/slop and want it to never happen again. Encodes the lesson as a durable rule in golden-rules.md — the feedback-flywheel / harness-layer-learning ratchet — instead of a one-off fix. Generic (language-agnostic).
---

# Capturing Golden Rules

A one-off fix repairs today's symptom. A **golden rule** repairs the whole class — it makes the
harness learn so the same mistake can't recur. This skill is the **ratchet**: turn a recurring
failure into a durable, checkable rule in `golden-rules.md`.

> Hashimoto's principle: *"Anytime an agent makes a mistake, engineer a solution so it never makes
> that mistake again."* The fix is a guardrail, not a scolding — **blame the process, not the agent**.
> You're improving the environment, not the model.

## When to capture

Capture when the signal is **recurring**, not a one-off:

- The **same** mistake or bad pattern appears a **second** time.
- A code-review comment is really a *convention* ("we always do X here"), not a one-time nit.
- `/gc` (the `drift-analyst`) flags drift that should have been a rule.

One-off edge cases and personal style stay personal — capture what *recurs*, or what *any* contributor
would hit. (The archive's lesson: **3 rules, not 30**.)

## Route the signal to its right home (don't dump everything here)

`golden-rules.md` is specifically the home for **failure → guardrail / anti-pattern** signals. Other
learning belongs elsewhere — routing keeps each artifact focused:

| Signal | Example | Goes to |
|---|---|---|
| **Failure** | "it keeps reintroducing this bug class" | `golden-rules.md` (this skill) |
| **Context** | a fact / version / convention the AI keeps missing | `AGENTS.md` (Conventions / Project Context) |
| **Instruction** | a prompt phrasing that reliably works | a skill, or `AGENTS.md` |
| **Workflow** | a task sequence that reliably produces good work | `AGENTS.md` / `session-handoff.md` |

If it isn't a failure-class signal, route it and stop.

## How to capture

Append a rule to `golden-rules.md`:

```
### GR-<n> — <one-line rule>
- **Why / origin:** <the concrete failure that motivated it>
- **Check:** <manual review | grep one-liner | lint rule>
```

- **Tie it to a real failure.** The `origin` line is what makes the rule stick — and lets a future
  reader judge whether it still applies.
- **Make it checkable.** Start with "manual review"; graduate the Check to a grep one-liner or a lint
  rule **only** when the rule is violated often enough to be worth it (invest by frequency × impact —
  not every rule needs a tool).
- **Keep IDs unique** (`GR-1`, `GR-2`, …) so `/gc` and `/status` can reference and count them.

## The flywheel

```
review comment / recurring failure / drift
        │  capture (this skill)
        ▼
   golden-rules.md ──► /gc (drift-analyst) scans every change ──► surfaced before it ships
        ▲                                                            │
        └──────────── prune / refine when a rule misfires ◄─────────┘
```

`golden-rules.md` is **startup-loaded** (AGENTS.md points to it) — a feed-forward Guide — *and* the
checklist `/gc` enforces as a Sensor. Closing that loop is the point: human taste, captured once,
applied to every future change.

## Prune — entropy applies to the rules too

Rules rot. Delete dead rules; resolve rules that contradict each other. A `golden-rules.md` nobody
trusts is worse than none. Review it when it stops matching how the project actually works.

## Anti-patterns

- **Vague rules**: "write clean code", "be consistent" — uncheckable, so unenforceable.
- **No origin**: a rule with no failure behind it is a guess; guesses accumulate as noise.
- **Premature automation**: a brittle lint rule for a once-seen issue.
- **Unbounded growth**: 50 rules nobody reads. Prefer few, load-bearing rules.

## Related

- `/gc` + `drift-analyst` — scans changed code against these rules (the Sensor half).
- `anti-hallucination-gates` — a recurring "claimed done without evidence" is itself a capturable rule.
- `self-correction-loop` — a recurring fix pattern is a candidate rule.
- `docs-lookup` — when unsure how to phrase a Check command for an unfamiliar tool.
- `/session-end` — its flywheel reflection is the natural moment to capture the session's lessons.
