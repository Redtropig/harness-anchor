# Evidence Checklist — Cookbook

A practical cookbook for "what artifact proves this criterion is met". Use when filling `evidence.artifacts` in `feature_list.json`.

## By criterion type

### Build / compile passes

| Project type | Evidence command | Artifact path suggestion |
|---|---|---|
| CMake | `cmake --build .build 2>&1 \| tee .harness-anchor/build-<ts>.log` | `.harness-anchor/build-<ts>.log` |
| Meson | `meson compile -C builddir 2>&1 \| tee .harness-anchor/build-<ts>.log` | `.harness-anchor/build-<ts>.log` |
| Make | `make 2>&1 \| tee .harness-anchor/build-<ts>.log` | `.harness-anchor/build-<ts>.log` |
| Node | `npm run build 2>&1 \| tee .harness-anchor/build-<ts>.log` | `.harness-anchor/build-<ts>.log` |
| Rust | `cargo build --release 2>&1 \| tee .harness-anchor/build-<ts>.log` | `.harness-anchor/build-<ts>.log` |
| Python | `python -m py_compile $(git ls-files '*.py')` (no log; capture stdout) | `.harness-anchor/pycompile-<ts>.log` |

### Type-check passes

| Project | Command | Artifact |
|---|---|---|
| TypeScript | `npx tsc --noEmit 2>&1 \| tee .harness-anchor/typecheck-<ts>.log` | typecheck log |
| Python (mypy) | `mypy . 2>&1 \| tee .harness-anchor/mypy-<ts>.log` | mypy log |
| Rust | (`cargo check` is part of build; same artifact) | same as build log |
| C/C++ | (compiler is the type-checker; same artifact) | same as build log |

### Tests pass

| Framework | Command | Artifact |
|---|---|---|
| GoogleTest (ctest) | `ctest --test-dir .build --output-on-failure 2>&1 \| tee .harness-anchor/tests-<ts>.log` | tests log |
| Catch2 | `./test_binary 2>&1 \| tee .harness-anchor/tests-<ts>.log` | tests log |
| Jest | `npm test -- --json --outputFile .harness-anchor/jest-<ts>.json` | jest json |
| pytest | `pytest --junit-xml .harness-anchor/pytest-<ts>.xml -v` | pytest xml |
| Cargo | `cargo test 2>&1 \| tee .harness-anchor/cargo-test-<ts>.log` | cargo log |

The log must show: **N passed, 0 failed, 0 errored**. If skipped > 0, note it — it's not failure, but may indicate gaps.

### Static analysis clean

| Tool | Command | Artifact |
|---|---|---|
| clang-tidy | `run-clang-tidy -p .build 2>&1 \| tee .harness-anchor/clang-tidy-<ts>.log` | tidy log |
| cppcheck | `cppcheck --enable=warning,style,perf src/ 2>&1 \| tee .harness-anchor/cppcheck-<ts>.log` | cppcheck log |
| ESLint | `npx eslint . --format json -o .harness-anchor/eslint-<ts>.json` | eslint json |
| ruff | `ruff check . --output-format json > .harness-anchor/ruff-<ts>.json` | ruff json |
| clippy | `cargo clippy -- -D warnings 2>&1 \| tee .harness-anchor/clippy-<ts>.log` | clippy log |

Evidence requires either:
- "0 warnings" / "no issues found" line, OR
- A non-empty report file that the user/reviewer has accepted (with explicit notes)

## Anatomy of a good evidence object

```json
{
  "timestamp": "2026-05-28T14:23:01Z",
  "commit": "a4f2e8c9d1b3",
  "artifacts": [
    ".harness-anchor/build-2026-05-28T14-22.log",
    ".harness-anchor/tests-2026-05-28T14-23.log",
    ".harness-anchor/clang-tidy-2026-05-28T14-23.log"
  ],
  "notes": "All 47 tests passing. clang-tidy: 3 modernize-* warnings (deferred, see issue #12). cppcheck: clean."
}
```

The `notes` field is where you record nuance — known noisy warnings, skipped tests, etc.

## Anti-patterns

- "Evidence: I think it works" → not evidence
- "Evidence: ran the test once" → which command? what output? Path?
- "Evidence: tests pass" → which tests? how many? log path?
- Artifact path that doesn't exist → check `ls -l` before claiming
- Reusing yesterday's artifact path for today's pass → re-run, generate fresh

## When you genuinely can't generate evidence

If a feature is intrinsically not testable by build/tests/lint (e.g., "documentation is written"):

- Use a `notes` entry pointing to the artifact (the doc file path + commit)
- Reviewer can verify by reading the doc
- Add a `done_criteria` like "Doc covers X, Y, Z" so the criterion is explicit
