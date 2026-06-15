---
description: Post-implementation coverage-gap analysis via a fresh-context coverage-analyst subagent. Derives test obligations from code + spec, flags paths/binaries outside the test runner's scope, and recommends a minimal, oracle-independent-first test set. Read-only — run before marking a feature 'pass'; complements /verify.
allowed-tools: Task, Read, Bash
---

# /test-plan

Produce a **coverage plan** for the active feature: what *must* be tested, what the suite already
covers, what's missing (including paths the test runner never runs), and the minimal set of tests to
close the gaps. Runs **after** implementation — it complements `/verify` (which runs the *registered*
suite; this finds what's missing from it).

This is the post-implementation, code-aware counterpart to superpowers TDD's pre-implementation
test-first pass. Like `/verify`, it uses a **fresh-context** subagent so the analysis isn't biased by
the agent that wrote the code.

## Steps

1. **Dispatch `coverage-analyst`** via the `Task` tool:

   ```
   Task tool with:
     subagent_type: coverage-analyst
     prompt: Analyse test coverage for the active feature in feature_list.json (or the feature named in
             the arguments). Derive obligations from code + spec, diff against the test set and the
             verified run scope, and recommend a minimal oracle-independent-first test set. Follow the
             fixed report format in your instructions. Read-only — do not write code or tests.
   ```
   If the user passed a feature id or path as an argument, name it in the prompt.

2. **Surface the report verbatim** — `### Obligations derived`, `### Run-scope gaps`,
   `### Recommended tests`, `### Coverage verdict`, `### Uncertainties`. The point of fresh-context
   analysis is the user sees the analyst's actual words.

3. **If `### Uncertainties` is non-empty**: ask the user those questions before acting — the analyst
   escalated because an oracle couldn't be derived. Do not fabricate expected values.

4. **If verdict is GAPS**: offer to act on the recommendations —
   - write the recommended tests (oracle-independent first), and/or
   - register any orphan binary with the test runner (e.g. add `add_test` / `gtest_discover_tests`),

   then run `/verify` (and `/sanitize` for C/C++) to confirm the now-in-scope tests pass.

5. **If verdict is COVERED**: report it with the `.harness-anchor/coverage-<ts>.md` evidence path —
   that is the artifact for the "Coverage obligations" criterion in `anti-hallucination-gates`.

## When to invoke

- After implementing a feature, before flipping `feature_list.json` to `pass`
- When tests pass but you're unsure they exercise the real risks (numeric / large-data / no-oracle code)
- When reviewing whether a feature is genuinely covered

## When NOT to invoke

- Before any code exists (use superpowers `test-driven-development` for the pre-impl, spec-driven pass)
- Inside a subagent (subagents are single-level)

## Related

- `coverage-analyst` agent — what this command dispatches
- `test-coverage-design` skill — the discipline + design-technique / risk-checklist reference
- `anti-hallucination-gates` — the evidence gate the report feeds
- `/verify` — runs the registered suite; pair them (plan the coverage, then verify it passes)
