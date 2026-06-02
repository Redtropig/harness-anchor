# harness-anchor — Contributor & AI Collaborator Guidelines

## If You Are an AI Agent Editing This Plugin

Stop. Read this before doing anything.

`harness-anchor` is **behaviour-shaping infrastructure** — its skills and hooks govern how OTHER agents behave in OTHER repositories. Edits here have outsized impact. A poorly tuned SKILL.md description will fail to trigger in real sessions; a too-fat SessionStart injection wastes context budget on every conversation; an over-eager PostToolUse hook blocks productive work.

**Your job is to protect the user from your own enthusiasm.** Do not:

1. Add features that aren't in the plan at `/Users/redtropig/.claude/plans/users-redtropig-desktop-users-redtropig-concurrent-truffle.md`
2. Rewrite skill descriptions to "comply with Anthropic best practices" without evals proving improvement
3. Add MCP server dependencies — this plugin is zero-dependency by design (bash + git)
4. Add `block` behavior to hooks — the entire design is warn-only (see plan §"决策")
5. Bundle changes to unrelated layers in one commit

## Design Invariants (do not break)

1. **Warn-only hooks.** No PostToolUse / Stop / UserPromptSubmit hook may produce JSON with `"permissionDecision": "deny"` or `"stopReason"`. PostToolUse / UserPromptSubmit / SessionStart surface `additionalContext` for self-correction; the **Stop** event has no `additionalContext` channel, so its reminder uses `systemMessage` (still non-blocking — never `decision: "block"`).
2. **SessionStart token budget ≤ 2000 tokens.** Roughly 8000 chars of injected content. Hard-truncate with a pointer to the on-disk file.
3. **Subagents are single-level.** Every subagent prompt must end with: *"Do not invoke other subagents from this one."*
4. **State files are git-tracked by default.** `.harness-anchor/` (error log dir) is the only gitignored runtime path.
5. **C/C++ skills are gated by `cpp-detect.sh`.** They must include a frontmatter trigger condition referencing the detected build system; they must not activate in non-C/C++ projects.
6. **Skill descriptions front-load distinctive trigger keywords.** First ~80 chars carry the load — Anthropic's skill listing budget is tight (see learn-harness `gotchas.md#12`).
7. **Hooks must time out in ≤ 5 seconds** and fail silent on missing tools.
8. **Default-FAIL evaluation contracts.** No skill or agent should mark anything "done" without an evidence path. This is the anti-hallucination invariant — do not soften it.
9. **docs-lookup is the canonical procedure** for unfamiliar tools/APIs/errors/library behavior. New skills MUST reference it rather than inlining Context7 → WebSearch waterfalls — the failure-mode detection and calibrated-uncertainty fallback live in one place by design.

## Authoring a New Skill (when explicitly asked)

1. Decide if it's generic (language-agnostic) or C/C++ specific. The frontmatter description must make this clear.
2. SKILL.md keeps the main flow in ≤200 lines. Heavy reference → sibling `.md` files.
3. Frontmatter description: ≤500 chars, front-load with "Use when X" trigger.
4. Add at least one adversarial prompt under `tests/skill-triggering/prompts/` proving the skill triggers on a naive user message that *doesn't* mention the skill name.
5. Update `scripts/validate-anchor.sh` checklist if needed.

## Authoring a New Hook (very rarely)

Hooks are the **most dangerous** component because they fire automatically. Before adding one:

1. State why this can't be a skill instead.
2. Provide a concrete failure mode being prevented.
3. Implement timeout, silent fail, and bounded output.
4. Add a contract test under `tests/hook-contracts/`.

## Authoring a Subagent

- frontmatter: `tools: Read, Bash, Grep, Glob` is the read-only default. Add `Write/Edit` only with explicit justification.
- Last paragraph of system prompt MUST contain: *"Do not invoke other subagents from this one."*
- Output a fixed structure (e.g., diagnosis / evidence / recommendation) so the calling agent can parse reliably.

## Versioning

Bump `version` in `.claude-plugin/plugin.json` AND `.claude-plugin/marketplace.json` together. Semver: PATCH for skill content tweaks, MINOR for new skill/agent/command, MAJOR for breaking hook contract.

## Tests

Before any commit that touches skills/hooks:

```bash
bash scripts/validate-anchor.sh
# Phase 5+: bash tests/skill-triggering/run-test.sh <skill> <prompt-file>
```

If validate-anchor fails, fix the failure or revert. Do not commit broken plugin metadata.
