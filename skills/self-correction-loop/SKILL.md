---
name: self-correction-loop
description: Use when a hook or tool returns a warning, lint error, type error, build error, or test failure after your edit. Iterate evidence-first instead of guessing. Stop when verification passes; do not loop forever.
---

# Self-Correction Loop

When your edit produces a warning/error signal, you're in a **correction loop**. This skill is the discipline that keeps the loop productive instead of thrashing.

## Trigger signals

You should engage this loop when ANY of these happen after your edit:

- `PostToolUse` hook injected `clang-tidy warnings:` / `lint warnings:` / similar
- A `Bash` command you ran returned non-zero exit
- A test runner reports failures
- A type-checker reports errors
- The user says "that broke X" / "it's failing now"

## The Loop (RED → diagnose → minimal-fix → GREEN)

This is **TDD's RED-GREEN-REFACTOR adapted for correction**:

```
1. CAPTURE the signal
   - What is the EXACT error message?
   - Which file / line?
   - What was my last change?

2. DIAGNOSE root cause (not symptom)
   - Read the error carefully — the answer is often in it
   - Check if my change broke an invariant elsewhere
   - Do NOT guess. If unclear, narrow with prints / smaller test cases

3. MINIMAL FIX
   - Smallest possible change that resolves THE specific issue
   - No "while I'm here" tangents (that's scope creep — see scope-jump)
   - Do NOT mask the error (e.g. catch-and-ignore) without explicit reason

4. RE-VERIFY
   - Run the same command that produced the signal
   - Observe the new output
   - Capture it as evidence
```

## Loop budget

If you've iterated 3 times on the same signal without resolving it, **stop and escalate**:

- Read more of the surrounding code than you have so far
- Consult [Context7 / WebSearch] for the specific error class
- Tell the user: *"I've tried 3 approaches to <issue>. Latest output: <...>. I need more context. Recommend either <option A> or <option B>?"*

Looping > 5 times is almost always a sign of:
- Wrong mental model of the bug → step out, re-read
- Missing tool/dependency → install it before continuing
- Genuinely ambiguous case → consult the user

## What "fixed" looks like

- The original failing command now succeeds (exit 0 + expected output)
- You can articulate WHY it failed and WHY the fix resolves it
- No new failures introduced (re-run the broader test suite, not just the one test)

If you can't articulate WHY, your fix is suspicious — even if green. State this uncertainty per `anti-hallucination-gates`.

## Anti-patterns

- **Silencing instead of fixing**: `// @ts-ignore`, `--no-verify`, deleting failing tests, broadening exception catches. These hide problems; sometimes they're warranted but require explicit user note.
- **Chasing different bug**: a lint warning on line 42 doesn't justify refactoring lines 100-200.
- **Optimistic re-run**: running the same failing test again "in case it was flaky" without changing anything. Flakiness is a separate issue to track, not a fix.

## How this interacts with hooks

`harness-anchor` hooks are **warn-only**. They inject `additionalContext` describing the problem; they don't block your action. That means:

- You *can* ignore a warning, but the warning is recorded in your context — the user can see you saw it. If you ignore, do so deliberately and say why.
- A test failure injected by PostToolUse should generally be addressed before moving on; if you choose to defer it (e.g., feature is mid-build and the test is for the next milestone), note it as a known-failing in `session-handoff.md`.

## When this skill is NOT applicable

- The signal is about a different feature than the one you're working on. Note it as `planned` in `feature_list.json` and continue current scope.
- The error is in third-party code you don't own. Document it; route to the right project.

## Related

- `anti-hallucination-gates` — keep claims honest while looping
- `systematic-debugging` (superpowers) — for deep debugging beyond surface signals
- `verification-runner` (agent) — for fresh-eyes evaluation of "is this really fixed?"
