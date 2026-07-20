---
description: Run the full verification suite (build, type-check, tests, lint) via a fresh-context verification-runner subagent; reports evidence paths. Read-only by default; opt-in '--fix' runs a bounded auto-fix loop (max 2 cycles). Use before marking feature_list.json status as 'pass'.
allowed-tools: Task, Read, Bash, Edit, Write
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

2. **Receive the report**. It will be structured as `### Build`, `### Tests`, `### Integrity`, `### Verdict`, `### Recommendation` sections.

3. **Surface the report to the user verbatim** — do not paraphrase. The point of fresh-context evaluation is the user sees the evaluator's actual words.

4. **If verdict is READY TO MARK PASS**:
   - Ask the user: *"Verifier reports ready to mark <feature> as pass. Update feature_list.json now?"*
   - On yes: invoke `feature-state-keeper` skill behaviour to update with the evidence object from the report

5. **If verdict is NOT READY**:
   - Surface the specific failing criteria
   - Offer: (a) opt into the bounded auto-fix loop (see "`--fix` mode" below), (b) fix manually and re-run `/verify`, or (c) leave as-is and end the session

## `--fix` mode (opt-in auto-fix loop)

**Default `/verify` is read-only.** Enter auto-fix ONLY when the user explicitly opts in —
`/verify --fix` (the `--fix` token is in the command arguments) or a direct request like
"verify and fix what you can." Never enter this mode on a bare `/verify`.

When opted in AND the verdict is **NOT READY**, run a bounded fix→re-verify loop:

1. **Read the `### Recommendation`** from the report — the failing criteria + suggested next
   commands. That is your *only* sanctioned fix scope.
2. **Apply fixes for that scope, transparently** — show each change (file + short diff or
   description). Do NOT touch anything outside the recommendation; if a real fix would require
   that, STOP and ask the user first.
3. **Re-verify with a FRESH `verification-runner`** — a new `Task` dispatch, not the prior
   subagent's context. Independence per cycle is the point: a fresh evaluator can't inherit the
   fixing agent's optimism.
4. **Decide:**
   - READY → report "converged after N cycle(s)", list every change applied, then offer the
     feature_list.json update (step 4 above).
   - NOT READY and cycles completed < 2 → run one more cycle (back to 1).
   - NOT READY after **2 cycles** → **STOP**. Report honestly: what each cycle tried, what was
     applied, and the remaining failures with evidence paths. Never claim pass; never start a 3rd cycle.

### Hard limits (do not relax)
- **≤ 2 fix→re-verify cycles**, ever — the budget is the safety valve against thrash.
- **Every applied change is surfaced** — no silent edits. If you can't show it, don't do it.
- **Each re-verify is a fresh dispatch** — never self-grade code you just edited.
- **Recommendation-scoped only** — widening the fix surface needs the user's say-so.
- **Default-FAIL** — "pass" requires a fresh `verification-runner` PASS, not your assertion (invariant #8).

## When NOT to invoke

- Before any code is written for the active feature (no point verifying nothing)
- Inside a subagent (subagents are single-level; if you're in a subagent, your caller invoked `/verify`)

## Output budget

The report should be ≤500 lines total. If it grows beyond, the verifier should write `verify-summary.md` and just hand back the summary path.

## Related

- `verification-runner` agent — what this command dispatches
- `anti-hallucination-gates` skill — why fresh-context evaluation matters
- `feature-state-keeper` skill — how to record the evidence after passing
