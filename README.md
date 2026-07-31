# harness-anchor

[![validate](https://github.com/Redtropig/harness-anchor/actions/workflows/validate.yml/badge.svg)](https://github.com/Redtropig/harness-anchor/actions/workflows/validate.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**A warn-only runtime layer for Claude Code agents.**
[`superpowers`](https://github.com/obra/superpowers) gives an agent *process*
(brainstorm → plan → TDD → review). `harness-anchor` gives it *environment and
state discipline*: where am I, what is the active feature, what counts as
"done", and what to do when stuck.

It never blocks a tool call. It keeps state on disk, injects it back at session
start, and makes the agent show its evidence before it claims anything.

## What the agent sees

Every session opens with this — real output, from an anchored project:

```
<harness-anchor-state>
Plugin:           harness-anchor v0.17.1
Project root:     /home/you/invoice-service
Active feature:   feat-3: PDF export pipeline
Project type:     generic
Platform:         linux
TOC freshness:    fresh (b4a7c3273f214f7cbc6b7be63317c2500ac8eec1)
Golden rules:     3 rule(s) — /gc scans changed code against them
Last session handoff (first 10 lines):
# Session Handoff
Last updated: 2026-07-30
Active feature: feat-3
Next action: wire the renderer into the CLI, then run scripts/lint.sh
</harness-anchor-state>
```

## The failure modes it's built around

**"Done." — with nothing run.** Every criterion starts false. A feature cannot
reach `status: pass` while its `evidence` is `null`, and `feature_list.schema.json`
rejects that combination — the gate is a schema, not a good intention. Evidence
means a path you can open: a build log, test output, a lint report.

**"That's not installed." — after checking one place.** The same contract runs
in reverse. Asserting absence requires the scope searched and the date checked —
`searched PATH + VS-bundled LLVM, not found (as of 2026-07-31)`. An empty
`command -v` proves nothing: VS-bundled LLVM needs `vcvars`, and Homebrew's is
keg-only.

**State that lived in the chat, and a compaction ate it.** Feature status,
progress and handoff live in files, not scrollback. Four warn-only sentinels
fire at the danger moments: context filling, compaction imminent,
just-compacted, session stopping.

**The change that quietly grew.** One active feature at a time. Scope jumps are
caught on the prompt side ("also, could you…") *and* on the action side — a new
module written while a feature is still in progress.

## What it deliberately does not do

- **Never blocks.** No hook returns `deny` or `block`. They inject context the
  agent can correct itself with — feedback loops, not gates.
- **Never auto-refactors.** `/gc` reports drift and stops there.
- **Never installs anything.** bash + git. JSON parsing walks a
  python3 → python → py -3 → node → pure-bash chain, and degrades honestly when
  none of them exist.
- **Never floods your context.** SessionStart injects ≤3000 tokens — banner,
  project index, meta-skill; C/C++ and per-OS sections are dropped when they
  don't apply, and depth loads on demand.

## Install

```bash
claude /plugin marketplace add Redtropig/harness-anchor
claude /plugin install harness-anchor@harness-anchor-local
```

Start a session; the banner above should appear in the agent's context.
(`harness-anchor-local` is the marketplace id, not a dev build.)

## Quick start

```bash
/anchor          # scaffold the state files
/index-project   # build PROJECT-TOC.md from git-tracked files
bash init.sh     # health-check the environment
# ...work...
/session-end     # write handoff, append progress.md, offer archival + commit
```

## Commands

| Command | What it does |
|---|---|
| `/anchor` | Scaffold the state files (never overwrites without explicit approval) |
| `/index-project` | (Re)build `PROJECT-TOC.md` from git-tracked sources |
| `/status` | Read-only snapshot: active feature, counts, git tree, TOC freshness, handoff head |
| `/verify` | Fresh-context subagent runs build + lint + tests, reports evidence paths (`--fix` = bounded ≤2-cycle auto-fix) |
| `/test-plan` | Fresh-context coverage-gap analysis: obligations from code + spec, plus paths outside the runner's scope |
| `/gc` | Fresh-context drift scan against `golden-rules.md` + slop heuristics. Report-only (not `git gc`) |
| `/session-end` | Write handoff, append `progress.md`, offer archival + commit |
| `/cpp-init` | C/C++: tune `init.sh`, drop `.clang-format` / `.clang-tidy` / `lint.sh` / `sanitizer-build.sh` |
| `/sanitize` | C/C++: build under ASan+UBSan, run tests, report with a log evidence path |

Full manual — arguments, prerequisites, outputs: [docs/commands.md](docs/commands.md).

## Skills (14, auto-triggered — you never invoke these)

- **State & navigation** — `project-indexing`, `feature-state-keeper`, `init-verification`
- **Evidence & verification** — `anti-hallucination-gates`, `self-correction-loop`, `test-coverage-design`
- **Governance & context** — `capturing-golden-rules`, `context-budget-discipline`, `docs-lookup`
- **C/C++** — `cpp-build-systems`, `cpp-static-analysis`, `cpp-formatting`, `cpp-sanitizers`
- **Meta** — `using-harness-anchor`, injected at every session start

## Subagents (5)

`verification-runner` (`/verify`), `coverage-analyst` (`/test-plan`) and
`drift-analyst` (`/gc`) are fresh-context evaluators — separating who writes the
code from who grades it is what keeps the grade honest. `coverage-analyst` is
the code-aware pass TDD deliberately cannot do: it derives test obligations from
the code as written, and flags paths the test runner never reaches.
`cpp-build-doctor` diagnoses build failures from compiler output.

Those four are read-only by frontmatter, not by convention — an evaluator that
can edit what it grades has an incentive to make the finding go away.
`index-curator` is the one that can write, and only to `PROJECT-TOC.md`.

## Hooks (5, all warn-only)

| Event | What it does |
|---|---|
| `SessionStart` | Injects the state banner and a slimmed meta-skill (≤3000 tokens; C/C++ and per-OS sections dropped when they don't apply) |
| `PostToolUse` | Nudges on repeated identical calls, error streaks, context watermarks, scope creep and feature checkpoints; runs clang-tidy on C/C++ edits when `compile_commands.json` exists. One nudge per call, with a cooldown |
| `UserPromptSubmit` | Flags scope-jump phrasing, surfaces the active feature for confirmation |
| `PreCompact` | Records compaction forensics for the post-compaction notice |
| `Stop` | Nudges a `progress.md` update, a handoff refresh, and flushing chat-only memory |

Hooks fail silent on missing tools and are budgeted at ≤5s; SessionStart,
PostToolUse and PreCompact enforce that with an explicit watchdog — on timeout
they emit nothing and exit 0.

## Design notes

Grounded in Anthropic's [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
and the [learn-harness-engineering](https://walkinglabs.github.io/learn-harness-engineering/)
five-subsystem model: harness-anchor supplies State, Verification, Scope and
Lifecycle; superpowers supplies process.

[docs/design.md](docs/design.md) carries the full mapping and the reasoning
behind each choice — warn-only hooks, the two-directional evidence contract,
state budgets and archival, why heavy operations are commands rather than
hooks — with the alternative that was rejected in each case.

## C/C++ projects

The build system is auto-detected (CMake / Meson / Make / Bazel); nothing to
configure. `/cpp-init` drops `.clang-format`, `.clang-tidy`, `scripts/lint.sh`
and `scripts/sanitizer-build.sh`. PostToolUse runs clang-tidy on edited files
when `compile_commands.json` exists. `/sanitize` builds under ASan+UBSan and
runs the tests; `cpp-build-doctor` reads compiler output when a build breaks.

Sanitizer coverage is platform-bound, and the skill says so instead of assuming:
TSan and LSan do not exist on Windows — `skills/cpp-sanitizers/platform/windows.md`
carries the substitute table.

## Platforms

Linux, macOS and Windows; the self-tests run on all three in CI.

Windows runs on the **Git-Bash baseline** — Git for Windows, which Claude Code
already requires, supplies the bash and coreutils the hooks need, and
`hooks/run-hook.cmd` dispatches to it (WSL bash is deliberately excluded: hooks
must see Windows paths). LF checkout is pinned by `.gitattributes`, `System32`'s
incompatible `find` / `sort` / `timeout` are shielded by a PATH prepend, and
`C:\` paths are normalized at hook entry.

With no JSON engine at all, the banner, project typing and version stay real —
plugin-controlled formats parse in pure bash — while ledger-derived checks skip
and say so rather than reporting a false zero.

## Verifying the plugin

```bash
bash scripts/validate-anchor.sh      # plugin self-consistency
bash scripts/validate-manifests.sh   # manifest name/version sync
bash tests/windows-compat.sh         # static Windows invariants (runs anywhere)
bash scripts/measure-context.sh      # SessionStart injection vs the 12000-char cap
```

CI runs these on every push and PR across Linux, macOS and Windows — hook
contracts, unit tests, compatibility gates, and a ShellCheck gate that fails on
warning severity. Test scripts are discovered by glob, not from a hard-coded
list. (The Windows leg deliberately runs a curated core subset.)

Stuck? [docs/troubleshooting.md](docs/troubleshooting.md).

---

Works alongside [`superpowers`](https://github.com/obra/superpowers) (recommended,
not required) and any docs MCP — `docs-lookup` prefers first-party sources over
general search.

MIT — see [LICENSE](LICENSE). Release history: [CHANGELOG.md](CHANGELOG.md).
