---
name: anti-hallucination-gates
description: Use before claiming "done", "fixed", "complete", "passing". Default-FAIL contract — every criterion needs evidence; express uncertainty if missing.
---

# Anti-Hallucination Gates

The most common agent failure is **declaring victory too early**. This skill is the gate between "I think it works" and "evidence proves it works".

## The Iron Rule

> No claim of "done" / "fixed" / "passing" without a concrete artifact path proving it.

A claim like *"I fixed the bug"* is incomplete. The proper form:

> "Fixed by commit `abc123`. Test `tests/foo.test.ts::handles-edge-case` now passes (output captured in `.harness-anchor/test-2026-05-28.log`). Build still passes (`.build/last-build.log` exit 0)."

## Default-FAIL Evaluation Contract

Adapted from [Anthropic's Code with Claude 2026 reference impl](https://github.com/anthropics/cwc-long-running-agents):

> "Every criterion starts false; the agent can't mark it passing without opening evidence first."

### Standard criteria (adapt to project)

| Criterion | What counts as evidence |
|---|---|
| **Compile / build passes** | Build log path + exit code 0, or compiler stdout/stderr captured |
| **Type-check passes** | `tsc --noEmit` (or equivalent) output |
| **Tests pass** | Test runner output showing N passed, **0 failed**, **0 errored** |
| **Static analysis** | Lint report file, OR explicit "no warnings" line in output |
| **Manual smoke** | Concrete steps + observed result (only if the above can't cover) |

### Filling out evidence in `feature_list.json`

```json
{
  "id": "doc-list-rendering",
  "status": "pass",
  "evidence": {
    "timestamp": "2026-05-28T13:45:21Z",
    "commit": "abc123def456",
    "artifacts": [
      ".harness-anchor/build-2026-05-28T13-44.log",
      ".harness-anchor/test-2026-05-28T13-45.txt"
    ],
    "notes": "All 47 tests pass. Build clean. clang-tidy: 0 warnings on changed files."
  },
  "completedAt": "2026-05-28T13:45:21Z"
}
```

**`evidence: null` ⇒ `status` cannot be `"pass"`.** This is enforced by `feature_list.schema.json`.

## Calibrated Uncertainty (2026 consensus)

When evidence is missing or partial, do NOT bluff. The 2026 LLM-hallucination research consensus is:

> "Aim for calibrated uncertainty: systems that transparently signal doubt and can safely refuse to answer when unsure."

Templates for expressing uncertainty:

- *"I am uncertain whether the test passes because I didn't run it. Recommend `npm test -- --testPathPattern foo` to verify."*
- *"The build appears to succeed based on no error in the output, but I did not see an explicit success line. Recommend `cmake --build .build && echo BUILD_OK`."*
- *"This fix may resolve the issue, but I have not reproduced the original failure. To gain confidence, run `./repro.sh` before and after the change."*

These statements **earn user trust**. Confident-but-wrong claims destroy it.

## Anti-patterns

Do NOT say:
- "Should work now."
- "The build should pass."
- "Tests should be green."
- "This looks correct."

Say instead:
- "Build passes (evidence: <path>) / Build pending verification (recommend: <command>)"
- The test status alongside a captured artifact path.

## The "should" detector

When you find yourself typing "should", "probably", "I think", or "looks like" about a behavioural claim, pause. Either:
- Run the command to verify, then state the observed result, OR
- Explicitly mark the claim as unverified per the templates above.

## Pre-claim checklist

Before saying ANY of {"done", "fixed", "ready", "complete", "passing", "working"}:

```
- [ ] I ran the build/compile, observed exit code 0
- [ ] I ran the test suite, observed N passed / 0 failed
- [ ] I have a file path for each piece of evidence
- [ ] feature_list.json is updated with evidence object + timestamp + commit
```

If any box is unchecked: state uncertainty explicitly, do NOT flip status to `pass`.

## When to invoke

- The user asks "is it done?"
- You're about to update `feature_list.json` `status` to `"pass"`
- You're about to say "the fix should work"
- The PostToolUse hook injected warnings — do NOT silently ignore them; surface and address per `self-correction-loop`

## Looking up evidence commands for unfamiliar frameworks

When the project uses a test/lint framework you don't have committed to memory (Catch2, doctest, ruff, deno test, etc.) — invoke the `docs-lookup` skill before constructing the verification command. The lookup result becomes part of the evidence trail.

Bluffing the command and not actually running it is the anti-pattern this skill exists to prevent — that's why **lookup precedes execution** here.

## Related

- `verification-before-completion` (superpowers) — the same Iron Law (no completion claim without fresh evidence). This skill is its harness-anchor counterpart and **superset**: it adds the on-disk evidence record (`feature_list.json`) and the `/verify` subagent. One verification run satisfies both gates — capture the evidence once, don't re-verify.
- `feature-state-keeper` — actual writes to feature_list.json
- `self-correction-loop` — what to do when evidence shows failure
- `/verify` command — full automated verification pass via `verification-runner` subagent
