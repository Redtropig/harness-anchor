# Changelog

All notable changes to harness-anchor are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.18.0] - 2026-07-31

MINOR: watchdog coverage on two hooks that never had it is a new backward-compatible
capability, and it ships with a new gate check and a new contract test — an
`### Added` section, which per the versioning rule means MINOR rather than PATCH.

### Added

- **`hooks/stop` and `hooks/user-prompt-submit` now carry the R1 5s watchdog.**
  Both fork a JSON engine — `ha_json_engine_init` probes by *running*
  `python3 -c 'print(1)'`, and both then call `ha_flist_active` — so a wedged
  interpreter (antivirus scan, network-mounted PATH entry, broken `python3` shim)
  hung them indefinitely with nothing to intervene. Measured against the wedged
  engine before the fix: **25s and still running** when the harness cut it off, on
  both hooks. After: **5s**, emitting nothing, exit 0. The three peers have had
  this since v0.10.0; these two were missed and nothing noticed for eight releases.
  `ha_json_engine_init` is deliberately *inside* `main()` — outside it, the probe's
  own hang would sit in front of the watchdog rather than behind it.
- **`tests/hook-contracts/stop-prompt-timeout.sh`** — wedges every engine in the
  chain (`python3`/`python`/`py`/`node` stubs that sleep 30) against an anchored
  fixture, then asserts each hook exits 0 within 8s emitting nothing. Verified red
  on the pre-fix hooks before being accepted as green on the fixed ones.
- **`scripts/validate-anchor.sh` [11/12] now asserts the watchdog's presence** in
  every hook `hooks/hooks.json` registers, so a newly added hook cannot ship
  without one. Structural check: it catches absence, not misbehaviour — proving
  the watchdog *fires* is the contract test's job. (163 assertions, was 158.)
- **`tests/unit/doc-align.sh`** — integrity of the `doc-align` markers, which were
  a standing unverified claim. Per marker: exactly one 40-hex sha, it resolves to a
  real commit, that commit is an ancestor of HEAD, and any abbreviated sha in the
  prose agrees with it. Markers are discovered by glob with a non-vacuity guard.
  Two real failures in one session motivated it: a 40-character sha typed out from
  a 7-character one (the second time that has happened in this repo), and a marker
  left pointing at a commit an `--amend` had rewritten. Both look exactly like a
  correct marker when read. Sha resolution needs real history, so it SKIPs — loudly
  — on the shallow clone CI checks out by default.
- **`tests/bench/hook-timing.sh` covers `pre-compact`, and guards its own list.**
  The benchmark for the 5s budget enumerated four hooks and had silently omitted
  `pre-compact` since v0.15.0 — the test for invariant #7 was not measuring one of
  the hooks the invariant governs. The hooks stay enumerated, because each needs
  its own env/stdin to reach its active path, but a completeness check now fails
  if any hook on disk is not benchmarked.
- **`docs/troubleshooting.md` #16 — "a hook goes completely silent".** With every
  hook now bounded at 5s, a wedged JSON engine produces silence indistinguishable
  from a legitimately quiet hook. The entry names the likely causes (antivirus on
  first interpreter run, the Microsoft Store `python3` alias, an unreachable
  network share on PATH), gives the two timing commands that tell them apart, and
  states that any one engine of the four is enough.

### Fixed

- **`docs/commands.md` had drifted for six releases and said so nowhere.** Its
  `doc-align` marker still pointed at `74a06eb` (v0.12.0, 2026-07-14) — an
  assertion of "verified" that had not been true since v0.13.0. Re-read against
  every file under `commands/` plus the scripts and agent that implement them.
  What the stale marker had been hiding: `/verify`'s report was documented with
  five sections when `verification-runner` emits nine and had gained
  `### Integrity`; `/status` was documented as parsing JSON with `python3→node`
  when the chain has been python3 → python → py -3 → node → pure-bash since
  v0.13.0; `/session-end`'s fact-gathering omitted the secrets scan and
  state-hygiene facts, and its steps omitted the consent-gated golden-rules
  consolidation and the secrets-before-commit gate; `/gc` never mentioned that
  doc-drift scanning is bounded and can return PARTIAL; the discoverability table
  still described PostToolUse as firing only on `Edit`/`Write`, which stopped
  being true in v0.15.0. The new marker carries an explicit scope note naming what
  was checked against implementation versus merely read.
