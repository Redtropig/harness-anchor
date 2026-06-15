# Changelog

All notable changes to harness-anchor are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Test-coverage design capability** (targets a confident-wrong failure mode: a fixed-width-accumulator overflow that only fires on large inputs and ships because its only triggering binary is built but never `add_test`-registered, so the sanitizer never runs it and a false "clean" is claimed). Post-implementation, and complements superpowers' (deliberately code-blind) TDD — TDD owns the pre-impl, spec-driven test-first pass; this owns the code-aware post-impl pass.
  - `agents/coverage-analyst.md` (NEW, read-only, fresh-context) — derives test obligations from code + spec (gray-box), diffs them against the suite **and the verified run scope** (flags binaries the runner never executes), and recommends a minimal **oracle-independent-first** test set (metamorphic / differential / property: correctness comes from a relation, not the model's judgement — so it survives the correlated blind spot when code and tests are both LLM-generated); persists evidence to `.harness-anchor/coverage-<ts>.md`.
  - `skills/test-coverage-design/` (NEW, generic) + `coverage-reference.md` — the post-impl discipline + a design-technique catalog (EP / BVA / pairwise / metamorphic …) and a *living* risk-construct checklist (C/C++ arm cross-links `cpp-sanitizers/ub-failure-patterns.md`).
  - `commands/test-plan.md` (NEW) — dispatches `coverage-analyst`; mirrors `/verify`'s fresh-context, read-only shape.
  - Warn-only cross-links: `anti-hallucination-gates` gains a "Coverage obligations" criterion (a green suite that skips the risk path is a false pass); `cpp-sanitizers` documents the run-scope caveat; `verification-runner` flags orphan binaries; `using-harness-anchor` lists both.

- **Feature `id` uniqueness enforcement** (closes a gap the JSON Schema can't: draft-07 has no per-field uniqueness, so `feature_list.schema.json` was structurally blind to `id` collisions — and `id` is the lookup key for status/evidence updates, so a duplicate silently corrupts the source of truth). Warn-only, defense-in-depth:
  - `scripts/feature-list-validate.mjs` (NEW, node, read-only) — default mode flags duplicate ids (exit 3); `--check <id>` is a pre-write candidate test that suggests the first free `-N` suffix. Single responsibility = uniqueness (id *format* stays the schema's job).
  - **Pre-write (primary):** `feature-state-keeper` gains a "Feature id uniqueness" section — check the candidate id against existing ones (the file was just read to edit it; or `--check`) and qualify a colliding id *before* writing.
  - **At-write safety net:** `hooks/post-tool-use` warns (warn-only, fail-silent) the moment a `feature_list.json` write introduces a duplicate id, naming it + suggesting a free one.
  - **Pre-commit backstop:** `/session-end` runs the validator before offering a commit.
  - New `tests/unit/feature-list-validate.sh` + a duplicate-id hook-contract case + an e2e-fixture uniqueness assertion; schema carries an inert `$comment` documenting why uniqueness is enforced imperatively, not in the schema.

### Fixed

- `scripts/toc-freshness.sh`: **exclude `PROJECT-TOC.md` from its own staleness counts** (pathspec `:(exclude)` on both the committed-diff and working-tree checks). Previously the TOC counted itself — committing a regenerated TOC always advanced HEAD past its own anchor, so **"fresh" was unreachable in the canonical tracked-TOC workflow** (the very one `/index-project` recommends: `git add PROJECT-TOC.md && git commit`) and the "stale … run /index-project" nudge fired permanently, prescribing a cure that couldn't work. Now the regenerate→commit loop converges to `fresh`, and `stale` means real drift. Status words/format unchanged (consumers — SessionStart banner, `/status`, `index-curator` — unaffected). Rewrote the unit-test stale fixture that had pinned the old behavior, added a canonical-workflow regression case, and corrected three docs/comments that had rationalized the false-stale as "an inherent limitation" (`tests/e2e-cpp-fixture/bootstrap.sh`, `docs/troubleshooting.md` §3, `skills/project-indexing` algorithm note) plus the inaccurate "always stale" wording in `/anchor` docs (a no-git project actually reports `not-git`).

## [0.4.0] - 2026-06-09

### Added

- **Test & CI hardening** (no plugin-behavior change; closes audit gaps G1–G6):
  - `tests/unit/` — black-box unit tests for the two most complex scripts: `index-builder.mjs` summary extraction (every comment marker incl. the `-->`/`--!>` `js/bad-tag-filter` fix, 80-char truncation, `## Decisions` preservation, binary/lockfile skipping) and `toc-freshness.sh` (all status branches incl. the missing-anchor `git cat-file` guard).
  - `tests/unit/feature-list-schema.sh` — exercises `feature_list.schema.json` itself (anti-drift) and proves the Default-FAIL rule (`status=pass ⇒ evidence`) rejects a violating doc. Python stdlib only.
  - `tests/cpp-detection/non-cpp-fixture/` — negative fixture asserting `cpp-detect.sh` → `is_cpp_project:false` (guards invariant #5).
  - `tests/skill-triggering/` — 7 new adversarial prompts (11/11 sibling skills now covered) + `check-coverage.sh`, a no-LLM CI guard enforcing the "one prompt per skill" authoring rule.
  - CI (`validate.yml`): runs the new unit / coverage / negative-fixture steps on the ubuntu+macOS matrix, plus a `shellcheck` job. All hooks/scripts/tests were brought **shellcheck-clean at `warning`** — fixed `SC2064` (trap expanded at set-time, not signal-time) and `SC2164` (unguarded `cd`) across the test scripts, and `for`-over-`find` → `while read` in `validate-anchor.sh` — so the gate runs at `--severity=warning` (notes/style surfaced informationally).
- **C/C++ analysis-tool coverage made honest + selective expansion** (`skills/cpp-static-analysis` + `skills/cpp-sanitizers`; no `description` changed, so triggering is unaffected):
  - `cpp-sanitizers`: documented **LeakSanitizer** as ASan's already-running leak component — on by default on Linux, `ASAN_OPTIONS=detect_leaks=1` on macOS (supported, off by default), plus the lighter standalone `-fsanitize=leak` mode and `LSAN_OPTIONS` suppression.
  - `cpp-static-analysis`: clarified that clang-tidy's `clang-analyzer-*` **is** the Clang Static Analyzer (per-TU), so `scan-build` is only for whole-build / HTML / cross-TU passes — preventing redundant "new analyzer" runs.
  - `cpp-static-analysis`: added **GCC `-fanalyzer`** (GCC 10+) as a different-engine second opinion, explicitly flagged **C-only** (the manual: "only suitable for use on C code") so it is never misapplied to C++. Mirrored in `tool-comparison.md`.
  - Deliberately rejected to stay lean: RealtimeSanitizer (niche), an MSan build recipe (high-friction), valgrind helgrind/DRD, and CodeChecker / Infer / PVS-Studio (heavyweight / commercial).
- **`docs-lookup`: first-party ecosystem docs MCPs as a preferred Step-1 source.** Generalized Step 1 from "Context7" to "structured docs MCP — Context7, or a first-party MCP for its ecosystem," naming **Microsoft Learn** (`microsoft_docs_search` → `microsoft_docs_fetch`) as the prime example for .NET/Azure/Windows/MSVC topics — relevant to the plugin's own C/C++-on-Windows surface (MSVC errors, Win32/SDK headers). Optional + prefer-when-present: same graceful fall-through to Context7 → WebSearch, so the zero-dependency ethos holds (Context7 is already treated this way). Stated as a general principle, not a vendor list, to avoid chain bloat. `description` unchanged; the README companion-plugins table is synced to match.
- **State files scale to heavyweight, long-running projects** (new deterministic `scripts/*.mjs` tools + adaptive SessionStart injection; non-breaking — hook JSON shape + warn-only contract unchanged):
  - `scripts/feature-list-sort.mjs` — reorders `feature_list.json` **actionable-first** (in-progress → blocked → planned → pass) at `/session-end`; deterministic, idempotent, and lossless (preserves unknown top-level keys, evidence, 2-space formatting). Lets the agent read the *head* of a long ledger and stop.
  - `scripts/progress-prepend.mjs` — inserts a new `progress.md` entry after the header **without loading the whole file** into context (newest-first; safe on a malformed/headerless file).
  - `scripts/index-builder.mjs` now emits a **`## Directory map`** (one line per directory — direct-file + subdir counts) above `## Files`.
  - `hooks/session-start` **adaptively** injects the TOC: full `## Files` on a small repo, else the directory map, else (huge repo) the shallowest directories first — always within the ≤8000-char Tier-1 budget (now tested at scale). A 3-tier read path (top dirs → map → files) without a multi-file tree.
  - Wired through `/session-end`, `/index-project`, `project-indexing`, `feature-state-keeper`, the `AGENTS.md` / `PROJECT-TOC.md` templates, and `docs/architecture.md`. Existing projects self-heal (no migration). New unit tests + a budget-at-scale hook-contract case.

### Fixed

- `hooks/post-tool-use`: quote the prefix in `rel_path="${file_path#"$project_root"/}"` (`SC2295`) so the relative-path computation does **literal** prefix removal instead of glob-pattern matching — robust to project paths containing `[ ] * ?`. Behavior-identical for normal paths (post-tool-use contract test 6/0); the shell suite is now shellcheck-clean at all severities.
- `templates/cpp/sanitizer-build.sh.tpl`: corrected a factually-wrong comment claiming "macOS doesn't support leak detection" — macOS *does* support ASan leak detection (off by default; `detect_leaks=1` enables it, which the script already sets). Comment-only; build behavior unchanged.

## [0.3.3] - 2026-06-04

### Changed

- **Made `superpowers` complementarity explicit.** An audit of harness-anchor against `superpowers` found a few overlapping process/record seams; this closes the one with real drift risk and cross-references the rest. Additive only — no skill `description` changed, so triggering is unaffected.
  - `skills/feature-state-keeper`: added an **"altitude" reconciliation contract** so harness-anchor's `feature_list.json` (durable project feature ledger / source of truth) and superpowers' plan-docs + `TodoWrite` (ephemeral step-level execution) don't drift or double-book — on disagreement, `feature_list.json` (with evidence) wins.
  - `skills/anti-hallucination-gates`: cross-references `superpowers:verification-before-completion` — same Iron Law; one verification run satisfies both gates (don't re-verify).
  - `skills/self-correction-loop`: names the switch threshold to `superpowers:systematic-debugging` (1–2 minimal fixes → switch; the cap-at-3 budgets are intentionally aligned).
  - `commands/session-end.md`: clarifies it is a session-pause checkpoint; branch/PR/merge belongs to `superpowers:finishing-a-development-branch`.

## [0.3.2] - 2026-06-02

### Fixed

- **Stop hook emitted JSON invalid for the Stop event.** `hooks/stop` wrapped its wrap-up reminder in `hookSpecificOutput` / `additionalContext` — valid for PostToolUse / UserPromptSubmit / SessionStart, but the **Stop** event has no `additionalContext` channel, so Claude Code rejected the output (`Hook JSON output validation failed — (root): Invalid input`) and the reminder never surfaced. The reminder now uses a top-level `systemMessage` — non-blocking and schema-valid (still never `decision:"block"` / `stopReason`, per invariant #1). The `tests/hook-contracts/stop-wrap-up.sh` contract test gained a real Stop-schema assertion (rejects `hookSpecificOutput` and any blocking field); it previously checked only JSON syntax + substrings, which is why the bad shape shipped.

## [0.3.1] - 2026-06-01

### Added

- **SessionStart `/cpp-init` recommendation:** the state banner now recommends `/cpp-init` when a project is detected as C/C++ and is already anchored (`feature_list.json` present) but lacks `.clang-format`/`.clang-tidy` — the same "missing artifact → run the command" pattern already used for `/anchor` and `/index-project`. Manual commands never auto-trigger, so the hook surfaces this one at the moment it is needed. Warn-only; fires only on that precise state (no nagging when the config exists or the project is un-anchored). A new C/C++ fixture in `tests/hook-contracts/session-start-banner.sh` asserts the hint fires when clang config is absent and is suppressed once it exists.

### Changed

- **`using-harness-anchor` command catalog → when-to-recommend guidance:** the meta-skill that SessionStart injects every session now frames each command by *when to recommend it* (parallel to its `## Sibling Skills` section) instead of a flat what-it-does list, and back-fills the missing `/sanitize` entry (shipped in v0.3.0 but never cataloged).

## [0.3.0] - 2026-05-30

### Added

- **`/sanitize` command (Tier 2):** `commands/sanitize.md` builds a C/C++ project under ASan+UBSan (TSan separately) and runs its tests, reporting in `verification-runner`-style fixed sections with a mandatory `.harness-anchor/sanitize-*.log` evidence path. Reuses `templates/cpp/sanitizer-build.sh.tpl`; refuses on non-C/C++ projects via `cpp-detect.sh`. `skills/cpp-sanitizers` references it.
- **PostToolUse `/sanitize` nudge:** the hook appends a one-line "consider /sanitize" suggestion to an *existing* warning on a C/C++ source edit — bounded, never standalone, never runs sanitizers inline (invariants #4/#7).
- **`/verify --fix` auto-fix loop (Tier 2):** opt-in only; on a NOT READY verdict it applies the verification-runner's `### Recommendation`-scoped fixes, then re-verifies with a *fresh* verification-runner, max 2 cycles, stopping on pass or budget exhaustion. Every change is surfaced; pass is never asserted without a fresh PASS (invariant #8). `commands/verify.md` gains `Edit, Write` for this path.

## [0.2.1] - 2026-05-29

### Added

- **R4 — command `allowed-tools` shape validation:** `scripts/check-allowed-tools.sh` is the single source of truth for the rule that every `commands/*.md` must declare an `allowed-tools:` line shaped as a comma-separated list of tool-name tokens (identifier + optional `(scope)`, e.g. `Bash(git diff:*)`; MCP names allowed). It validates *shape, not membership* — no hard-coded tool registry to go stale. Wired into `validate-anchor.sh [6/9]` for real commands; negative fixtures under `tests/command-fixtures/` exercised by a new CI step.
- **P1 — hook wall-clock benchmark:** `tests/bench/hook-timing.sh` bootstraps the e2e fixture and times all four hooks against a time budget (warn ≥2s, fail ≥5s), guarding invariant #7 the way `measure-context.sh` guards the byte budget (invariant #2). Runs on both CI arms.

## [0.2.0] - 2026-05-29

### Added

- **Layer A — Robustness:**
  - `scripts/index-builder.mjs` writes `.harness-anchor/last-error.log` on failure; clears stale log on success (`c9e1a37`)
  - `scripts/validate-anchor.sh` extended with agent frontmatter (name + description) and command frontmatter (description only) checks (`c9e1a37`)
  - `tests/hook-contracts/` — 5 contract tests for all 4 hooks (session-start banner + timeout, post-tool-use warn, stop wrap-up, user-prompt-submit scope-jump) (`c9e1a37`)
  - R1 total watchdog for `hooks/session-start` and `hooks/post-tool-use`: 5s tempfile-guarded cap, emits nothing on timeout (avoids partial-JSON pitfall) (`c9e1a37`)

- **Layer B — Anti-drift:**
  - `hooks/session-start` reads version from `plugin.json` at runtime (no hardcoded `v0.1.0`) (`5296b74`)
  - README check count de-hardcoded ("count printed on run") (`5296b74`)
  - Removed dead `scripts/escape-json.sh` (zero references; all hooks inline `escape_for_json`) (`5296b74`)
  - Extracted `scripts/toc-freshness.sh` from session-start (shared by `/status`) (`5296b74`)

- **Layer C — Manifest validation + CI:**
  - `scripts/validate-manifests.sh`: Python-stdlib-only validator for `plugin.json` and `marketplace.json` (name, description, version semver, version sync) (`6162175`)
  - `scripts/schemas/{plugin,marketplace}.schema.json` — reference docs (not executed) (`6162175`)
  - `tests/manifest-fixtures/` — negative JSON fixtures (bad-keywords, bad-name, bad-version, version-mismatch) (`6162175`)
  - CI matrix: `ubuntu-latest` + `macos-latest` (`6162175`)
  - `tests/posix-compat.sh` — scans for GNU-only flags (`6162175`)

- **Layer D — Usability:**
  - `/status` command — read-only project overview (6 Markdown sections) (`56fa3c9`)
  - Commit-hygiene section folded into `feature-state-keeper/SKILL.md` (`56fa3c9`)

- **Layer E — E2E fixture + observability:**
  - Expanded `tests/e2e-cpp-fixture/`: 3 features (planned/in-progress/pass), C++ sources, gtest, full state files, `.clang-format`/`.clang-tidy` (`d64eab5`)
  - `tests/e2e-cpp-fixture/bootstrap.sh` — creates isolated git repo from fixture (`d64eab5`)
  - `scripts/measure-context.sh` — measures SessionStart output against the 8000-char cap (exit 1 if exceeded, warn at 90%) (`d64eab5`)

- **Layer F — Docs:**
  - `CHANGELOG.md` (this file) — Keep-a-Changelog format
  - `docs/troubleshooting.md` — 5+ failure modes with diagnosis + fix

### Fixed

- TOC freshness algorithm: validate anchor commit exists (`git cat-file`) before diffing; sanitize arithmetic with `tr -cd 0-9`; extend grep pattern to include underscores (`c9e1a37`)
- `hooks/post-tool-use`: stdin read before backgrounding (bash redirects bg stdin to `/dev/null`) (`c9e1a37`)
- `scripts/index-builder.mjs`: `exit(2)` inside try block → `throw Error()` so catch block actually runs and writes error log (`c9e1a37`)

### Changed

- `tests/self-correction/` → `tests/hook-contracts/` (rename ripple: README, tests/README.md, CLAUDE.md, validate.yml) (`c9e1a37`)
- `validate-anchor.sh` sections renumbered 7→9 (`c9e1a37`)
- `validate-anchor.sh` excludes `tests/manifest-fixtures/` from JSON parse (`6162175`)

## [0.1.0] - 2026-05-28

### Added

- Initial harness-anchor plugin: 12 skills, 3 subagents, 5 commands, 4 warn-only hooks (`677b76c`)
- SessionStart hook with state banner, TOC freshness, project type detection (`677b76c`)
- PostToolUse hook with regression-warn + clang-tidy (`677b76c`)
- Stop hook with wrap-up reminders (`677b76c`)
- UserPromptSubmit hook with scope-jump detection (`677b76c`)
- C/C++ engineering suite: build systems, static analysis, formatting, sanitizers (`677b76c`)
- `docs-lookup` skill with Context7 → WebSearch fallback chain (`ba4e132`)

### Fixed

- 5 plan-vs-implementation gaps closed across 2 rounds (`f099f6c`, `81c332f`)

### Docs

- README rewrite, agent compression, docs-lookup test case (`bdb0f99`)

[Unreleased]: https://github.com/Redtropig/harness-anchor/compare/v0.3.3...HEAD
[0.3.3]: https://github.com/Redtropig/harness-anchor/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/Redtropig/harness-anchor/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/Redtropig/harness-anchor/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/Redtropig/harness-anchor/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/Redtropig/harness-anchor/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Redtropig/harness-anchor/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Redtropig/harness-anchor/releases/tag/v0.1.0
