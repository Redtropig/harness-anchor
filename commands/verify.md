---
description: Run full verification suite (build, type-check, tests, lint) via the verification-runner subagent. Read-only, reports evidence paths. Use before marking feature_list.json status as 'pass'.
allowed-tools: Task, Read, Bash
---

# /verify

Run the project's full verification suite via a **fresh-context** subagent and produce an evidence-based report.

This is the Anthropic three-agent architecture's "evaluator" role — independent from the code-writing agent so leniency bias is minimized.

## Steps

1. **Dispatch `verification-runner` subagent** via the `Task` tool:

   ```
   Task tool with:
     subagent_type: verification-runner
     prompt: Verify the active feature in feature_list.json. Use the project's
             documented verification commands from AGENTS.md if present; otherwise
             infer from project type (cmake, npm, cargo, etc.). Follow the fixed
             report format in your skill instructions. Do not modify code.
   ```

2. **Receive the report**. It will be structured as `### Build`, `### Tests`, `### Verdict`, `### Recommendation` sections.

3. **Surface the report to the user verbatim** — do not paraphrase. The point of fresh-context evaluation is the user sees the evaluator's actual words.

4. **If verdict is READY TO MARK PASS**:
   - Ask the user: *"Verifier reports ready to mark <feature> as pass. Update feature_list.json now?"*
   - On yes: invoke `feature-state-keeper` skill behaviour to update with the evidence object from the report

5. **If verdict is NOT READY**:
   - Surface the specific failing criteria
   - Ask the user whether to fix-and-re-verify, or to leave as-is and end session

## When NOT to invoke

- Before any code is written for the active feature (no point verifying nothing)
- Inside a subagent (subagents are single-level; if you're in a subagent, your caller invoked `/verify`)

## Output budget

The report should be ≤500 lines total. If it grows beyond, the verifier should write `verify-summary.md` and just hand back the summary path.

## Related

- `verification-runner` agent — what this command dispatches
- `anti-hallucination-gates` skill — why fresh-context evaluation matters
- `feature-state-keeper` skill — how to record the evidence after passing