- **`tests/README.md` listed five hook-contract tests while sixteen shipped**, and
  its "quick test" block enumerated them by hand directly below a comment
  explaining that enumeration rots. The per-file table is now indexed by hook —
  five rows that change when the hook set does, not when a test is added — and the
  quick-test block globs. Also corrected there: the hook-contract timing (two
  tests deliberately wait out a 5s watchdog, so `<5s` was never true of the
  directory) and the CI matrix, which has included Windows since v0.13.0.
- **`docs/design.md` claimed `cpp-detect.sh` gates which C/C++ skills load.** It
  does not. Skills are selected by description matching — all four C/C++ ones open
  with "Use in C/C++ projects", which is the actual gate — while `cpp-detect.sh`
  gates the injected meta-skill's `cpp-only` regions and makes `/cpp-init` and
  `/sanitize` refuse outright. The sentence had restated CLAUDE.md's *normative*
  wording ("must include a frontmatter trigger condition") as a description of
  what the files do; only one of the four actually names a build system.
- **`tests/windows-compat.sh` [1/5] punished documenting the hazard it polices.**
  Its own comment promised that "prose mentions and comments must NOT trip this",
  but the grep had no comment filter — so a comment explaining that
  `ha_json_engine_init` probes by running `python3 -c` was reported as a bare
  `python3` invocation. It fired on both hooks touched in this release. Comment
  lines are now dropped exactly as [2/5] already did it. Coverage is unchanged:
  an executable line is never comment-leading, and a trailing comment after real
  code still matches. Both directions verified by mutation.

### Changed

- **`README.md` rewritten** to lead with the failure modes and a real
  `hooks/session-start` banner rather than a component inventory; the long-form
  rationale moved to the new `docs/design.md`. Also corrects a stale hook count
  (four claimed, five shipping), a false "Subagents (5, read-only)" heading
  (`index-curator` carries `Write` — it has to), and a description of
  `done_criteria` as booleans (it is an array of strings; the enforced rule is
  `evidence: null` ⇒ `status` cannot be `pass`, per `feature_list.schema.json`).
- **`docs/design.md` added** — the design rationale at full depth, with the
  alternative rejected in each case. Its warn-only section corrects the previous
  README's claim that all four warn hooks inject `additionalContext`: Stop has no
  such channel and uses `systemMessage`, and PreCompact reaches only the user.

## [0.17.1] - 2026-07-31

PATCH, not MINOR: both entries are repairs to components that already shipped —
nothing belongs in an `### Added` section.

### Fixed

- **`doc-drift-scan.sh` flooded the consumer it reports to.** `HARD_CAP` bounded
  the symbol set; nothing bounded the candidate *rows*, which are the unit the
  reader actually pays for. Measured on this repository's own `v0.16.0..v0.17.0`
  range: 54 symbols → 4765 rows / 759 KB. The 3000-token SessionStart budget
  invariant is this repo's scale for what injected context may cost; 759 KB from
  one sensor is not in that world. Wherever the consuming tool's output limit
  falls, a payload that size is past it — so `drift-analyst` was adjudicating a
  list the harness had already cut, silently, with no note either end could see
  (an inference from the size, not a measurement of a particular tool; the
  budget argument stands without it). The script announced
  `PARTIAL` for the one truncation it performed and was blind to the larger one
  it caused. Rows are now capped per symbol (12) and in total (400), each with a
  `PARTIAL` marker, and the summary reports matched-vs-shown
  (`K candidate(s), S shown`). Same range after: 379 rows / 70 KB (−91%).
