# harness-anchor

> **Runtime constraint layer for Claude Code agents.** Companion to [`superpowers`](https://github.com/obra/superpowers). Anchors your agent to project state, scope boundaries, evidence-based completion, C/C++ engineering best practices, and a strict docs-lookup discipline.

---

## What it is

`superpowers` gives your agent **process methodology** (brainstorm → plan → TDD → review).

`harness-anchor` gives your agent **environment & state discipline** (where am I, what's the active feature, what counts as "done", which files exist, what to do when stuck on an unfamiliar tool).

Together they form a complete harness based on Anthropic's [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) and the [learn-harness-engineering](https://walkinglabs.github.io/learn-harness-engineering/) 5-subsystem model:

| Subsystem | Provided by |
|---|---|
| Instructions | superpowers + harness-anchor (`using-harness-anchor`) |
| State | **harness-anchor** (`feature_list.json`, `progress.md`, `session-handoff.md`) |
| Verification | **harness-anchor** (`anti-hallucination-gates`, `/verify`) + superpowers (TDD) |
| Scope | **harness-anchor** (active-feature lock, scope-jump detection) |
| Lifecycle | **harness-anchor** (`init.sh`, `/session-end`) |

---

## Installation (local dev marketplace)

```bash
# 1. Register the local dev marketplace
claude /plugin marketplace add /Users/redtropig/Desktop/harness-anchor

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
                 # session-handoff.md, PROJECT-TOC.md, context-budget.md
/cpp-init        # (C/C++ projects only) tunes init.sh, drops .clang-format,
                 # .clang-tidy, scripts/sanitizer-build.sh
/index-project   # builds PROJECT-TOC.md from your git-tracked files
bash init.sh     # health-check the environment

# Then work normally; on session end:
/session-end     # writes structured handoff, appends progress.md, suggests commit
```

---

## Skills (12 total — auto-triggered from session context)

| Skill | When it fires |
|---|---|
| `using-harness-anchor` | Auto-loaded at every session start (meta-skill) |
| `project-indexing` | Locating files; consults `PROJECT-TOC.md` before Glob |
| `feature-state-keeper` | Starting/advancing/finishing/blocking a feature |
| `init-verification` | Start of work; after env change; when something stops working |
| `self-correction-loop` | After tool/hook returns warning, lint/type/build error |
| `anti-hallucination-gates` | Before claiming "done", "fixed", "passing" |
| `context-budget-discipline` | Long sessions; subagents; large file fetches |
| `docs-lookup` | Looking up unfamiliar tools/APIs/errors (Context7 → WebSearch → uncertainty) |
| `cpp-build-systems` | CMake/Meson/Make/Bazel projects |
| `cpp-static-analysis` | clang-tidy / cppcheck / IWYU |
| `cpp-formatting` | clang-format |
| `cpp-sanitizers` | ASan / UBSan / TSan / valgrind |

## Subagents (3 — invoked via `Task` tool or slash commands)

| Agent | Role |
|---|---|
| `verification-runner` | Fresh-context evaluator — runs build/tests/lint, reports evidence paths. Read-only. |
| `cpp-build-doctor` | Diagnoses C/C++ build failures from compiler output. Read-only. |
| `index-curator` | Sole writer of `PROJECT-TOC.md`. Used by `/index-project`. |

## Slash commands

| Command | What it does |
|---|---|
| `/anchor` | Scaffolds harness state files into the current project (overwrites only with explicit approval) |
| `/cpp-init` | C/C++ project: tunes `init.sh`, drops `.clang-format` / `.clang-tidy` / `sanitizer-build.sh` |
| `/index-project` | (Re)builds `PROJECT-TOC.md` from git-tracked sources |
| `/verify` | Dispatches `verification-runner` for fresh-context evaluation; opt-in `--fix` runs a bounded (≤ 2-cycle) auto-fix loop |
| `/sanitize` | C/C++ project: builds under ASan+UBSan (TSan separately), runs tests, reports findings in fixed sections with a `.harness-anchor/sanitize-*.log` evidence path |
| `/session-end` | Writes structured handoff + appends `progress.md` + offers commit |
| `/status` | Read-only project overview: active feature, counts, git tree, TOC freshness, handoff head |

## Hooks (4 — all warn-only, never block)

| Hook | Purpose |
|---|---|
| SessionStart | Injects state banner: active feature, project type, TOC freshness, handoff head, meta-skill body (≤ 2000 token budget) |
| PostToolUse | After Edit/Write: regression-warn on pass-feature files; clang-tidy on C/C++ files when `compile_commands.json` present; one-line `/sanitize` nudge on C/C++ edits (never runs sanitizers inline) |
| Stop | Nudges progress.md update, session-handoff refresh; never blocks |
| UserPromptSubmit | Detects scope-jump phrases ("顺便", "also", "by the way"); surfaces active feature for confirmation |

---

## Key design decisions

- **Warn-only hooks.** PostToolUse / Stop / UserPromptSubmit hooks **never block** — they inject `additionalContext` for self-correction per Anthropic's "feedback loops > gates" guidance.
- **Default-FAIL contracts.** Done criteria start `false`; the agent must produce a concrete evidence path (build log, test output, lint report) to flip them to `true`. See `skills/anti-hallucination-gates/`.
- **Progressive Disclosure.** SessionStart injects ≤ 2000 tokens (banner + TOC head + meta-skill). Deeper references live in skill subfolders, loaded on demand.
- **docs-lookup is canonical.** No inline Context7 → WebSearch waterfalls in other skills — they all reference `docs-lookup` for the procedure (including failure-mode detection and calibrated-uncertainty fallback).
- **Fresh-context evaluator.** `/verify` dispatches `verification-runner` in a subagent with read-only tools; mitigates "self-grading" leniency per Anthropic's March 2026 three-agent architecture.
- **Heavy ops are explicit commands, not auto-fired hooks.** Sanitizer builds (`/sanitize`) and the opt-in auto-fix loop (`/verify --fix`, bounded to ≤ 2 fresh-evaluated cycles) far exceed the ≤ 5s warn-only hook budget — a hook may *suggest* `/sanitize`, but never runs it inline.
- **C/C++ first-class.** Build system auto-detect (CMake/Meson/Make/Bazel), `compile_commands.json`-aware clang-tidy, sanitizer build templates.

---

## Companion plugins

| Plugin | Role | Required? |
|---|---|---|
| [`superpowers`](https://github.com/obra/superpowers) | Process methodology | Recommended |
| `context7` MCP | Library docs lookup | Optional (docs-lookup skill falls back to WebSearch) |

`harness-anchor` is **zero-dependency at runtime** (bash + git; Node.js only for `scripts/index-builder.mjs`).

---

## Verifying installation

```bash
bash scripts/validate-anchor.sh        # self-consistency checks (count printed on run)
bash scripts/validate-manifests.sh     # manifest validation (name, version, sync)
bash tests/hook-contracts/post-tool-use-warn.sh  # PostToolUse hook contract
bash scripts/cpp-detect.sh --target tests/cpp-detection/cmake-fixture
                                       # cpp-detect on a known fixture
bash scripts/measure-context.sh        # SessionStart context budget vs 8000-char cap
```

CI runs all of these on push/PR (ubuntu + macos) — see `.github/workflows/validate.yml`.

Troubleshooting? See [docs/troubleshooting.md](docs/troubleshooting.md).

---

## License

MIT — see [LICENSE](LICENSE).

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history.

## v0.1.0 retrospective

See [docs/v0.1.0-plan-addendum.md](docs/v0.1.0-plan-addendum.md) for post-plan reality and lessons learned.
