# Changelog

All notable changes to harness-anchor are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
  - `docs/v0.1.0-plan-addendum.md` — post-plan reality summary

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

[Unreleased]: https://github.com/Redtropig/harness-anchor/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/Redtropig/harness-anchor/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/Redtropig/harness-anchor/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/Redtropig/harness-anchor/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Redtropig/harness-anchor/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Redtropig/harness-anchor/releases/tag/v0.1.0