- **`doc-drift-scan.sh` harvested comment prose as if it were code.** Symbol
  extraction reads raw diff lines, comments included, so English containing
  `word (` becomes a "symbol": `O` (from `O(files)`), `b` (from the regex
  `\b(${ALT})`) and `it` (from `prefixes it (`) produced 3100 of those 4765 rows
  — 65% of the output, none of it naming any code symbol. Tokens under three
  characters are no longer searched at all: prefix matching is case-insensitive
  by design, so their rows are undecidable at *any* count. They are named
  individually on stderr — a symbol the scan chose not to look for must never
  read as one it looked for and found nothing about. This does **not** touch the
  common-word noise the header documents (`read`, `get`, `check` are real
  identifiers whose rows a reader can judge; they stay).
- **`tests/windows-compat.sh` stopped checking the newest hook two releases
  ago.** Its `HOOKS` list was hard-coded and never learned about
  `hooks/pre-compact` (v0.15.0), so checks [1/5] (no bare `python3`), [3/5]
  (`eol=lf`) and [5/5] (sources `portable.sh` + `ha_platform_init`) skipped it
  — and [1/5] has no other coverage anywhere in the suite. Nothing was broken
  (the hook complies with all three), but invariant #10's only mechanical gate
  was not enforcing it. Hooks are now globbed, with a non-vacuity guard so an
  empty discovery fails loudly instead of passing every loop below it. Same
  defect class `tests/README.md` and the CI workflow already name in their own
  comments: enumeration rots.
- **Two troubleshooting entries gave pre-0.13.0 / pre-0.16.0 advice.** #6 named a
  missing `python3` as a cause of hook-contract failures — false since v0.13.0
  made the engine chain `python3` → `python` → `py -3` → `node` → pure-bash and
  made an engine-less machine emit `SKIP`, never `FAIL`, so the entry sent
  Windows users chasing an interpreter that cannot be the problem. #5 told the
  reader to install a build tool on the strength of `init.sh`'s `command -v`
  check, which is PATH-only — the exact inference 0.16.0's discovery chain
  exists to prevent, in the guide that is supposed to teach it.
- **The meta-skill's `eol=lf` pin had never been verified.** `.gitattributes`
  pins `skills/using-harness-anchor/SKILL.md` because `hooks/session-start`
  awk-consumes it for the conditional-region filter and the injection length
  count — and `tests/windows-compat.sh` [3/5] is the only place in the repo that
  reads an `eol` attribute at all. It did not check that file. It does now.
- **A hook registered in `hooks.json` but missing on disk was invisible to every
  gate.** `validate-anchor` [1/12] names two of the five hooks; [11/12]
  enumerated all five by hand but only to check their *wiring*; `hooks.json`
  itself is validated for JSON syntax alone. [11/12] now derives its list from
  `hooks.json` — the file Claude Code actually executes — and runs registry →
  disk: registered implies exists, sources `portable.sh`, calls
  `ha_platform_init`. Complementary to `windows-compat` [5/5], which globs
  `hooks/` and runs disk → wiring; neither direction alone catches both
  failures. An empty parse, or a registration in a shape the parser does not
  recognise (parsed count ≠ declared `"type": "command"` count), fails loudly
  instead of skipping the loop.

### Changed

- `agents/drift-analyst.md` reads the scan's stderr through a six-row state
  table (up from three prose states), including the two new cap markers and the
  never-searched token list. Its known-blind-spot header records the new
  three-character floor: a clean doc-drift section now means "no doc claim about
  a changed, 3+ character, function-shaped symbol in a scanned language looks
  stale".
- `docs/troubleshooting.md` gains entries 14 and 15, covering the two sensors
  0.16.0/0.17.0 added — both of which are built to report things that *look*
  like failures and are not (`doc-drift-scan`'s six stderr states and its
  candidates-not-violations contract; `cpp-tool-discovery`'s `NOT_FOUND` for a
  tool in a non-standard prefix, and the dated phrasing that lets
  `init-verification` re-check it next session).
