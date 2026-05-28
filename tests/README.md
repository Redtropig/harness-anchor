# harness-anchor tests

Three test layers, in order of cost:

| Layer | What it tests | Speed | Requires Claude session? |
|---|---|---|---|
| `scripts/validate-anchor.sh` | Plugin self-consistency: file structure, JSON validity, skill frontmatter, hook output shape | <1s | No |
| `tests/self-correction/` | Hook **contract**: given synthetic stdin, hook produces expected JSON | <2s | No |
| `tests/skill-triggering/` | Skill **triggering**: real Claude session run with naive prompts, verify skill is invoked | 30s-5min per case | **Yes** (claude CLI) |

## Quick test (no Claude required)

```bash
bash scripts/validate-anchor.sh
bash tests/self-correction/post-edit-warn.sh
for fix in cmake meson make bazel; do
  bash scripts/cpp-detect.sh --target "tests/cpp-detection/$fix-fixture"
done
```

All three should report PASSED with zero failures.

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

## CI

`.github/workflows/validate.yml` runs the **fast** layers (validate-anchor + self-correction + cpp-detection) on every push. Skill-triggering tests are slow and require a Claude session; run them manually before tagging a release.
