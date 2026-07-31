# harness-anchor — Contributor & AI Collaborator Guidelines

## If You Are an AI Agent Editing This Plugin

Stop. Read this before doing anything.

`harness-anchor` is **behaviour-shaping infrastructure** — its skills and hooks govern how OTHER agents behave in OTHER repositories. Edits here have outsized impact. A poorly tuned SKILL.md description will fail to trigger in real sessions; a too-fat SessionStart injection wastes context budget on every conversation; an over-eager PostToolUse hook blocks productive work.

**Your job is to protect the user from your own enthusiasm.** Do not:

1. Add features that aren't in the maintainer's approved plan (kept locally under `~/.claude/plans/`)
2. Rewrite skill descriptions to "comply with Anthropic best practices" without evals proving improvement
3. Add MCP server dependencies — this plugin is zero-dependency by design (bash + git)
4. Add `block` behavior to hooks — the entire design is warn-only (see plan §"决策")
5. Bundle changes to unrelated layers in one commit

## Design Invariants (do not break)

1. **Warn-only hooks.** No PostToolUse / Stop / UserPromptSubmit hook may produce JSON with `"permissionDecision": "deny"` or `"stopReason"`. PostToolUse / UserPromptSubmit / SessionStart surface `additionalContext` for self-correction; the **Stop** event has no `additionalContext` channel, so its reminder uses `systemMessage` (still non-blocking — never `decision: "block"`). **PreCompact** likewise reaches only the user (a marker file + `systemMessage`) — the agent gets no turn before compaction runs, so the actionable pre-compaction warning lives in the PostToolUse watermark stages.
2. **SessionStart token budget ≤ 3000 tokens.** Roughly 12000 chars of injected content. Hard-truncate with a pointer to the on-disk file. The meta-skill body is injected *slimmed* (frontmatter stripped; conditional regions dropped when their gate doesn't match — `cpp-only` by project type, `os-<name>` by HA_OS platform) — headroom belongs to the project-specific TOC/handoff, not to a fatter generic body.
3. **Subagents are single-level.** Every subagent prompt must end with: *"Do not invoke other subagents from this one."*
4. **State files are git-tracked by default.** `.harness-anchor/` (error log dir) is the only gitignored runtime path.
5. **C/C++ components stay dormant in non-C/C++ projects — through two different
   gates, and only one of them is `cpp-detect.sh`.** That script is the mechanical
   gate: it sets the banner's project type, decides whether the meta-skill's
   `cpp-only` regions are injected at all, and makes `/cpp-init` (exit 3) and
   `/sanitize` refuse outright. It does **not** gate skill loading — skills are
   selected by description matching, and nothing consults `cpp-detect.sh` at the
   moment one loads. So the gate on the skills is their own frontmatter: every
   `skills/cpp-*` description must scope itself to C/C++ within its first 80
   characters, the window invariant #6 says carries the load. That string is the
   only thing between a clang-tidy skill and a Python repo. Enforced by
   `validate-anchor` [3-4/12].

   The earlier wording of this invariant ("must include a frontmatter trigger
   condition referencing the detected build system") described neither what the
   files do — three of the four name no build system, and clang-format has no
   reason to — nor what actually gates them, and nothing enforced it. An
   unenforced entry in this list contradicts what the section below promises about
   it.
6. **Skill descriptions front-load distinctive trigger keywords.** First ~80 chars
   carry the load — Anthropic's skill listing budget is tight (see learn-harness
   `gotchas.md#12`). **Enforced by eval, not by grep.** Every skill ships an
   adversarial prompt that never names it (§"Authoring a New Skill" #4);
   `tests/skill-triggering/check-coverage.sh` guards that coverage structurally on
   every CI run, and `run-all.sh` puts the prompts through a live session before a
   release. Do not "close the gap" by adding a static text check: whether a keyword
   is distinctive is a property of *whether the skill fires*, not of the string, so
   any grep approximating it would pass descriptions the eval rejects and fail ones
   it accepts. Reading the absence of a grep as an absence of enforcement is a
   mistake that has already been made once against this entry.
7. **Hooks must time out in ≤ 5 seconds** and fail silent on missing tools.
8. **Default-FAIL evaluation contracts, both directions.** No skill or agent should
   mark anything "done" without an evidence path — **and** none should assert that
   something is **absent** (not installed / not available / no such symbol) without
   stating the search scope it actually covered and when it looked. A scope-less
   negative is wrong about *where* someone looked; a date-less one is wrong about
   *when*. This is the anti-hallucination invariant — do not soften it.
   Judgement-shaped negatives ("this is impossible", "that won't work") are
   deliberately **out of scope**: they carry no evidence path, and admitting them
   would turn the contract into unverifiable moralising.
9. **docs-lookup is the canonical procedure** for unfamiliar tools/APIs/errors/library behavior. New skills MUST reference it rather than inlining Context7 → WebSearch waterfalls — the failure-mode detection and calibrated-uncertainty fallback live in one place by design.
10. **Windows/Git-Bash is a supported surface.** `tests/windows-compat.sh` must pass:
    no direct `python3` invocation in hooks (JSON goes through `scripts/lib/portable.sh`'s
    engine chain: python3 → python → py -3 → node → narrow bash); externally supplied
    paths are normalized at hook entry (`ha_normalize_path`); walk-up loops terminate
    by fixed point (`ha_find_project_root`), never by comparing against `"/"`; bash-consumed
    files carry `eol=lf` gitattributes (`run-hook.cmd` deliberately excluded — polyglot).

## Shell hazards no tool in this repo catches

These are conventions, deliberately **not** invariants: the list above is mechanically
enforced by a test, and these cannot be. Putting an unenforceable rule in that list
would imply a check that does not exist.

1. **Under `set -u`, a bare `local x` is UNSET, not empty.** Reading it —
   `[ -n "$x" ]`, `"$x"`, `${x}` — aborts the script with `x: unbound variable`.
   Initialise every `local` you might read before assigning: `local x=""`. The
   dangerous shape is narrow and easy to miss: a name whose assignments all sit
   inside a loop or `if`, read after that block. It fires only on the path where
   the block never runs — the least-exercised branch, which is usually the
   not-found / empty / error path.

   Shipped instance: `scripts/cpp-tool-discovery.sh`'s versioned-variant search
   aborted on its true-`NOT_FOUND` path, i.e. the path the script exists to
   report correctly.

   **Neither grep nor shellcheck finds this** — both were tried against the real
   instance. Deciding it needs to know whether an assignment happens on *every*
   path, which line order does not tell you: a line-order scanner reports clean on
   code that crashes. ShellCheck at `--severity=style` emitted SC2034 and SC2043
   for that function and nothing about the unbound read. **The only detector is
   executing the path**, so the real mitigation is a test that covers the
   not-found / empty case — which is what caught this one.

## Authoring a New Skill (when explicitly asked)

1. Decide if it's generic (language-agnostic) or C/C++ specific. The frontmatter description must make this clear.
2. SKILL.md keeps the main flow in ≤200 lines. Heavy reference → sibling `.md` files. Platform-specific content splits by decision weight: facts an agent needs to *judge* correctly (availability, verdict rules) stay inline; operational depth (substitute tools, commands, workarounds) goes to `platform/<os>.md` (os ∈ the HA_OS taxonomy) behind an inline "On <OS>, read …" pointer using a same-skill relative path (cross-skill mentions name the skill, never a path). Don't create a platform file for <10 lines of pure decision facts.
3. Frontmatter description: ≤500 chars, front-load with "Use when X" trigger.
4. Add at least one adversarial prompt under `tests/skill-triggering/prompts/` proving the skill triggers on a naive user message that *doesn't* mention the skill name.
5. Update `scripts/validate-anchor.sh` checklist if needed.

## Authoring a New Hook (very rarely)

Hooks are the **most dangerous** component because they fire automatically. Before adding one:

1. State why this can't be a skill instead.
2. Provide a concrete failure mode being prevented.
3. Implement timeout, silent fail, and bounded output.
4. Add a contract test under `tests/hook-contracts/`.
5. **State the observation-point.** Name the failure's *manifestation surface* (Y — where the bad outcome actually appears) and the *signal the hook observes* (X). Assert **X ⊇ Y**; where it can't, **document the residual blind spot** in the hook header so a silent warn-only pass is not mistaken for coverage. A guardrail keyed on a proxy narrower than its target failure is silently blind — e.g. a scope check reading only the prompt misses agent-initiated scope creep (issue #6).

## Authoring a Subagent

- frontmatter: `tools: Read, Bash, Grep, Glob` is the read-only default. Add `Write/Edit` only with explicit justification.
- Last paragraph of system prompt MUST contain: *"Do not invoke other subagents from this one."*
- Output a fixed structure (e.g., diagnosis / evidence / recommendation) so the calling agent can parse reliably.

## Versioning

Bump `version` in `.claude-plugin/plugin.json` AND `.claude-plugin/marketplace.json` together. Semver: PATCH for fixes / content tweaks to existing components; MINOR for **any new backward-compatible capability** — new skill/agent/command/template/hook check, anything that belongs in a CHANGELOG `### Added` section; MAJOR for breaking hook contract. (The old "new skill/agent/command" wording was an incomplete enumeration and once caused an Added-bearing release to be mislabeled PATCH.)

## Tests

Before any commit that touches skills/hooks:

```bash
bash scripts/validate-anchor.sh
# Phase 5+: bash tests/skill-triggering/run-test.sh <skill> <prompt-file>
```

If validate-anchor fails, fix the failure or revert. Do not commit broken plugin metadata.