- **`docs/troubleshooting.md`'s `doc-align` marker is re-verified and bumped**,
  v0.9.0 → v0.17.1. It had sat at v0.9.0 through eight releases — two of which
  added entries to that very file — while its own text said "re-verify and bump
  this marker if they change". All 15 entries were re-checked against `hooks/`
  and `scripts/`, every mechanically checkable claim run or grepped rather than
  read, and the marker now states that scope instead of asserting bare
  "verified".
- `tests/unit/doc-drift-scan.sh` 22 → 32 assertions; `tests/windows-compat.sh`
  19 → 24; `scripts/validate-anchor.sh` 157 → 158.

## [0.17.0] - 2026-07-29

### Added

- **The Default-FAIL contract now runs both ways.** `anti-hallucination-gates`
  bound only positive claims ("done", "fixed", "passing"); a negative one —
  "clang-tidy isn't installed here", "there's no such function" — was bound by
  nothing, and the skill's own description carried no negative trigger, so it was
  not even loaded at the moment it was needed. Adds a two-class contract
  (capability / search) with an executable probe for each, the mirror of the
  "should" detector, and an explicit exclusion for judgement-shaped negatives.
- **Negative capability conclusions carry an observation date.** 0.16.0 made
  "not found" state its search scope; it still did not state *when*. The mandated
  form is now `searched <scope>, not found (as of <YYYY-MM-DD>)` at all seven
  sites (`init-verification` additionally re-checks inherited negative
  conclusions written in that form at session start — only negative ones,
  because those fail silently while positive ones fail loudly at the next
  invocation).
- `tests/unit/mandated-phrasing.sh` — the wording rule spans seven files and was
  held together by instruction alone through 0.16.0, whose own review found it
  already drifted, and whose release then drifted again between the command and
  the docs page restating it. Now mechanical.
- `doc-drift-scan.sh` announces what it did on stderr: `skipped — <reason>` for
  every early-exit path, `scanned N symbol(s) x M doc(s)` on completion. stdout
  remains a pure candidate list.

### Changed

- `doc-drift-scan.sh` scans a maintained language whitelist (C/C++, Python,
  JS/TS, Go, Rust, Ruby, Java, Kotlin, C#, shell) instead of C/C++ only.
- `doc-drift-scan.sh` is now O(files) per chunk end to end, not O(symbols x
  files) — but the search-phase rewrite alone (one alternation grep per
  document per chunk instead of one grep per (symbol, document) pair) was not
  what delivered that. Measured on `--base v0.15.0`: the search-phase change
  alone regressed to over 10 minutes, killed by timeout (the pre-branch nested
  loop completed there in 8m25.794s), because attribution still spawned two
  greps per CANDIDATE LINE, and candidates outnumber symbol-file pairs. The fix
  that actually shipped (`ac440ff`) replaced attribution with one `awk` pass
  per document. Measured on the identical `--base v0.16.0` range (44 symbols x
  53 docs, 4363 candidates): pre-branch nested loop 5m44.427s, shipped version
  3.917s — byte-identical output apart from a trailing-colon truncation the
  old `IFS=: read` silently caused. Chunking above 400 symbols and truncation
  above 2000 are both announced.
- The contract is restated in both directions everywhere it appears: `CLAUDE.md`
  design invariant #8, the `using-harness-anchor` meta-skill's Hard Rule 1
  (injected at every SessionStart), the README skill table and Default-FAIL
  section, and the scaffolded `AGENTS.md` template's Definition of Done.

### Fixed

- `doc-drift-scan.sh` could not see a single one of 0.16.0's own 21 changed files
  — it was pathspec-limited to C/C++ in a bash-and-markdown repository — and
  reported that by returning exactly what a clean scan returns. "Did not scan"
  and "scanned, found nothing" no longer share a channel.
- `cpp-tool-discovery.sh` searched versioned tool variants against a hard-coded
  ladder ending at 22, giving it a roughly twelve-month fuse: an installed
  `clang-tidy-23` would have reported NOT_FOUND, recreating the exact bug the
  script was written to fix. Versioned variants are now glob-enumerated.
- `tests/README.md`'s "Quick test" block enumerated 7 of the 18 unit tests that
  actually exist — the list had gone stale across several releases, so anyone
  following the documented steps ran under 40% of the suite while believing they
  had run it. Replaced with a glob, matching what CI already does for the reason
  its own comment gives: enumeration rots.
- `tests/windows-compat.sh` blamed a MSYS2 `grep` crash on backslashes. The
  actual trigger is the `-i`+`-F` flag pair alone: it aborts during matcher
  construction, so there is no safe input, and `grep` writes nothing to stderr —
  inside `$(...)` or an `if` condition a SIGABRT is indistinguishable from a
  clean "no match".

## [0.16.0] - 2026-07-28

### Added
- `scripts/cpp-tool-discovery.sh` — resolves a C/C++ tool through PATH *and* the
  platform's known install locations (VS-bundled LLVM/Ninja on Windows, keg-only
  Homebrew llvm on macOS, versioned `/usr/lib/llvm-*` on Linux). An empty
  `command -v` is no longer treated as proof a tool is absent.
