# Command Manual — harness-anchor

<!-- doc-align: 8cb5fc01e9623a0b3a477918df89711caf402905 · 2026-07-03 · harness-anchor v0.8.0 -->
> **Aligned with commit** [`8cb5fc01e9623a0b3a477918df89711caf402905`](https://github.com/Redtropig/harness-anchor/commit/8cb5fc01e9623a0b3a477918df89711caf402905) (harness-anchor v0.8.0, 2026-07-03). Verified against `commands/*.md` at this commit; re-verify and bump this marker if the command set changes.

Reference for every slash command shipped by harness-anchor: what it does, **when to
reach for it**, its arguments, prerequisites, outputs, and how the harness reminds you to
use it.

> **All commands are manual.** In Claude Code, slash commands are **user-invoked and never
> auto-trigger** — only *skills* auto-load (the model pulls them by `description`). So every
> command below runs only when you type it. The harness can't run them for you; what it
> *can* do is **recommend** the right one at the right moment (via hooks and the
> session-start meta-skill). The "How it surfaces" line on each command tells you where that
> nudge comes from.

---

## Conventions shared by all commands

- **Never silent-overwrite.** A command that would write a file that already exists and is
  non-empty asks first via `AskUserQuestion` `[Overwrite / Skip / Show diff]` — this applies
  to the scaffolding commands `/anchor` and `/cpp-init`. (`/session-end` deliberately
  *overwrites* `session-handoff.md` each session — it is a living snapshot, not user content.)
- **Never auto-commit.** Commands stage or *suggest* a commit but leave the decision to you;
  source-code changes are always your call. `/session-end` and `/index-project` offer a
  commit of *state files only*, never your source.
- **Default-FAIL evidence.** Nothing is reported "passing" without a concrete artifact
  (a build/test log, a `.harness-anchor/*.log` path). Missing evidence ⇒ the status stays
  `in-progress` and the command says so.
- **`${CLAUDE_PLUGIN_ROOT}`** is the installed plugin path; commands call their helper
  scripts (`cpp-detect.sh`, `index-builder.mjs`, …) from there.

---

## Quick reference

| Command | One-line purpose | When | Writes? | Scope |
|---|---|---|---|---|
| [`/anchor`](#anchor) | Scaffold harness state files into a project | Project is un-anchored (no `feature_list.json`) | ✍️ creates files | any |
| [`/cpp-init`](#cpp-init) | Add C/C++ config + sanitizer build | Right after `/anchor` in a C/C++ project | ✍️ creates files | C/C++ |
| [`/index-project`](#index-project) | (Re)build `PROJECT-TOC.md` file index | TOC missing/stale, or before a broad file search | ✍️ writes TOC | any (git) |
| [`/verify`](#verify) | Fresh-context build/test/lint evaluation | Before marking a feature `pass` / claiming "done" | 🔒 read-only (`--fix` writes) | any |
| [`/test-plan`](#test-plan) | Fresh-context coverage-gap analysis | After implementing, before marking a feature `pass` | 🔒 read-only | any |
| [`/gc`](#gc) | Fresh-context code-drift / entropy scan | After a batch of generated code, before `/session-end` | 🔒 read-only | any |
| [`/sanitize`](#sanitize) | Run tests under ASan+UBSan (TSan separately) | After a C/C++ change, or before merging C/C++ | ✍️ build + log only | C/C++ |
| [`/status`](#status) | Read-only "where am I" snapshot | Anytime you want the current state | 🔒 read-only | any |
| [`/session-end`](#session-end) | Write handoff + progress, offer commit | At a stopping point / before ending | ✍️ writes state files | any |

---

## Typical lifecycle

```
New project       /anchor ──▶ /cpp-init (C/C++ only) ──▶ /index-project ──▶ bash init.sh
                     │
During work        edit ──▶ /verify    (before flipping a feature to "pass")
                        ├─▶ /test-plan (coverage gaps: untested paths / outside the run scope)
                        ├─▶ /gc        (drift / entropy: dead code, duplication, doc-drift, golden-rule violations)
                        └─▶ /sanitize  (C/C++ runtime check: crashes / leaks / UB / races)
Check state        /status            (anytime, read-only, writes nothing)
End of session     /session-end ──▶ offers TOC refresh + commit of state files
```

---

## `/anchor`

**Purpose.** Initialize harness-anchor's state files in the current project (the
"Initializer Agent" pattern from Anthropic's harness guidance).

**When to use.** The very first time you bring a project under harness-anchor — i.e. there's
no `feature_list.json` yet. Run it once per project.

**What it does.** Detects project type (`cpp-detect.sh`), then scaffolds, with placeholder
substitution (project name, ISO-8601 timestamp, git SHA):
`AGENTS.md`, `feature_list.json`, `feature_list.schema.json`, `init.sh` (chmod +x),
`progress.md`, `session-handoff.md`, `PROJECT-TOC.md`, `context-budget.md`.

**Arguments.** None.

**Prerequisites.** Best run inside a git repo — if not, it asks whether to `git init` first
(recommended) or continue (TOC freshness then can't be verified — reports `not-git`).

**Writes / side effects.** Creates the files above. Existing non-empty files trigger the
overwrite prompt. Does **not** commit (review the diff yourself first).

**How it surfaces.** The SessionStart banner shows `Active feature: none (run /anchor to
scaffold)` and `Last session handoff: (no session-handoff.md — run /anchor …)` when the
project isn't anchored.

**Refuses / asks when.** Not a git repo (asks); `feature_list.json` already valid (skips it,
tells you).

**Related.** `/cpp-init` (C/C++ layer on top) · `/index-project` (fills the TOC) ·
`using-harness-anchor` skill.

---

## `/cpp-init`

**Purpose.** Add C/C++-specific harness files on top of a generic `/anchor` scaffold.

**When to use.** Right **after `/anchor`** in a C/C++ project — especially when the project
has no `.clang-format` / `.clang-tidy` yet.

**What it does.** Confirms `/anchor` ran (refuses otherwise), detects the build system via
`cpp-detect.sh`, then:

- Replaces `init.sh` with a build-system template (`cmake` / `meson`; `make`/`bazel` keep
  the generic one with a warning).
- Drops `.clang-format` (LLVM base, 4-space indent, 100-col) and `.clang-tidy`
  (bugprone / cert / clang-analyzer / cppcoreguidelines baseline).
- Drops `scripts/lint.sh` — the sysroot-correct clang-tidy entry point (macOS Homebrew
  clang-tidy fails to parse without the SDK sysroot; see `cpp-static-analysis`).
- Drops `scripts/sanitizer-build.sh` (CMake projects; other build systems: asks).

**Arguments.** None.

**Prerequisites.** `/anchor` already run (`feature_list.json` present) **and** a C/C++ project
(`cpp-detect.sh` → `is_cpp_project: true`). Refuses otherwise.

**Writes / side effects.** Creates the config files above; existing non-empty ones trigger
the overwrite prompt. Does **not** commit.

**How it surfaces.** The SessionStart banner shows
`C/C++ setup: not initialized (no .clang-format/.clang-tidy) — run /cpp-init` when the
project is detected as C/C++, is anchored, but has no clang config.

**Refuses when.** Not C/C++; build system `unknown` with no C/C++ sources (suggests picking
a build system first).

**Related.** `/anchor` · `/sanitize` (uses the sanitizer build this drops) ·
`cpp-static-analysis` / `cpp-formatting` skills.

---

## `/index-project`

**Purpose.** (Re)build `PROJECT-TOC.md` — a `## Directory map` (per-directory file/subdir
counts) over a one-line-per-file `## Files` index of every git-tracked source file, with a
git-commit freshness anchor.

**When to use.** When `PROJECT-TOC.md` is absent or **stale** (its commit anchor no longer
matches `HEAD`), or before a broad file-finding sweep so the agent consults the index instead
of `Glob`.

**What it does.** Runs `scripts/index-builder.mjs`, which reads `git ls-files`, skips
binaries / files > 100 KB / build dirs, extracts a ≤ 80-char summary per file, **emits a
`## Directory map`** (per-directory counts) above `## Files`, **preserves the human-edited
`## Decisions` section**, and stamps
`<!-- generated-at-commit: <HEAD SHA> -->`. Then reports the diff (N added / M removed / K
updated) and suggests `git commit -m 'chore: refresh project index'`.

**Arguments.** None.

**Prerequisites.** A git repository (errors out otherwise). **Note:** this is the one command
that needs **Node.js** (for `index-builder.mjs`); everything else is bash + git (+ python3).

**Writes / side effects.** Writes `PROJECT-TOC.md`. Bootstraps it from the template if
missing. Does **not** commit.

**How it surfaces.** The SessionStart banner shows
`TOC freshness: absent … run /index-project` or `stale … run /index-project`.

**When not to run.** Mid-feature after changing only 1–2 files (ignore the stale-TOC warning
and regenerate at `/session-end`); in CI.

**Related.** `/anchor` (cleaner first scaffold) · `index-curator` agent (the sole TOC
writer) · `project-indexing` skill.

---

## `/verify`

**Purpose.** Run the project's full verification suite (build / type-check / tests / lint) in
a **fresh-context** subagent and produce an evidence-based report. This is the Anthropic
three-agent architecture's "evaluator" role, kept independent from the code-writing agent to
minimize leniency bias.

**When to use.** Before you mark a feature `pass` in `feature_list.json`, or before claiming
anything is "done / fixed / passing".

**What it does.** Dispatches the `verification-runner` subagent (read-only), which runs the
documented verification commands (from `AGENTS.md`, else inferred from project type) and
returns a fixed report: `### Build`, `### Tests`, `### Deliverable state` (clean tree → evidence reflects the committed `HEAD`; dirty tree → evidence reflects only the working tree, so `HEAD` isn't proven buildable), `### Verdict`, `### Recommendation`. The
command surfaces that report **verbatim**. On a `READY` verdict it offers to update
`feature_list.json` with the evidence; on `NOT READY` it surfaces the failing criteria.

**Arguments.**

- *(none)* — read-only verification.
- **`--fix`** — opt into a **bounded auto-fix loop**. Only on an explicit `/verify --fix`
  (or a direct "verify and fix" request), never on a bare `/verify`.

**`--fix` mode (hard limits).** On a `NOT READY` verdict it applies only the report's
`### Recommendation`-scoped fixes (every change shown), then **re-verifies with a fresh
`verification-runner`** — repeating at most **2 cycles**, stopping on pass or budget
exhaustion. It never self-grades, never widens scope without asking, and never claims pass
without a fresh PASS (invariant #8). Triage each finding with `superpowers:receiving-code-review`
rigor — verify it against the code before applying, never blind-application (see
`self-correction-loop`).

**Prerequisites.** Some code written for the active feature. Not callable from inside a
subagent (subagents are single-level).

**Writes / side effects.** **Read-only by default.** Only `--fix` edits files (transparently,
recommendation-scoped). Updating `feature_list.json` happens only with your confirmation.

**How it surfaces.** PostToolUse warns "consider re-running /verify" after you edit source
that a passed feature depends on; the `anti-hallucination-gates` skill points here before any
"done" claim.

**Output budget.** Report ≤ 500 lines; beyond that the verifier writes `verify-summary.md`
and hands back the path.

**Related.** `verification-runner` agent · `anti-hallucination-gates` skill ·
`feature-state-keeper` skill · `/sanitize` (runtime-instrumented deepening).

---

## `/test-plan`

**Purpose.** Produce a **coverage plan** for the active feature in a **fresh-context** subagent:
what *must* be tested, what the suite already covers, what's missing — including paths the test
runner never executes — and the minimal set of tests to close the gaps. The post-implementation,
code-aware counterpart to superpowers' (deliberately code-blind) TDD.

**When to use.** After implementing a feature, before flipping it to `pass`; or whenever tests
pass but you're unsure they exercise the real risks (numeric / large-data / no-oracle code).

**What it does.** Dispatches the `coverage-analyst` subagent (read-only), which (1) scans the code
against a risk-construct checklist, (2) derives the spec's behavioural obligations, (3) diffs both
against the suite **and the verified run scope** — flagging the run-scope pattern of a binary built but
never registered with the test runner (so `/verify` + `/sanitize` silently skip it) — and (4)
recommends a minimal **oracle-independent-first** test set (metamorphic / differential / property —
correctness from a relation, not a guessed expected value). Returns a fixed report
(`### Obligations derived` · `### Run-scope gaps` · `### Recommended tests` · `### Coverage verdict`
· `### Uncertainties`) and persists it to `.harness-anchor/coverage-<ts>.md`.

**Arguments.** *(optional)* a feature id or path; else the active feature from `feature_list.json`.

**Prerequisites.** Code written for the active feature (it reads the implementation). Not callable
from inside a subagent (single-level).

**Writes / side effects.** **Read-only** — it recommends; you write the tests. The only file it
creates is the evidence report under `.harness-anchor/` (the gitignored runtime path).

**How it surfaces.** The `test-coverage-design` skill points here when deciding what to test or
before a "done" claim; `anti-hallucination-gates`'s "Coverage obligations" criterion takes the
`coverage-<ts>.md` report as evidence; `verification-runner` recommends it when it spots a built
binary the runner never runs.

**Reliability note.** Because code and tests are both LLM-generated, a "different agent" only
decorrelates context bias, not shared model priors — so the analyst prefers oracle-independent
tests and a deterministic risk checklist, and **escalates** ambiguous oracles to you rather than
fabricating an expected value.

**Related.** `coverage-analyst` agent · `test-coverage-design` skill · `anti-hallucination-gates`
skill · `/verify` (runs the registered suite; pair them) · superpowers `test-driven-development`
(the pre-implementation counterpart).

---

## `/gc`

**Purpose.** Scan recent work for **drift / entropy / AI slop** — code that compiles and passes
tests but has rotted from the project's conventions (duplicated helpers, dead code, inconsistent
error handling, stale docs, golden-rule violations). The garbage-collection sensor of
harness-engineering's Concept ⑥ — **not** `git gc`.

**When to use.** After a batch of generated code, before `/session-end`; before merging; or when
`golden-rules.md` has grown and you want recent changes checked against it.

**What it does.** Dispatches the `drift-analyst` subagent (read-only, fresh-context), which loads
`golden-rules.md`, bounds the scope to **changed files** (`git diff` vs `HEAD`) or the active
feature, runs each rule's Check, applies generic drift heuristics (duplication, dead code, oversized
files, TODO pileup, **doc-drift**), grades findings **must / should / nice**, and persists
`.harness-anchor/drift-<ts>.md`. Returns a fixed report (`### Golden-rule violations` ·
`### Generic drift findings` · `### Recommended actions` · `### Verdict` CLEAN / DRIFT FOUND ·
`### Uncertainties`), surfaced **verbatim**.

**Arguments.** *(optional)* a path or feature id; else changed files / the active feature.

**Prerequisites.** Code written or changed to scan. Not callable from inside a subagent
(single-level).

**Writes / side effects.** **Read-only** — it recommends; you decide. The only file it creates is
the evidence report under `.harness-anchor/` (the gitignored runtime path). On DRIFT FOUND it
*offers* (never auto-applies) scoped fixes, a golden-rule capture, or a handoff note — it never
bulk-refactors.

**How it surfaces.** No hook nudge by design (like `/status`) — the `capturing-golden-rules` skill
and the `using-harness-anchor` meta-skill recommend it (after a batch of generated code, before
wrapping up). One of three read-only sensors: `/verify` (build/test/lint pass), `/test-plan`
(coverage / run-scope), `/gc` (drift / maintainability).

**Distinct from.** `/verify` and `/test-plan` answer "does it pass?" and "is it tested?"; `/gc`
answers "has it drifted?" — different sensors, pair them.

**Related.** `drift-analyst` agent · `capturing-golden-rules` skill (turn a finding into a rule) ·
`/verify` · `/test-plan` · `golden-rules.md` state file.

---

## `/sanitize`

**Purpose.** Build a C/C++ project under runtime sanitizers and run its tests, reporting in
fixed sections. Catches what static analysis can't: use-after-free, leaks, undefined
behavior, data races.

**When to use.** After a C/C++ source change, before merging C/C++ work, or to chase a
crash / leak / hang / intermittent failure.

**What it does.** Confirms C/C++ (`cpp-detect.sh`), locates or materializes
`scripts/sanitizer-build.sh`, then builds + tests under the chosen config and tees output to
`.harness-anchor/sanitize-<config>-<ts>.log`. Reports:
`### Build` · `### Tests` · `### Sanitizer findings` · `### Verdict` (CLEAN / DIRTY /
INFRA-FAIL) · `### Recommendation`. An abort of the sanitizer tooling *itself* (e.g. an
`ASAN_OPTIONS` flag unsupported on this OS) is reported as **INFRA-FAIL** — not a code
finding, and never CLEAN; the fix path is `cpp-sanitizers` platform notes / `docs-lookup`.

**Arguments.** None (it asks which config when the symptom is ambiguous).

**Configuration.** **ASan + UBSan by default** (combinable, widest coverage). **TSan runs in
a separate build** (mutually exclusive with ASan) — reach for it on a suspected data race or
hang.

**Prerequisites.** A C/C++ project **with tests** (sanitizers instrument *test execution* —
no tests, nothing to exercise). A clang/gcc toolchain; missing tools are reported as
`MISSING TOOLCHAIN`, never silently skipped.

**Writes / side effects.** A sanitizer build dir + the evidence log under `.harness-anchor/`
(the one gitignored runtime path). No source changes. **Never auto-suppresses** a finding —
third-party noise gets a suppression *suggestion* for you to approve.

**How it surfaces.** PostToolUse appends a one-line "consider /sanitize" suggestion to an
existing warning after a C/C++ source edit — it never runs the sanitizer inline (a
build+test cycle far exceeds the ≤ 5 s warn-only hook budget; that's why this is a command,
not a hook).

**Refuses when.** Not C/C++; no tests; called from inside a hook.

**Related.** `cpp-sanitizers` skill (what each catches, reading output, suppressions) ·
`/verify` (general gate) · `templates/cpp/sanitizer-build.sh.tpl`.

---

## `/status`

**Purpose.** A read-only "where am I?" snapshot of the project. Everything at a glance,
nothing written.

**When to use.** Anytime you want the current state — mid-session re-orientation, or when a
fresh agent asks "what's going on here?". It's the on-demand, read-only sibling of the
SessionStart banner.

**What it does.** Prints, in fixed order: `## Status — <project>`, `### Active feature`,
`### Feature counts` (planned / in-progress / pass / blocked), `### Git working tree`
(`git status --porcelain`), `### TOC freshness` (`toc-freshness.sh`),
`### Session handoff (head)` (first 15 lines of `session-handoff.md`), and `### Harness health`
(golden-rules count, last `/gc` scan + verdict, active-feature + handoff staleness — a few signals,
not a dashboard).

**Arguments.** None.

**Prerequisites.** An anchored project — if `feature_list.json` is missing it reports
"Project not anchored — run `/anchor` first" and stops.

**Writes / side effects.** **None.** It never touches `feature_list.json`, `progress.md`, or
`session-handoff.md`. Use it freely.

**How it surfaces.** By design it has **no hook nudge** — it would duplicate the SessionStart
banner and create noise. Instead the `using-harness-anchor` meta-skill recommends it
whenever you ask "where am I / what's the state".

**Related.** `/session-end` (the *writing* sibling) · `feature-state-keeper` skill.

---

## `/session-end`

**Purpose.** End the session cleanly: write a structured handoff, log progress, and optionally
refresh the TOC and commit state files (the "clean restart path").

**When to use.** At a meaningful stopping point or before you end work — so the next session
can resume from disk, not from chat memory.

**What it does (in order).**

1. Identifies the active feature (asks if none).
2. Runs `init.sh` to capture ground-truth build/test state.
3. **Overwrites** `session-handoff.md` (timestamp, active feature, what's in flight,
   build/test/lint state, the ONE next action, risks; ≤ 300 words).
4. **Prepends** a dated entry to `progress.md` (append-only history) — via
   `progress-prepend.mjs`, which inserts after the header without loading the whole file.
5. Updates `feature_list.json` status if warranted (`pass` only with evidence; else
   `blocked` / stays `in-progress`), keeps it **actionable-first** via `feature-list-sort.mjs`,
   then **validates feature `id` uniqueness** via `feature-list-validate.mjs` (resolve any
   duplicate before committing).
6. **Flywheel reflection** — asks whether anything recurred this session worth capturing as a
   golden rule / convention (the `capturing-golden-rules` skill); usually nothing, a few-seconds reflex.
7. Offers a `PROJECT-TOC.md` refresh if structure changed.
8. **Surfaces any uncommitted source** (full `git status`, not just state files) with a HEAD-buildability caveat — a `pass` whose source isn't committed leaves the committed HEAD unbuildable — then offers to commit **state files only** (`chore(harness): session N handoff — <feature id>`); it still never auto-commits your source.

**Arguments.** None.

**Prerequisites.** An anchored project (suggests `/anchor` if `feature_list.json` is missing).

**Writes / side effects.** Writes the state files above. The verification-before-handoff order
means the handoff reflects reality, not optimism. Commits **only** state files, only if you
say yes — never your source changes.

**How it surfaces.** The Stop hook nudges it when `progress.md` looks un-updated this session
or `session-handoff.md` is > 24 h old.

**Refuses when.** You ask to mark `pass` but evidence is incomplete — it refuses and names the
missing evidence (Default-FAIL contract).

**Related.** `/status` (read-only snapshot) · `/index-project` (the TOC refresh it offers) ·
`feature-state-keeper` skill.

---

## How commands get recommended (discoverability)

Because commands never fire on their own, harness-anchor surfaces them at the right moment
through two channels:

| Channel | Timing | Recommends |
|---|---|---|
| **SessionStart** banner | Session start, on missing artifacts | `/anchor` (no state), `/cpp-init` (C/C++, no clang config), `/index-project` (TOC absent/stale) |
| **PostToolUse** hook | After an `Edit`/`Write` | `/verify` (edited a passed feature's files), `/sanitize` (C/C++ source change) |
| **Stop** hook | When the agent wraps up | `/session-end` (stale progress / handoff) |
| **`using-harness-anchor`** meta-skill | Injected every session (model-facing) | All commands, each with a *when-to-recommend* trigger — including `/status` and `/gc`, which have no hook nudge by design |

Hooks are **warn-only**: they inject a suggestion, never block and never run the command for
you.

---

## See also

- [`README.md`](../README.md) — install, quick start, the command/hook/skill tables.
- [`docs/troubleshooting.md`](troubleshooting.md) — when a hook or command misbehaves.
- [`CHANGELOG.md`](../CHANGELOG.md) — what changed in each release.
- The canonical source for each command is its own file under
  [`commands/`](../commands/) — this manual is derived from those and should match them.
