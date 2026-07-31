# harness-anchor tests

Test layers, in order of cost:

| Layer | What it tests | Speed | Requires Claude session? |
|---|---|---|---|
| `scripts/validate-anchor.sh` | Plugin self-consistency: file structure, JSON validity, skill/agent/command frontmatter (incl. `allowed-tools` shape), hook output shape | <1s | No |
| `tests/unit/` | **Script unit tests**: `index-builder` summary extraction (every comment marker + truncation + `## Decisions` preservation + binary/lockfile skip) and **`## Directory map`**, `toc-freshness` status branches, `feature_list.schema.json` enforcement + **fixture id-uniqueness**, **`feature-list-sort` actionable-first reorder** (idempotent + lossless), **`feature-list-validate` id-uniqueness** (default + `--check` + read-only), **`progress-prepend` newest-first insert**, **C/C++ tool discovery**, **doc-drift symbol scan**, **mandated negative-capability phrasing**, **`doc-align` marker integrity** (sha resolves, is an ancestor of HEAD, agrees with the abbreviated form) | ~65-75s (measured, all 19) | No |
| `tests/hook-contracts/` | Hook **contract**: given synthetic stdin, hook produces expected JSON | <5s each, except the two watchdog tests that deliberately wait one out (`session-start-timeout` ~6s, `stop-prompt-timeout` ~11s) | No |
| `tests/bench/` | Hook **timing**: wall-clock per hook vs. the 5s budget (invariant #7), plus a coverage guard that fails if a hook on disk is not benchmarked | <20s | No |
| `tests/cpp-detection/` | **Build system detection**: `cpp-detect.sh` identifies CMake/Meson/Make/Bazel, plus a negative `non-cpp-fixture` → `is_cpp_project:false` (invariant #5) | <1s | No |
| `tests/skill-triggering/check-coverage.sh` | **Coverage guard**: every sibling skill has a triggering case registered (structural) | <1s | No |
| `tests/skill-triggering/` | Skill **triggering**: real Claude session run with naive prompts, verify skill is invoked | 30s-5min per case | **Yes** (claude CLI) |

## Quick test (no Claude required)

```bash
bash scripts/validate-anchor.sh
# Glob, not an enumeration — CI does the same, for the reason its own comment
# gives: enumeration rots. This list had already gone stale, silently omitting
# the two unit tests v0.16.0 added.
for t in tests/unit/*.sh; do bash "$t"; done
bash tests/skill-triggering/check-coverage.sh
# Same reason: this list used to name five hook-contract tests while sixteen
# shipped. </dev/null matters — a hook that reads stdin must not inherit yours.
for t in tests/hook-contracts/*.sh; do bash "$t" </dev/null; done
bash tests/bench/hook-timing.sh
for fix in cmake meson make bazel; do
  bash scripts/cpp-detect.sh --target "tests/cpp-detection/$fix-fixture"
done
```

All should report PASSED with zero failures.

## Hook contract tests

Given synthetic stdin, each script asserts one hook's output shape. **Indexed by
hook, not by file** — the previous per-file table named five tests while sixteen
shipped, and every release that added one made it staler. File names carry the
hook as a prefix, so the current set for any hook is
`ls tests/hook-contracts/<hook>-*.sh`.

| Hook | Covered behaviour |
|---|---|
| SessionStart | Valid JSON with the state block, and valid JSON even in a non-anchored dir; the compact-caution line; meta-skill slimming (frontmatter stripped, cpp-only / os-region gating); the state-budget sentinel; honest degradation with no JSON engine; the R1 watchdog capping at ~5s with no truncated output |
| PostToolUse | Regression warning on a pass-feature edit and silence in a non-anchored dir; the pulse fast lane (duplicate-call, error-streak, cooldown); the action-side scope-expansion warn; the durable-memory flush sentinel; clang-tidy parse fidelity; Windows path normalization |
| UserPromptSubmit | Scope-jump keyword plus an active feature triggers the warning; a benign prompt stays silent; the R1 watchdog under a wedged JSON engine |
| Stop | In-progress feature reminder; silence in a non-anchored dir; the R1 watchdog under a wedged JSON engine |
| PreCompact | Forensics marker written with every field; overwritten on a second compaction; trigger recorded verbatim; the stale-handoff `systemMessage` |

Two of these deliberately take longer than the rest: `session-start-timeout.sh`
and `stop-prompt-timeout.sh` each wedge a dependency and wait out the 5s
watchdog, so they cost ~6s and ~11s. That is the measurement, not a slow test.

## Skill triggering (needs Claude CLI)

Each prompt under `tests/skill-triggering/prompts/` is a **naive user message** that does NOT mention the skill name. The skill's frontmatter description should be specific enough that Claude invokes the Skill tool with the right name.

Run one:

```bash
bash tests/skill-triggering/run-test.sh feature-state-keeper tests/skill-triggering/prompts/state-drift.txt
```

The runner:
1. Invokes `claude -p` with the prompt and the plugin loaded
2. Captures stream-json output
3. Greps for `"name":"Skill"` invocations with matching skill name
4. PASS if found, FAIL if not

Run all (slow):

```bash
bash tests/skill-triggering/run-all.sh
```

## Fixtures

- `tests/cpp-detection/{cmake,meson,make,bazel}-fixture/` — minimal projects for verifying `cpp-detect.sh` build-system detection; `non-cpp-fixture/` covers the detect-**false** path (invariant #5)
- `tests/e2e-cpp-fixture/` — slightly fuller minimal CMake project for `/anchor` + `/cpp-init` + `/verify` end-to-end flow
- `tests/manifest-fixtures/` — negative JSON fixtures for validating `validate-manifests.sh` error paths
- `tests/command-fixtures/` — `good-*`/`bad-*` command files for validating `check-allowed-tools.sh` (R4) accept/reject paths

## CI

`.github/workflows/validate.yml` runs the **fast** layers on every push (matrix: ubuntu + macOS + Windows — several steps are gated `if: runner.os != 'Windows'`, so the Windows leg runs a curated core subset by design): validate-anchor, manifest + command negative fixtures, all hook contracts, POSIX-compat, e2e structural, context-budget + hook-timing budgets, cpp-detect (positive ×4 + negative), the `tests/unit/` script tests, and the skill-triggering **coverage** guard. A separate `shellcheck` job lints all shell — the suite is shellcheck-clean at `warning`, so the job **gates at `--severity=warning`** (notes/style surfaced informationally). Skill-triggering **invocation** tests are slow and need a Claude session — run `tests/skill-triggering/run-all.sh` manually before tagging a release.