- `scripts/doc-drift-scan.sh` — reverse-associates symbols touched by a change to
  `*.md` lines that mention them, surfacing documentation claims that should have
  changed and didn't. Attributes body-only changes to the enclosing symbol.
- Adversarial trigger prompt for `cpp-static-analysis` covering the
  "tool looks missing, let's skip the check" failure shape.

### Changed
- `cpp-static-analysis` / `cpp-formatting` / `/cpp-init` now resolve tool
  availability via the discovery script, and are required to report absence as
  "searched PATH + <locations>, not found" rather than "not installed on this machine".
- `drift-analyst` doc-drift now covers *stale claims* (symbol still exists, its
  contract changed) in addition to *dangling references*, and pulls unchanged
  `*.md` into scope when they mention a touched symbol. Its symbol-keyed blind
  spot is stated in the agent header.
- `cpp-build-systems` escalates to `cpp-build-doctor` after a second failed
  attempt at the same build failure, not only on "anything cryptic".
- `/anchor` closes by recommending `/cpp-init` when the project is C/C++ and
  `.clang-format`/`.clang-tidy` are absent.
- `/cpp-init` records resolved tools portably: a tool already on PATH keeps its
  bare name, and one found off PATH is written as a PATH-first lookup with the
  resolved path as fallback. `scripts/lint.sh` and `AGENTS.md` are git-tracked,
  so a bare absolute path would have broken the next machine and CI.

### Fixed
- `tests/skill-triggering/run-test.sh` passed `-p --output-format stream-json`
  without `--verbose`, which newer `claude` CLI versions reject at argument-parse
  time — before any prompt is read. Every triggering case failed identically
  regardless of content, which made `tests/README.md`'s pre-tag ritual
  unexecutable and left the "an adversarial prompt must PROVE the skill triggers"
  authoring rule unsatisfiable.
- `scripts/doc-drift-scan.sh` reported a silent clean in the two most common
  `/gc` contexts: on `main` (where `merge-base HEAD main` *is* HEAD, and the
  `HEAD~1` fallback was guarded on the base being empty rather than useless), and
  on uncommitted work (a `BASE..HEAD` range excludes the working tree, but `/gc`
  runs on uncommitted batches by design). Both fixed and covered by regression
  tests that exercise default base resolution — the path the original suite
  never touched.

## [0.15.0] - 2026-07-19

### Added

- **Session Pulse (PostToolUse fast lane, all tools).** Sliding-window self-supervision:
  duplicate-call nudge (3× identical input), error-streak nudge (3× same-tool failures),
  periodic feature checkpoint quoting the new optional `out_of_scope` ledger field —
  one nudge max per call, 10-call cooldown, pure bash on the hot path (no JSON-engine
  spawn outside the 1-in-25 checkpoint).
