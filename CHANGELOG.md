# Changelog

All notable changes to harness-anchor are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.10.0] - 2026-07-05

### Added

- **cpp-gated, slimmed SessionStart injection.** The meta-skill body is now injected as a
  pure filter of `using-harness-anchor/SKILL.md`: YAML frontmatter stripped, and
  `<!-- cpp-only-start -->` / `<!-- cpp-only-end -->` regions (the four `cpp-*` sibling
  skills, `/cpp-init`, `/sanitize`) dropped in non-C/C++ projects — catching invariant #5
  up at the injection layer. The file itself is untouched for the Skill-tool path. New
  contract test pins both modes plus the skip-leak guard; `validate-anchor` checks the
  marker pairs stay balanced and every `cpp-only` line is exactly one of the two
  markers (a malformed variant slips past the filter and the balance count).
- **`measure-context.sh` second pass** on a bare generic fixture, so the generic fixed-cost
  baseline (the common case) is measured alongside the C/C++ e2e fixture.

### Fixed

- **SessionStart watchdog: kills are now SIGKILL and the watchdog's stdio is detached.**
  Measured on macOS bash 3.2: a subshell blocked on `sleep 5` defers SIGTERM until the
  sleep completes, so (a) the parent's `wait $watchdog_pid` burned the full 5-second
  window on every session start even though `main()` finished in ~0.4s — any consumer
  waiting on the hook saw ~5s of wall per invocation — and (b) a genuinely runaway
  `main()` was never actually killed on that bash (the deferred TERM aborts the subshell
  before its `kill` line runs), leaving invariant #7's enforcement partly fictional.
  Exposed on CI by the rescaled 600-dir deep-repo fixture: slow runners pushed `main()`
  past 5s and the still-armed watchdog hard-killed it ("no output emitted"). Deep-repo
  hook wall: 5047ms → 502ms; the timeout contract (genuine overrun → silent, exit 0)
  re-verified at 5054ms.
- **SessionStart JSON escaping is O(n) via python3 (pure-bash fallback retained).** The
  `${var//…}` escaper is quadratic in matches×length: a ~12KB, ~700-line payload (a
  deep-repo directory map at the raised cap) burned the remaining watchdog window in
  this one step on pessimal macOS CI runners (~0.15s on a fast machine — which masked
  it). `json.dumps` is linear and also escapes control characters the bash path misses;
  environments without python3 keep the old escaper. Deep-repo hook wall: 502ms → 165ms.

### Changed

- **Injection budget raised: ≤ 2000 → ≤ 3000 tokens (8000 → 12000 chars) — invariant #2.**
  The old cap was 94% consumed and the squeeze fell entirely on the project-specific
  `<project-toc>` block (the banner never truncates). With the slimmed body a generic
  project's fixed cost drops to ~4.6KB (≈1160 tokens measured) and the TOC budget grows
  ~5×, so repos up to ~150 files get the full `## Files` view instead of the degraded
  directory map. All cap reference points (hook, measure script, three test files,
  CLAUDE.md, README, both context-budget references) moved in lockstep; the deep-repo
  contract fixture rescaled 200→600 dirs so the degradation path stays exercised.
- **Meta-skill body compressed ~5.9KB → ~5.0KB** — packaging only: rules, trigger keywords,
  read order, and command timing preserved item-for-item (contract-suite verified; a live
  three-scenario spot-check — scope-jump, TOC-before-Glob, no-done-without-evidence — gates
  the merge).

## [0.9.1] - 2026-07-05

### Fixed

- **`index-builder.mjs`: `--target`/`--output` require a real value.** Both flags feed the
  `PROJECT-TOC.md` write path; the lax `argv[++i]` parse let a missing or empty value
  (e.g. an unset shell variable in `--target "$DIR"`) silently fall back and rewrite the
  *current directory's* index, and a following flag was eaten as the value (probe-confirmed:
  a junk `./--output/.harness-anchor/` dir and a file literally named `--target`). A
  missing/empty/flag-like value is now a one-line usage error — exit 1, distinct from the
  runtime-fatal exit 2, raised before any target-derived path (including the error-log dir)
  is computed — the same argument contract `state-archive.mjs` adopted in 0.9.0. New unit
  test pins all six refusals plus valid-value consumption.

## [0.9.0] - 2026-07-04

### Added

