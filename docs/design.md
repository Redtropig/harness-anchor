# Design notes

<!-- doc-align: 2d9a7e664e38393ceae9f77f3434ceb1dff1399e · 2026-07-31 · harness-anchor v0.17.1 -->

Why harness-anchor is shaped the way it is. [README.md](../README.md) states what
each component does; this file states why it was built that way and what was
rejected. Content here is the long form of the README's "Design notes" bullets.

**Scope of that verification:** the `doc-align` commit above is the tree this
file's claims were read against. Sections were checked by reading the named
component (`hooks/*`, `skills/*/SKILL.md`, `scripts/*`); no gate was executed for
this document, because it makes no claim a gate covers.

## The five-subsystem mapping

Grounded in Anthropic's [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
and the [learn-harness-engineering](https://walkinglabs.github.io/learn-harness-engineering/)
five-subsystem model.

| Subsystem | Provided by |
|---|---|
| Instructions | superpowers + harness-anchor (`using-harness-anchor`) |
| State | **harness-anchor** (`feature_list.json`, `progress.md`, `session-handoff.md`, `golden-rules.md`; cold history: `progress-archive.md` / `feature_archive.json`) |
| Verification | **harness-anchor** (`anti-hallucination-gates`, `/verify`) + superpowers (TDD) |
| Scope | **harness-anchor** (active-feature lock, scope-jump detection) |
| Lifecycle | **harness-anchor** (`init.sh`, `/session-end`) |

## Warn-only by design

PostToolUse / Stop / UserPromptSubmit / PreCompact hooks **never block**. Each
surfaces its reminder through whatever channel its event actually has:
PostToolUse and UserPromptSubmit — and SessionStart — inject `additionalContext`
the agent can self-correct from; Stop has no such channel, so its reminder uses
`systemMessage`; PreCompact reaches only the user, via a marker file plus
`systemMessage`, because no agent turn exists before compaction runs. The shape
follows Anthropic's "feedback loops > gates" guidance.

The rejected alternative is the obvious one: make the hooks refuse. A `deny`
decision on a scope-creep warning would stop the wrong edits and also the right
ones, and the hook cannot tell them apart — it sees a file path, not an
intention. That imprecision is structural rather than a tuning problem: a hook
observes a proxy signal, and the authoring rules require asserting that the
proxy covers the failure it targets — or documenting the residual blind spot
where it cannot. A warning the agent can read and overrule costs a few tokens; a
gate costs a blocked tool call every time its proxy misfires. This is an
invariant, not a preference: no hook may emit `"permissionDecision": "deny"`,
`"stopReason"`, or `decision: "block"`.

## Default-FAIL, both directions

Every criterion starts false; the agent must produce a concrete evidence path
(build log, test output, lint report) before a feature counts as done. That
stance has a narrow mechanical enforcement point: `evidence: null` means `status`
cannot be `pass`, and `feature_list.schema.json` rejects the pair. `done_criteria`
itself is a list of statements rather than booleans — the default-false is the
discipline, and the schema is the part that bites. Negative claims are bound the
same way: asserting something is absent requires the search scope actually
covered and the date it was checked — an empty `command -v` proves nothing about
installation. See `skills/anti-hallucination-gates/`.

Judgement-shaped negatives ("this is impossible", "that won't work") are
deliberately out of scope. They carry no evidence path, and admitting them would
turn the contract into unverifiable moralising.

## Progressive disclosure

SessionStart injects ≤ 3000 tokens (banner + an adaptive `PROJECT-TOC` view — the
directory map, or the full file list on a small repo — + the meta-skill, injected
slimmed: frontmatter stripped; cpp-only sections gated by cpp-detect;
`os-<name>` sections gated by the runtime platform, HA_OS). Deeper references
live in skill subfolders — including per-platform `platform/<os>.md` sidecars —
loaded on demand.

The budget is a hard constraint rather than a target because the cost is paid on
*every* conversation, including the ones that never touch a C/C++ file or need a
platform sidecar. Headroom belongs to the project-specific table of contents and
handoff, not to a fatter generic body.

## docs-lookup is the canonical procedure

No inline Context7 → WebSearch waterfalls in other skills — they all reference
`docs-lookup` for the procedure (including failure-mode detection and
calibrated-uncertainty fallback).

Duplicating the waterfall into each skill was the alternative, and it fails the
same way every copy-paste convention fails: the failure-mode detection and the
uncertainty fallback get updated in one copy and not the others, and the skills
that quietly drift are the ones nobody re-reads.

## Fresh-context evaluation

`/verify` dispatches `verification-runner` in a subagent with read-only tools;
mitigates "self-grading" leniency per Anthropic's March 2026 three-agent
architecture.

The same reasoning produces `coverage-analyst` (`/test-plan`) and
`drift-analyst` (`/gc`). All three are read-only by frontmatter, not by
convention: an evaluator that can edit the thing it is grading has an incentive
to make the finding go away rather than report it.

## Coverage analysis is post-implementation

`/test-plan` + `coverage-analyst` derive what *must* be tested from code + spec
and flag paths outside the runner's scope — the code-aware pass superpowers'
(deliberately code-blind) TDD can't do; pre-implementation test-first stays TDD's
job. Reliability against correlated LLM blind spots (code and tests both
LLM-generated) leans on oracle-independent tests (metamorphic / differential /
property) + a risk-construct checklist, not the model's judgement.

## Entropy governance is a flywheel

Recurring mistakes become checkable rules in `golden-rules.md` (the
`capturing-golden-rules` skill); `/gc` dispatches a fresh-context `drift-analyst`
that scans *changed* code against those rules + generic slop heuristics (dead
code, duplication, doc-drift) and **recommends** — it never auto-refactors.
Capture is **write-at-realization** — the rule lands the turn the signal appears;
`/session-end`'s flywheel is the safety net, not a new ceremony (Garg's Feedback
Flywheel; the solo-appropriate, lightweight form per the harness-engineering
practical guide).