- **Two-stage context watermark.** The v0.12.0 flush reminder (T1) migrates into the
  fast lane — observing every tool, not just Edit/Write — and gains a T2 stage advising
  `/session-end` + a fresh session over automatic compaction.
- **PreCompact forensics.** New warn-only hook records `.harness-anchor/last-compact.meta`
  (trigger, transcript size, branch, dirty count, handoff age) and notifies the user when
  the handoff is stale; the SessionStart compact notice consumes the marker into concrete
  recovery anchors.
- **Evidence integrity.** `/verify` gains a `### Integrity` (tests-touched) report section;
  `/session-end`'s precheck scans state files for credential patterns before the commit
  offer (labels only — matched values never echoed) and reports golden-rules hygiene with
  a consent-gated consolidation flow (`[user]`-tagged rules are never touched).

### Changed

- PostToolUse registration drops its `Edit|Write` matcher (fires on all tools); the
  Edit/Write slow lane is behaviorally unchanged, and the JSON-engine pre-warm moved into
  it so the fast path stays spawn-free.

## [0.14.0] - 2026-07-18

### Added

- **Cross-platform content modularization.** Platform-specific agent-facing content
  now has two dedicated channels: `skills/<skill>/platform/<os>.md` sidecars for
  operational depth (loaded on demand behind an inline same-skill pointer;
  decision-shaping facts — availability, verdict rules — stay inline), and
  `<!-- os-<name>-start/end -->` regions in the injected meta-skill, mechanically
  dropped by SessionStart unless `<name>` matches the runtime `HA_OS` (fail-slim:
  unknown names never fatten the injection). First sidecar:
  `cpp-sanitizers/platform/windows.md` (substitute-tool preference table).
  Adding a platform = adding content; no mechanism change.
- SessionStart banner `Platform:` line (HA_OS taxonomy: `windows (Git-Bash)` |
  `darwin` | `linux`; unknown pre-set values pass through verbatim).
- `ha_platform_init` respects a pre-set `HA_OS` (tests inject platform states;
  users may override classification) — the Windows PATH shield stays keyed on
  the real uname.
- validate-anchor: joint flat sequencing across both conditional-region families,
  os-name taxonomy whitelist, inert-marker detection outside the meta-skill, and
  `[12/12]` platform-sidecar ↔ SKILL.md pointer integrity (bidirectional).

### Changed

- `cpp-sanitizers` Windows substitute detail moved to `platform/windows.md`
  (SKILL.md keeps the availability matrix and the never-CLEAN verdict rule
  inline); `/sanitize` pointer updated accordingly. CLAUDE.md invariant #2
  wording generalized to conditional regions; the skill-authoring rules gain the
  platform decision-weight split. The meta-skill is pinned `eol=lf` (it is
  awk-consumed by the injection filter).

## [0.13.0] - 2026-07-16

### Added