- **State-file entropy governance.** The SessionStart *injection* was already hard-capped,
  but the state files themselves grew without bound on long-lived projects — and the startup
  ritual reads them every session (a year-scale project puts `feature_list.json` at ~100KB /
  20k+ tokens per session start). Now:
  - **`scripts/state-archive.mjs`** — deterministic, idempotent checkpoint archival: moves
    `progress.md` sections beyond the newest 20 to `progress-archive.md`, and `pass`
    features beyond the 10 most recently completed — evidence intact — to
    `feature_archive.json` (same schema shape). Archive-first write order + verbatim-
    duplicate convergence make it crash-safe; malformed JSON — or a ledger with duplicate
    feature ids — aborts with no writes (it never "repairs" the ledger, and never operates
    on a corrupt one). History is moved, never deleted; archives are git-tracked and
    grep-only.
  - **`/session-end` budget step** — after the ledger update, a `--dry-run` backlog check
    offers archival (explicit confirmation; the archives ride the same state-file commit);
    flags `.harness-anchor/` > ~5MB as deletable runtime evidence (informational).
  - **SessionStart state-budget sentinel** (warn-only) — one banner line when a budgeted
    file exceeds its cap (progress 64KB · feature_list 32KB · golden-rules 8KB · AGENTS 8KB
    · handoff 4KB), pointing at `/session-end`. Observation point + residual blind spots
    documented per hook rule 5 (byte size is a proxy: a quiet sentinel is not proof of
    context health). New contract test.
  - **`feature-list-validate.mjs` is archive-aware** — `feature_archive.json` shares the id
    namespace: `--check` treats archived ids as taken (suggestion clears both files),
    whole-file mode reports hot∩archive collisions, and a corrupt archive is a hard error
    rather than a silently disabled guard.

### Changed

- **Read discipline for long-lived state** (zero structural change): `AGENTS.md.tpl`
  startup rules now say *read the head* of `feature_list.json` (actionable-first keeps live
  entries on top) and *Grep, don't full-read* a large `PROJECT-TOC.md`; `project-indexing`
  adds the ~400-line hard read rule; `feature-state-keeper` documents the hot windows and
  grep-only archives; `context-budget-discipline` carries the budget table.
- Templates document their budgets (progress hot window; handoff ≤ 300 words / ~4KB;
  golden-rules ~30 rules / 8KB with prune-not-archive). Existing projects adopt the updated
  template wording by re-running `/anchor` (Overwrite/Skip/Diff prompt); the archival step,
  sentinel, and archive-aware validation are plugin-side and need no migration.
- `/status` merges archived `pass` counts (`pass: N (+M archived)`) and adds a state-budget
  line to Harness health; `/anchor` points over-budget legacy projects at `/session-end`
  instead of archiving during scaffolding.
- `scripts/validate-anchor.sh` [2/9] now also `node --check`s every `scripts/*.mjs` (glob,
  not an enumerated list).