## Durable memory flushes at realization

Lessons, decisions, and milestones are written to disk in the turn they're
recognized — rough golden-rule stubs are legitimate (origin quotes the evidence
at hand; Check starts `manual review`). Four warn-only sentinels back the
contract at the danger moments: context filling (PostToolUse two-stage watermark
— per-stage once, any tool), compaction imminent (PreCompact forensics marker +
user notice), just-compacted (SessionStart caution line, forensics-enriched),
stopping (Stop nudge).

Deferring the write to session end was the alternative, and
`capturing-golden-rules` rejects it explicitly: `/session-end`'s reflection is
the safety net for anything missed, not the capture moment. The turn that
produced the signal is the only turn where the evidence is still at hand to
quote.

## State budgets and archival

Hot files stay bounded on long-lived projects (`progress.md` keeps the newest ~20
sessions; `feature_list.json` keeps live features + the 10 most recent `pass`
entries); `/session-end` offers moving the excess verbatim — evidence intact — to
git-tracked archives via `scripts/state-archive.mjs` (deterministic, idempotent,
crash-convergent, aborts on malformed JSON rather than "repairing" the ledger).
The SessionStart banner warns (warn-only) when a budget is exceeded. History is
moved, never deleted; archives are grep-only reference.

The abort-rather-than-repair choice is deliberate. A ledger repaired by
heuristic is a ledger whose evidence trail can no longer be trusted, which
defeats the point of keeping one.

## Heavy operations are commands, not hooks

Sanitizer builds (`/sanitize`) and the opt-in auto-fix loop (`/verify --fix`,
bounded to ≤ 2 fresh-evaluated cycles) far exceed the ≤ 5s warn-only hook budget
— a hook may *suggest* `/sanitize`, but never runs it inline.

The bound on the auto-fix loop is a second budget of the same kind —
`commands/verify.md` calls it "the safety valve against thrash". The failure it
prevents is named in `self-correction-loop`: three to five edits to one file
chasing the same unclearing signal is micro-adjusting a single approach, and the
classic terminal move is "fixing" a failing test by rewriting it to match the
code.

## Mechanical halves are scripts

`/status`, `/anchor`, `/cpp-init`, `/session-end` and the golden-rules Check tier
run deterministic `scripts/*` helpers (single source of truth, unit-tested,
byte-stable output); the command markdown keeps only judgment + interaction.
Cheaper per invocation, and "never silently overwrite" is enforced as interface
shape — `scaffold.sh`'s default path has no overwrite branch at all.

Enforcing that as interface shape rather than as an instruction is the point. An
instruction not to overwrite is a thing an agent can forget under pressure; a
code path that does not exist is not.

## C/C++ as a first-class project type

Build system auto-detect (CMake/Meson/Make/Bazel), `compile_commands.json`-aware
clang-tidy, sanitizer build templates.

Gating is by detection, not by configuration: `scripts/cpp-detect.sh` decides,
and the C/C++ skills carry a frontmatter trigger condition referencing the
detected build system so they stay dormant in non-C/C++ projects. A user who
never writes C++ should not pay for this in context budget or in false triggers.