- **Windows support (Git-Bash baseline).** `scripts/lib/portable.sh` — shared platform
  layer sourced by all four hooks and runtime scripts: JSON engine chain
  (python3 → python → py -3 → node → narrow pure-bash) with run-validated detection
  (immune to the Windows-Store python stub), `C:\` path normalization at hook entry,
  fixed-point project-root walk (the old `!= "/"` loop spun the 5s watchdog on
  drive-letter paths), Windows PATH shield (System32's incompatible
  `find`/`sort`/`timeout` lose to `/usr/bin`), portable mtime. Plugin-controlled
  formats (plugin.json version, cpp-detect output) parse even with ZERO engines —
  fixes the `vunknown` banner and C++-projects-typed-`generic` on Windows.
- `.gitattributes` eol rules: every bash-consumed file checks out LF on all platforms
  (`run-hook.cmd` deliberately stays `text=auto` for the cmd/bash polyglot).
- `hooks/run-hook.cmd`: `%ProgramFiles%`-based + user-scope Git discovery; WSL's
  `System32\bash.exe` excluded (hooks must see Windows paths).
- C/C++ Windows counterpart mapping: `sanitizer-build.sh.tpl` turns `detect_leaks`
  off on MINGW*/MSYS*/CYGWIN* (LSan unsupported — same abort class as the v0.8.0
  macOS incident); `/sanitize` reports TSan-on-Windows as INFRA-FAIL with substitutes;
  `cpp-sanitizers` gains *Windows platform notes* with a substitute-tool table
  (WSL2/Linux-CI TSan, Intel Inspector, Dr. Memory, CRT debug heap, UMDH, `/RTC1`);
  `cpp-static-analysis` gains Windows compile_commands/driver-mode notes.
- `tests/windows-compat.sh` — static Windows invariants on every platform; new
  contract tests: `session-start-engine-degradation.sh`,
  `post-tool-use-windows-paths.sh` (Windows path bugs are string bugs — Linux CI
  catches them); windows-latest CI arm (curated core subset).

### Changed

- Hooks and `status-report.sh`/`session-end-precheck.sh` widen `command -v python3`
  gates to the shared engine chain; the four duplicated `escape_for_json` copies
  collapse into `ha_json_escape`; `hooks/stop` staleness checks use mtime arithmetic
  instead of `find -mmin` (BSD/GNU/System32-neutral). Dev-surface scripts
  (validate-anchor / validate-manifests / measure-context) discover any python via
  `ha_python`; the test suite SKIPs honestly (visible, never silent) where an assert's
  engine is missing. CLAUDE.md gains design invariant #10 (Windows surface).

## [0.12.0] - 2026-07-14

### Added

- **Write-at-realization contract** for durable memory: `capturing-golden-rules` now mandates
  capture in the turn the signal appears, with a legitimate rough-stub form (origin = pasted
  evidence at hand; Check defaults `manual review` → /gc's [MANUAL] tier); template note synced.
- `hooks/post-tool-use` Check 1d — **context-fill flush reminder**: transcript-size threshold
  (6 MiB const), warn-once per session via a `.harness-anchor/flush-warned-<session_id>` marker;
  X-vs-Y blind spots documented in the check header.
- `hooks/session-start` — **compact caution line**: fired with stdin `source=="compact"`, the
  banner warns that memory-from-recall is unreliable and points at on-disk evidence; stdin read
  is `-t 0`-guarded (non-blocking), regular startups zero-increment.
- Contract tests: `post-tool-use-flush-sentinel.sh`, `session-start-compact-caution.sh`.

### Changed

- `hooks/stop` — the stale-progress nudge now also reminds to flush chat-only durable memory;
  observation-point header documents the mtime-proxy blind spot (cannot see chat content).
- `hooks/post-tool-use` — stdin capture bounded (1s `read -t`; callers holding stdin open no
  longer hang the hook) and watchdog hardened to the SIGKILL/stdio-detached idiom
  (session-start's v0.10.0 lesson): the TERM version added ~5s wall to every
  command-substitution consumer and could not actually kill a runaway main.
- Same-turn flush cross-links: `self-correction-loop` (capture hop after a recurrent fix),
  `context-budget-discipline` (flush-before-compress ritual + rebuild-from-disk after
  compaction), `feature-state-keeper` (mid-session milestone `progress.md` prepends),
  `/session-end` step 7 reframed as the safety net rather than the capture moment.

## [0.11.0] - 2026-07-14

### Added

- `scripts/golden-rules-check.sh` — mechanical Check runner for golden rules: parses
  `### GR-<n>` blocks, executes the first backtick-quoted command per Check line (5s SIGKILL
  watchdog each, per-check isolation), three-state verdicts — CLEAN / FINDINGS(n) /
  CHECK-ERROR — so "found nothing" is never conflated with "didn't look"; `--count` feeds
  /status. Check convention documented in the golden-rules template + capturing-golden-rules
  skill: output = candidate violations, empty = clean, "manual review" in the line wins over
  backticks.