- **`templates/context-budget.md.tpl`: Tier-1 table re-measured** — its estimates predated
  several releases (harness-anchor's injection was listed at ~700 tokens vs ~1900 actual),
  and the row structure misrepresented the banner / TOC-head / handoff-head lines as blocks
  separate from that injection. Rows now mirror the real blocks (state banner + adaptive TOC
  view + meta-skill body) under the stated 8000-char cap, with a re-measure pointer
  (`${CLAUDE_PLUGIN_ROOT}/scripts/measure-context.sh`); the Tier-2 note carries the
  measured largest skill. `context-budget-discipline`'s Tier-1 row now states cap vs
  measured (treat as full), and its sibling reference `context-budget-template.md` —
  whose same-era table even summed superpowers into the "≤2000 Tier-1 total" (that cap
  is harness-anchor's own) and described the pre-adaptive TOC truncation — is rebuilt
  on the same corrected structure, plus a watch-point for the new `State budget:`
  sentinel line.

## [0.8.0] - 2026-07-03

### Fixed

- **`templates/cpp/sanitizer-build.sh.tpl`: per-OS `detect_leaks`.** LeakSanitizer is
  unavailable on macOS/Apple toolchains; the previous unconditional `detect_leaks=1` made
  every ASan run abort at startup there ("detect_leaks is not supported on this platform")
  — the old comment even called it a no-op. Now Darwin → 0, else → 1.
- **`cpp-sanitizers` skill: corrected the LSan platform claim.** macOS is not "supported
  but off by default" — forcing it aborts ASan; standalone `-fsanitize=leak` is likewise
  Apple-unavailable. Use `leaks`(1)/Instruments on macOS, or run LSan on Linux CI.
- **PostToolUse clang-tidy signal fidelity.** On macOS the hook now injects the SDK sysroot
  via `xcrun`; when a TU still fails to parse (any `clang-diagnostic-error`) it suppresses
  the unreliable diagnostics and emits one honest notice instead of garbage warnings
  (previously the false positives from the half-parsed TU were injected as if real —
  field use had to adopt a "don't trust the hook" project rule, the opposite of a
  guardrail). New contract test pins both behaviours. Warn-only contract unchanged.

### Added

- **`templates/cpp/lint.sh.tpl`** — sysroot-correct clang-tidy wrapper dropped by
  `/cpp-init` as `scripts/lint.sh`: the stable lint entry point for agents, docs, and
  `done_criteria` (field use kept having to reinvent exactly this script on macOS).
  Locates `compile_commands.json` across root / `.build/` / `build/` / `builddir/`
  (the PostToolUse hook's search order) with a clear generate-hint when absent, and
  soft-falls-back to no sysroot args when `xcrun` cannot report an SDK path.
- **`/sanitize` INFRA-FAIL verdict** — a sanitizer-infrastructure abort (e.g. an
  unsupported `ASAN_OPTIONS` flag) is now reported as INFRA-FAIL: not a code finding, and
  never CLEAN. Previously the report shape had no honest slot for "the tooling itself
  failed before exercising anything".

### Changed

- **`cpp-static-analysis` skill** documents the macOS `'<header>' file not found` failure
  mode (Homebrew clang-tidy without the SDK sysroot) and the rule that **diagnostics from
  a failed parse are garbage** — do not act on them.
- **Friction-point skill wiring:** hook clang-tidy warnings now carry a
  `self-correction-loop` / `cpp-static-analysis` pointer tail; `/sanitize` and the cpp
  template scripts point at `cpp-sanitizers` / `docs-lookup` on infra failures — the
  knowledge existed in the skills but nothing delivered it at the moment of friction.
- `scripts/validate-anchor.sh` [9/9] now also cross-checks templates referenced from
  `commands/cpp-init.md` (previously only `/anchor`'s references were guarded).
- **CI hardening:** the hook-contract and script-unit steps now glob their test
  directories instead of enumerating files (the hardcoded list had already silently
  omitted this release's new fidelity test); ShellCheck now also lints the shipped
  shell templates (`templates/**/*.sh.tpl`); new `tests/unit/lint-template.sh` pins
  the lint wrapper's DB-search / explicit-args / no-DB / sysroot behaviours; the e2e
  cpp fixture now models `/cpp-init`'s `scripts/lint.sh` + `scripts/sanitizer-build.sh`
  outputs and CI asserts them.

## [0.7.2] - 2026-07-01

### Fixed

- **`verification-runner` wrote evidence logs without creating `.harness-anchor/` first.** It captured build/test/lint output to `.harness-anchor/verify-<step>-<ts>.log` without ensuring the dir exists; `.harness-anchor/` is gitignored and no hook creates it, so when `/verify` was the first gate run in a fresh clone or worktree the shell redirect failed with "No such file or directory" and evidence capture silently broke. Added the `mkdir -p .harness-anchor` guard its sibling evidence-writers (`coverage-analyst`, `drift-analyst`) already use, and enforced it: `validate-anchor.sh` [5/9] now asserts a **fresh-dir contract** — any agent that writes to `.harness-anchor/` must `mkdir -p` it first (read-only agents stay exempt).

### Changed

- **Extended `superpowers` complementarity — closed 3 more seams the post-v0.3.3 surface opened.** Additive only — no skill `description` changed, so triggering is unaffected (mirrors the v0.3.3 audit).
  - `skills/feature-state-keeper`: the Altitude sync-contract now names **parallel / subagent dispatch** (`superpowers:dispatching-parallel-agents` / `subagent-driven-development`) as a second shared-state writer — dispatched workers don't each write the state trio or run the subagent-backed gates (single-level); the coordinating parent reconciles `feature_list.json` once after integration.
  - `skills/init-verification`: `init.sh` is documented as the **`superpowers:using-git-worktrees` baseline** (Step 2 Project Setup / Step 3 Verify Baseline), and a fresh worktree's absent, gitignored `.harness-anchor/` is expected (recreated on demand), not un-anchored.
  - `skills/self-correction-loop`: a fresh-context sensor's findings (`/verify` · `/test-plan` · `/gc`) are triaged with **`superpowers:receiving-code-review`** rigor — verify each, push back with reasoning, don't blind-apply — most importantly inside `/verify --fix`.
  - `skills/using-harness-anchor`: Hard Rule #5 now spells out that dispatched workers must not run the subagent-backed gates (the parent does), plus a one-line interop pointer to the three skills above.

## [0.7.1] - 2026-06-22

### Changed

- **Evidence contract now covers deliverable state, not just the working tree.** `anti-hallucination-gates` gains a "Deliverable committed & reproducible" criterion (review the full `git status`, confirm the committed `HEAD` builds — not only the dirty working tree) plus an anti-pattern against dismissing uncommitted changes as "old / unrelated" without a `git diff`; `verification-runner` now reports working-tree clean/dirty and flags that green local evidence does not prove a buildable `HEAD`; `/session-end` surfaces uncommitted **source** (the whole tree, not just state files) with a HEAD-buildability caveat before offering its state-file commit (it still never auto-commits source). Closes the failure where a feature marked `pass` could leave its own source uncommitted and the committed HEAD unbuildable.
- **Coverage obligations extended to behavioural-contract regressions and liveness.** `test-coverage-design`'s risk checklist + `coverage-analyst` now derive two classes the sensors previously missed: (1) *behavioural-contract substitution* — swapping a container / algorithm / impl behind a stable API can silently regress a guaranteed observable property (ordering / stability / idempotency / documented no-op) or a public signature, caught by a characterization / metamorphic test; (2) *liveness / termination under adversarial structure* — cycles, self-edges, or already-satisfied preconditions in graphs / dependencies must terminate or diagnose, not hang. The shared-mutable row also now names check-then-act (TOCTOU) on a composite predicate.
- **Drift detection now flags dead stores.** `drift-analyst` gains a computed-but-never-used heuristic (a buffer / accumulator / timestamp built then never read) — wasted work that looks like real logic and previously slipped the scan.
- Synced `plugin.json` / `marketplace.json` descriptions with the GitHub repo About — they now reflect coverage gates (v0.5.0), entropy governance (v0.6.0), and the warn-only / zero-dependency identity, not just the pre-v0.5.0 blurb (metadata-only change carried over from the prior unreleased state).
- Bumped `plugin.json` / `marketplace.json` to 0.7.1 (synced); refreshed `docs/commands.md` (`/session-end`, `/verify`) and its doc-align marker.

## [0.7.0] - 2026-06-16

### Added

- **Action-side scope-creep detector** (`hooks/post-tool-use`): a warn-only check that fires when a new code module is created via `Write` while a feature is `in-progress`, surfacing agent-initiated scope expansion the prompt-side `UserPromptSubmit` guardrail cannot observe (the "observation-point mismatch" of #6). Edits, overwrites, test/doc files, git-ignored files, and non-git projects stay silent by construction. Resolves #6.
- **Guardrail authoring rule** (`CLAUDE.md`): new hooks must state the failure's manifestation surface (Y) and the observed signal (X), assert X ⊇ Y, or document the residual blind spot in the hook header.

### Changed

- `feature-state-keeper` / `using-harness-anchor`: scope discipline is now enforced on both the prompt side and the action side (the new post-tool-use check gives "record new scope as `planned` first" action-layer teeth).

## [0.6.1] - 2026-06-16

### Fixed

- **golden-rules count off-by-one** in the SessionStart banner (`Golden rules: N`) and `/status` harness-health. The count pattern `^### GR-` also matched the commented-out `### GR-1` *example* inside the freshly-scaffolded `golden-rules.md`, so a project with **zero** real rules reported `1`. Fixed by counting only numbered real rules (`^### GR-[0-9]`) and changing the template's example heading to the non-counted placeholder `### GR-N`. New `tests/hook-contracts/session-start-banner.sh` assertions guard it: real rules counted, commented example excluded, the as-shipped empty template → `0`, absent file → no banner line (the missing contract assertion that let this ship — mirrors the v0.3.1 cpp-init-hint pattern).

### Changed

- `scripts/validate-anchor.sh` [5/9] now also asserts every `agents/*.md` ends with the single-level constraint line ("Do not invoke other subagents from this one.") — mechanizing invariant #3, which was previously maintained by hand.

## [0.6.0] - 2026-06-16

### Added

- **Entropy governance / feedback flywheel** (Concept ⑥ — the one canonical harness-engineering concept harness-anchor had no mechanism for, built in the *lightweight, report-only* form a solo / small-team harness needs: "grow from failure, 3 rules not 30", and Böckeler's "continuous drift sensors"). Warn-only, zero-dependency, never auto-refactors:
  - `templates/golden-rules.md.tpl` (NEW) — a project state file for accumulated taste / anti-pattern rules, each `GR-<n>` tied to a concrete past failure with a Check that escalates manual → grep → lint by frequency × impact. Ships **empty** (seed on real recurrence); scaffolded by `/anchor` and **Skip-by-default** on re-anchor so accumulated rules are never wiped. Kept separate from AGENTS.md so the map stays a map.
  - `skills/capturing-golden-rules/` (NEW, generic) — the ratchet: turn a recurring failure into a durable rule ("blame the process, not the agent"). Routes the four Feedback-Flywheel signal types to their homes (failure → golden-rules; context → AGENTS.md; instruction / workflow → skill / AGENTS.md) so the file doesn't become a dump.
  - `agents/drift-analyst.md` (NEW, read-only, fresh-context) — scans **changed** code against `golden-rules.md` + generic drift heuristics (duplicated helpers, inconsistent error handling, copy-paste, oversized files, TODO pileup, **doc-drift**), grades findings must / should / nice, persists `.harness-anchor/drift-<ts>.md`. Explicitly non-overlapping with `verification-runner` (build/test/lint) and `coverage-analyst` (coverage / run-scope).
  - `commands/gc.md` (NEW) — dispatches `drift-analyst`; mirrors `/verify` & `/test-plan`'s fresh-context, read-only shape; report-only (offers scoped fixes / rule capture, never bulk-refactors). Not `git gc`.
  - **Flywheel wiring:** `/session-end` gains a one-question reflection ("did anything recur worth capturing?") — anchored to the existing checkpoint, not a new ceremony (Garg's Feedback Flywheel). `/status` gains a lightweight `### Harness health` section (rule count, last drift scan, staleness) — a few signals, deliberately not a dashboard. The SessionStart banner surfaces the golden-rules count.

- **AGENTS.md template upgraded to the validated content formula** (`templates/AGENTS.md.tpl`): commands-first (they were an empty block at the bottom), a `## Git workflow` section (the missing sixth domain, kept **value-neutral** — no hardcoded GitFlow / commit convention), a code-example stub in Conventions (examples > prose), and a pointer to `golden-rules.md`. Still a map (≤ ~80 lines). Existing projects adopt it by re-running `/anchor` (Overwrite/Skip/Diff prompt).

### Changed

- `skills/self-correction-loop`: added the **edit budget** (doom-loop) alongside the existing re-run budget — ~3–5 edits to one file chasing the same goal without the signal clearing means STOP, re-read the spec (not your own diff), switch approach or escalate; and don't "fix" a failing test by rewriting it to match the code (LoopDetection-middleware discipline).

## [0.5.0] - 2026-06-15

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

[Unreleased]: https://github.com/Redtropig/harness-anchor/compare/v0.10.0...HEAD
[0.10.0]: https://github.com/Redtropig/harness-anchor/compare/v0.9.1...v0.10.0
[0.9.1]: https://github.com/Redtropig/harness-anchor/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/Redtropig/harness-anchor/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/Redtropig/harness-anchor/compare/v0.7.2...v0.8.0
[0.7.2]: https://github.com/Redtropig/harness-anchor/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/Redtropig/harness-anchor/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/Redtropig/harness-anchor/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/Redtropig/harness-anchor/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/Redtropig/harness-anchor/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Redtropig/harness-anchor/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/Redtropig/harness-anchor/compare/v0.3.3...v0.4.0
[0.3.3]: https://github.com/Redtropig/harness-anchor/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/Redtropig/harness-anchor/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/Redtropig/harness-anchor/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/Redtropig/harness-anchor/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/Redtropig/harness-anchor/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Redtropig/harness-anchor/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Redtropig/harness-anchor/releases/tag/v0.1.0
