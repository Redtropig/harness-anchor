# harness-anchor

> **Runtime constraint layer for Claude Code agents.** Companion to [`superpowers`](https://github.com/obra/superpowers). Anchors your agent to project state, scope boundaries, evidence-based completion, test-coverage design, entropy governance (golden rules + drift scan), C/C++ engineering best practices, and a strict docs-lookup discipline.

---

## What it is

`superpowers` gives your agent **process methodology** (brainstorm → plan → TDD → review).

`harness-anchor` gives your agent **environment & state discipline** (where am I, what's the active feature, what counts as "done", which files exist, what to do when stuck on an unfamiliar tool).

Together they form a complete harness based on Anthropic's [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) and the [learn-harness-engineering](https://walkinglabs.github.io/learn-harness-engineering/) 5-subsystem model:

| Subsystem | Provided by |
|---|---|
| Instructions | superpowers + harness-anchor (`using-harness-anchor`) |
| State | **harness-anchor** (`feature_list.json`, `progress.md`, `session-handoff.md`, `golden-rules.md`; cold history: `progress-archive.md` / `feature_archive.json`) |
| Verification | **harness-anchor** (`anti-hallucination-gates`, `/verify`) + superpowers (TDD) |
| Scope | **harness-anchor** (active-feature lock, scope-jump detection) |
| Lifecycle | **harness-anchor** (`init.sh`, `/session-end`) |

---

## Installation (local dev marketplace)

```bash
# 1. Register the marketplace (from the published GitHub repo)
claude /plugin marketplace add Redtropig/harness-anchor

# 2. Install
claude /plugin install harness-anchor@harness-anchor-local

# 3. Start a session; SessionStart hook injects harness-anchor banner
claude
```

You should see a `<harness-anchor-state>...</harness-anchor-state>` block in the agent's awareness on session start.

---

## Quick start in a new project

```bash
# In your project root:
/anchor          # scaffolds AGENTS.md, feature_list.json, init.sh, progress.md,
                 # session-handoff.md, PROJECT-TOC.md, context-budget.md, golden-rules.md
/cpp-init        # (C/C++ projects only) tunes init.sh, drops .clang-format,
                 # .clang-tidy, scripts/lint.sh, scripts/sanitizer-build.sh
/index-project   # builds PROJECT-TOC.md from your git-tracked files
bash init.sh     # health-check the environment

# Then work normally; on session end:
/session-end     # writes structured handoff, appends progress.md, offers archival + commit
```

---

## Skills (14 total — auto-triggered from session context)

| Skill | When it fires |
|---|---|
| `using-harness-anchor` | Auto-loaded at every session start (meta-skill) |
| `project-indexing` | Locating files; consults `PROJECT-TOC.md` before Glob |
| `feature-state-keeper` | Starting/advancing/finishing/blocking a feature |
| `init-verification` | Start of work; after env change; when something stops working |
| `self-correction-loop` | After tool/hook returns warning, lint/type/build error |
| `anti-hallucination-gates` | Before claiming "done", "fixed", "passing" |
| `test-coverage-design` | Deciding what to test; is a feature covered before "done" (dispatches `coverage-analyst`) |
| `capturing-golden-rules` | The same mistake recurs / a review comment is really a convention — encode it as a durable rule (the feedback flywheel) |
| `context-budget-discipline` | Long sessions; subagents; large file fetches |
| `docs-lookup` | Looking up unfamiliar tools/APIs/errors (Context7 → WebSearch → uncertainty) |
| `cpp-build-systems` | CMake/Meson/Make/Bazel projects |
| `cpp-static-analysis` | clang-tidy / cppcheck / IWYU |
| `cpp-formatting` | clang-format |
| `cpp-sanitizers` | ASan / UBSan / TSan / valgrind |

## Subagents (5 — invoked via `Task` tool or slash commands)

| Agent | Role |
|---|---|
| `verification-runner` | Fresh-context evaluator — runs build/tests/lint, reports evidence paths. Read-only. |
| `coverage-analyst` | Fresh-context coverage-gap analyst — derives test obligations from code + spec, flags paths outside the run scope, recommends oracle-independent-first tests. Read-only. |
| `drift-analyst` | Fresh-context drift / entropy scanner — checks changed code against `golden-rules.md` + slop heuristics (dead code, duplication, doc-drift), reports findings with an evidence path. Read-only. |
| `cpp-build-doctor` | Diagnoses C/C++ build failures from compiler output. Read-only. |
| `index-curator` | Sole writer of `PROJECT-TOC.md`. Used by `/index-project`. |

## Slash commands

| Command | What it does |
|---|---|
| `/anchor` | Scaffolds harness state files into the current project (overwrites only with explicit approval) |
| `/cpp-init` | C/C++ project: tunes `init.sh`, drops `.clang-format` / `.clang-tidy` / `lint.sh` / `sanitizer-build.sh` |
| `/index-project` | (Re)builds `PROJECT-TOC.md` from git-tracked sources |
| `/verify` | Dispatches `verification-runner` for fresh-context evaluation; opt-in `--fix` runs a bounded (≤ 2-cycle) auto-fix loop |
| `/test-plan` | Dispatches `coverage-analyst` for a post-impl coverage-gap analysis (obligations, paths outside the run scope, minimal oracle-independent-first tests); read-only |
| `/gc` | Dispatches `drift-analyst` for an on-demand code-drift / entropy scan against `golden-rules.md` + slop heuristics (dead code, duplication, doc-drift); read-only, report-only (not `git gc`) |
| `/sanitize` | C/C++ project: builds under ASan+UBSan (TSan separately), runs tests, reports findings in fixed sections with a `.harness-anchor/sanitize-*.log` evidence path |
| `/session-end` | Writes structured handoff + appends `progress.md` + offers over-budget archival (state-archive.mjs) + commit |
| `/status` | Read-only project overview: active feature, counts, git tree, TOC freshness, handoff head |

📖 **Full command reference:** [docs/commands.md](docs/commands.md) — when to reach for each command, its arguments, prerequisites, outputs, and how the harness recommends it.

## Hooks (4 — all warn-only, never block)

| Hook | Purpose |
|---|---|
| SessionStart | Injects state banner: active feature, project type, platform (HA_OS taxonomy), TOC freshness, golden-rules count, state-file budget sentinel, handoff head, slimmed meta-skill body — frontmatter stripped; cpp-only sections injected only in C/C++ projects; os-<name> sections only on that platform (≤ 3000 token budget); compact-source caution line (post-compaction recall is unreliable — rebuild from on-disk evidence), enriched with last-compaction forensics (trigger, branch, dirty count, handoff age) when a fresh pre-compact marker exists |
| PostToolUse | **All tools** (v0.15.0 pulse fast lane): duplicate-call nudge (3× identical input), error-streak nudge (3× same-tool failures), **two-stage context watermark** (flush reminder → fresh-session advice; per-stage once, any tool — not just edits), periodic **feature checkpoint** quoting `out_of_scope`; one nudge max per call + cooldown. On Edit/Write additionally: regression-warn on pass-feature files; duplicate feature-`id` warn when `feature_list.json` is written; **new-code-module scope-creep warn** when a new module is written while a feature is in-progress (action-side companion to the prompt-side scope-jump check); clang-tidy on C/C++ files when `compile_commands.json` present (sysroot-aware on macOS; failed-parse diagnostics suppressed with one honest notice); one-line `/sanitize` nudge on C/C++ edits (never runs sanitizers inline) |
| PreCompact | Writes `.harness-anchor/last-compact.meta` forensics (trigger, transcript size, branch, dirty count, handoff age) for the post-compaction notice; one user-facing `systemMessage` when the handoff is stale/absent. No agent-reaching channel exists at this event — never blocks |
| Stop | Nudges progress.md update, session-handoff refresh, and flushing chat-only durable memory; never blocks |
| UserPromptSubmit | Detects scope-jump phrases ("also", "by the way"); surfaces active feature for confirmation |

---

## Key design decisions

- **Warn-only hooks.** PostToolUse / Stop / UserPromptSubmit / PreCompact hooks **never block** — they inject `additionalContext` for self-correction per Anthropic's "feedback loops > gates" guidance.
- **Default-FAIL contracts.** Done criteria start `false`; the agent must produce a concrete evidence path (build log, test output, lint report) to flip them to `true`. See `skills/anti-hallucination-gates/`.
- **Progressive Disclosure.** SessionStart injects ≤ 3000 tokens (banner + an adaptive `PROJECT-TOC` view — the directory map, or the full file list on a small repo — + the meta-skill, injected slimmed: frontmatter stripped; cpp-only sections gated by cpp-detect; os-<name> sections gated by the runtime platform, HA_OS). Deeper references live in skill subfolders — including per-platform `platform/<os>.md` sidecars — loaded on demand.
- **docs-lookup is canonical.** No inline Context7 → WebSearch waterfalls in other skills — they all reference `docs-lookup` for the procedure (including failure-mode detection and calibrated-uncertainty fallback).
- **Fresh-context evaluator.** `/verify` dispatches `verification-runner` in a subagent with read-only tools; mitigates "self-grading" leniency per Anthropic's March 2026 three-agent architecture.
- **Test coverage is post-implementation.** `/test-plan` + `coverage-analyst` derive what *must* be tested from code + spec and flag paths outside the runner's scope — the code-aware pass superpowers' (deliberately code-blind) TDD can't do; pre-implementation test-first stays TDD's job. Reliability against correlated LLM blind spots (code and tests both LLM-generated) leans on oracle-independent tests (metamorphic / differential / property) + a risk-construct checklist, not the model's judgement.
- **Entropy governance is a feedback flywheel — report-only.** Recurring mistakes become checkable rules in `golden-rules.md` (the `capturing-golden-rules` skill); `/gc` dispatches a fresh-context `drift-analyst` that scans *changed* code against those rules + generic slop heuristics (dead code, duplication, doc-drift) and **recommends** — it never auto-refactors. Capture is **write-at-realization** — the rule lands the turn the signal appears; `/session-end`'s flywheel is the safety net, not a new ceremony (Garg's Feedback Flywheel; the solo-appropriate, lightweight form per the harness-engineering practical guide).
- **Durable memory flushes at realization, not session end.** Lessons, decisions, and milestones are written to disk in the turn they're recognized — rough golden-rule stubs are legitimate (origin quotes the evidence at hand; Check starts `manual review`). Four warn-only sentinels back the contract at the danger moments: context filling (PostToolUse two-stage watermark — per-stage once, any tool), compaction imminent (PreCompact forensics marker + user notice), just-compacted (SessionStart caution line, forensics-enriched), stopping (Stop nudge).
- **State files carry budgets and a checkpoint archival ritual.** Hot files stay bounded on
  long-lived projects (`progress.md` keeps the newest ~20 sessions; `feature_list.json` keeps
  live features + the 10 most recent `pass` entries); `/session-end` offers moving the excess
  verbatim — evidence intact — to git-tracked archives via `scripts/state-archive.mjs`
  (deterministic, idempotent, crash-convergent, aborts on malformed JSON rather than
  "repairing" the ledger). The SessionStart banner warns (warn-only) when a budget is
  exceeded. History is moved, never deleted; archives are grep-only reference.
- **Heavy ops are explicit commands, not auto-fired hooks.** Sanitizer builds (`/sanitize`) and the opt-in auto-fix loop (`/verify --fix`, bounded to ≤ 2 fresh-evaluated cycles) far exceed the ≤ 5s warn-only hook budget — a hook may *suggest* `/sanitize`, but never runs it inline.
- **Mechanical halves are scripts.** `/status`, `/anchor`, `/cpp-init`, `/session-end` and the golden-rules Check tier run deterministic `scripts/*` helpers (single source of truth, unit-tested, byte-stable output); the command markdown keeps only judgment + interaction. Cheaper per invocation, and "never silently overwrite" is enforced as interface shape — `scaffold.sh`'s default path has no overwrite branch at all.
- **C/C++ first-class.** Build system auto-detect (CMake/Meson/Make/Bazel), `compile_commands.json`-aware clang-tidy, sanitizer build templates.

---

## Companion plugins

| Plugin | Role | Required? |
|---|---|---|
| [`superpowers`](https://github.com/obra/superpowers) | Process methodology | Recommended |
| `context7` / first-party docs MCP (e.g. Microsoft Learn) | Library & ecosystem docs lookup | Optional (`docs-lookup` prefers first-party when relevant, else WebSearch) |

`harness-anchor` is **zero-dependency at runtime** (bash + git; Node.js for the `scripts/*.mjs` index/state tools). Hooks parse JSON through an engine chain — python3 → python → py -3 → node → a narrow pure-bash tier — so any ONE of those (or none, with honest degradation) is enough.

---

## Windows

Supported under the **Git-Bash baseline**: Git for Windows (which Claude Code on
Windows already requires) provides the bash + GNU coreutils the hooks run on;
`hooks/run-hook.cmd` dispatches hook events to it automatically (WSL bash is
deliberately excluded — hooks must see Windows paths).

| You have | Hook fidelity |
|---|---|
| python3 / python / py, or node | Full — all checks incl. feature-ledger parsing |
| none of the above | Degraded but honest: banner + project typing + version still real (plugin-controlled formats parse in pure bash); ledger-derived checks skip and the banner shows `(needs python3 or node)` |

Windows-specific behaviors handled for you: LF checkout is forced for all bash
files via `.gitattributes`; `System32`'s incompatible `find`/`sort`/`timeout` are
shielded by a PATH prepend inside each hook; `C:\` paths are normalized at hook
entry. C/C++ notes: TSan/LSan don't exist on Windows — see the `cpp-sanitizers`
skill's `platform/windows.md` sidecar for the substitute-tool table (WSL2, Intel
Inspector, Dr. Memory, CRT debug heap, `/RTC1`).

## Verifying installation

```bash
bash scripts/validate-anchor.sh        # self-consistency checks (count printed on run)
bash scripts/validate-manifests.sh     # manifest validation (name, version, sync)
bash tests/hook-contracts/post-tool-use-warn.sh  # PostToolUse hook contract
bash scripts/cpp-detect.sh --target tests/cpp-detection/cmake-fixture
                                       # cpp-detect on a known fixture
bash scripts/measure-context.sh        # SessionStart context budget vs 12000-char cap (cpp + generic fixtures)
```

CI runs all of these on push/PR (ubuntu + macos) — see `.github/workflows/validate.yml`.

Troubleshooting? See [docs/troubleshooting.md](docs/troubleshooting.md).

---

## License

MIT — see [LICENSE](LICENSE).

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history.