- `scripts/status-report.sh` — the whole 7-section /status snapshot in one deterministic run
  (python3→node JSON engine chain; if both are missing only the JSON-derived lines degrade,
  the rest still reports; reuses toc-freshness.sh and golden-rules-check --count).
- `scripts/scaffold.sh` — template placement for /anchor and /cpp-init (`--cpp`): placeholder
  substitution, chmod, skip-by-default for feature_list.json/golden-rules.md,
  `conflicts (need decision)` reporting, `--render` for diffs, `--overwrite <allowlist>` as
  the only write path over non-empty files — the default path physically has no overwrite
  branch.
- `scripts/session-end-precheck.sh` — one-call fact block for /session-end: active feature +
  counts, init.sh under a 60s watchdog, state-archive dry-run + ledger-validate relays,
  two-column (state/source) tree scan, TOC structural-change hint (A/D/R + untracked, capped
  at 20).
- validate-anchor `[10/10]` — the four mechanism scripts must be executable and parse, and
  every `{CLAUDE_PLUGIN_ROOT}/scripts/*` reference in commands/ + agents/ must resolve (thin
  wrappers made script paths a single point of failure); plus `[9b]` — template existence is
  now cross-checked against scaffold.sh's map (the old [9] check went silently empty once the
  command mds stopped naming template paths).
- Unit suites for all four scripts (tier precedence, three-state verdicts incl. timeout,
  rerun byte-inertness by checksum, --overwrite allowlist, --render fidelity, cpp dotfile
  drops, refusal exit codes 3/4, engine-degradation via PATH shims, duplicate-id relay).

### Changed

- `/status`, `/anchor`, `/cpp-init`, `/session-end` are now thin wrappers over the scripts
  above — the script is the single source of truth for the mechanical half; the markdown
  keeps judgment and interaction (AskUserQuestion conflict round-trips, Default-FAIL flips,
  consent-gated archival, flywheel). Only read-only /status retains a manual degraded path.
  Saves the template/gathering round-trips through context (~6-18 tool calls → 1-2 per
  command) and pins the outputs byte-level.
- `drift-analyst` runs the golden-rules mechanical tier via golden-rules-check.sh and keeps
  judgment: adjudicating FINDINGS lines (expected vs violation), reviewing MANUAL rules,
  surfacing CHECK-ERROR as a broken Check rather than a pass.

## [0.10.0] - 2026-07-05

### Added

- **cpp-gated, slimmed SessionStart injection.** The meta-skill body is now injected as a
  pure filter of `using-harness-anchor/SKILL.md`: YAML frontmatter stripped, and
  `<!-- cpp-only-start -->` / `<!-- cpp-only-end -->` regions (the four `cpp-*` sibling
  skills, `/cpp-init`, `/sanitize`) dropped in non-C/C++ projects — catching invariant #5
  up at the injection layer. The file itself is untouched for the Skill-tool path. New
  contract test pins both modes plus the skip-leak guard; `validate-anchor` checks the
  regions are flat — sequenced, non-nested, closed (a nested pair would leak past the
  filter's single skip boolean with start/end counts still equal) — and that every
  `cpp-only` line is exactly one of the two markers.
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

[Unreleased]: https://github.com/Redtropig/harness-anchor/compare/v0.18.0...HEAD
[0.18.0]: https://github.com/Redtropig/harness-anchor/compare/v0.17.1...v0.18.0
[0.17.1]: https://github.com/Redtropig/harness-anchor/compare/v0.17.0...v0.17.1
[0.17.0]: https://github.com/Redtropig/harness-anchor/compare/v0.16.0...v0.17.0
[0.16.0]: https://github.com/Redtropig/harness-anchor/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/Redtropig/harness-anchor/compare/v0.14.0...v0.15.0
[0.14.0]: https://github.com/Redtropig/harness-anchor/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/Redtropig/harness-anchor/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/Redtropig/harness-anchor/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/Redtropig/harness-anchor/compare/v0.10.0...v0.11.0
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
