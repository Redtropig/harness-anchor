# harness-anchor tests

Five test layers, in order of cost:

| Layer | What it tests | Speed | Requires Claude session? |
|---|---|---|---|
| `scripts/validate-anchor.sh` | Plugin self-consistency: file structure, JSON validity, skill/agent/command frontmatter (incl. `allowed-tools` shape), hook output shape | <1s | No |
| `tests/hook-contracts/` | Hook **contract**: given synthetic stdin, hook produces expected JSON | <5s | No |
| `tests/bench/` | Hook **timing**: wall-clock per hook vs. the 5s budget (invariant #7) | <10s | No |
| `tests/cpp-detection/` | **Build system detection**: `cpp-detect.sh` correctly identifies CMake/Meson/Make/Bazel | <1s | No |
| `tests/skill-triggering/` | Skill **triggering**: real Claude session run with naive prompts, verify skill is invoked | 30s-5min per case | **Yes** (claude CLI) |

## Quick test (no Claude required)

```bash
bash scripts/validate-anchor.sh
bash tests/hook-contracts/post-tool-use-warn.sh
bash tests/hook-contracts/session-start-banner.sh
bash tests/hook-contracts/session-start-timeout.sh
bash tests/hook-contracts/stop-wrap-up.sh
bash tests/hook-contracts/user-prompt-submit-scope-jump.sh
bash tests/bench/hook-timing.sh
for fix in cmake meson make bazel; do
  bash scripts/cpp-detect.sh --target "tests/cpp-detection/$fix-fixture"
done
```

All should report PASSED with zero failures.

## Hook contract tests

Each script under `tests/hook-contracts/` tests one hook's behavior:

| Test | Hook | What it verifies |
|---|---|---|
| `post-tool-use-warn.sh` | PostToolUse | Regression warning on pass-feature edit; silent for non-anchored dir |
| `session-start-banner.sh` | SessionStart | Valid JSON with state block; valid JSON even for non-anchored dir |
| `session-start-timeout.sh` | SessionStart | Total watchdog (R1): caps at ~5s, emits no truncated JSON on timeout |
| `stop-wrap-up.sh` | Stop | In-progress feature reminder; silent for non-anchored dir |
| `user-prompt-submit-scope-jump.sh` | UserPromptSubmit | Scope-jump keyword + active feature triggers warning; benign prompt silent |

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

- `tests/cpp-detection/{cmake,meson,make,bazel}-fixture/` — minimal projects for verifying `cpp-detect.sh` build-system detection
- `tests/e2e-cpp-fixture/` — slightly fuller minimal CMake project for `/anchor` + `/cpp-init` + `/verify` end-to-end flow
- `tests/manifest-fixtures/` — negative JSON fixtures for validating `validate-manifests.sh` error paths
- `tests/command-fixtures/` — `good-*`/`bad-*` command files for validating `check-allowed-tools.sh` (R4) accept/reject paths

## CI

`.github/workflows/validate.yml` runs the **fast** layers (validate-anchor + hook-contracts + cpp-detection) on every push. Skill-triggering tests are slow and require a Claude session; run them manually before tagging a release.
