# harness-anchor

> **Runtime constraint layer for Claude Code agents.** Companion to [`superpowers`](https://github.com/obra/superpowers). Anchors your agent to project state, scope boundaries, evidence-based completion, and C/C++ engineering best practices.

---

## What it is

`superpowers` gives your agent **process methodology** (brainstorm → plan → TDD → review).

`harness-anchor` gives your agent **environment & state discipline** (where am I, what's the active feature, what counts as "done", which files exist).

Together they form a complete harness based on Anthropic's [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) and the [learn-harness-engineering](https://walkinglabs.github.io/learn-harness-engineering/) 5-subsystem model:

| Subsystem | Provided by |
|---|---|
| Instructions | superpowers + harness-anchor (`using-harness-anchor`) |
| State | **harness-anchor** (`feature_list.json`, `progress.md`, `session-handoff.md`) |
| Verification | **harness-anchor** (`anti-hallucination-gates`, `/verify`) + superpowers (TDD) |
| Scope | **harness-anchor** (active-feature lock, scope-jump detection) |
| Lifecycle | **harness-anchor** (`init.sh`, `/session-end`) |

---

## Status

**Phase 1 — Skeleton.** Only `using-harness-anchor` meta-skill is wired. Subsequent phases add state/scope/verification/cpp layers. See [plan](../../../.claude/plans/users-redtropig-desktop-users-redtropig-concurrent-truffle.md).

---

## Installation (local dev)

```bash
# 1. Register the local dev marketplace
claude /plugin marketplace add /Users/redtropig/Desktop/harness-anchor

# 2. Install
claude /plugin install harness-anchor@harness-anchor-local

# 3. Start a session; SessionStart hook injects harness-anchor banner
claude
```

You should see `<harness-anchor>...</harness-anchor>` context block in the agent's awareness on session start.

---

## Quick concepts

- **Warn-only hooks.** PostToolUse / Stop / UserPromptSubmit hooks **never block** — they inject feedback into the next context per Anthropic's "feedback loops > gates" guidance.
- **Default-FAIL contracts.** Done criteria start `false`; the agent must produce a concrete evidence path (build log, test output, lint report) to flip them to `true`. See `skills/anti-hallucination-gates/`.
- **Progressive Disclosure.** SessionStart injects ≤2000 tokens. Deeper references live in skill subfolders, loaded on demand.
- **C/C++ first-class.** Build system auto-detect (CMake/Meson/Make/Bazel), `compile_commands.json`-aware clang-tidy, sanitizer build templates.

---

## Companion plugins

| Plugin | Role | Required? |
|---|---|---|
| [`superpowers`](https://github.com/obra/superpowers) | Process methodology | Recommended |
| `context7` MCP | Library docs lookup | Optional (skills will fall back to WebSearch) |

`harness-anchor` is **zero-dependency** (bash + git only at runtime; Node.js used only for `index-builder.mjs`).

---

## License

MIT — see [LICENSE](LICENSE).
