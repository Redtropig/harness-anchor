---
description: Build a C/C++ project under runtime sanitizers (ASan+UBSan by default; TSan separately) and run its tests, reporting findings in fixed sections. Use for crashes, leaks, use-after-free, undefined behavior, or data races — or before merging C/C++ changes. Heavy build, so it is a command, never a hook.
allowed-tools: Read, Write, Bash, AskUserQuestion
---

# /sanitize

Build the project under runtime sanitizers, run its tests, and report findings in a
fixed structure — so the result is parseable and honest about what was actually run.

**Why a command, not a hook:** a sanitizer build+test cycle takes minutes, far beyond
the ≤5s warn-only hook budget (CLAUDE.md invariants #4 and #7). PostToolUse may *suggest*
`/sanitize` after a C/C++ source change, but it must never run sanitizers inline.

## Steps

1. **Detect C/C++ and the build system:**

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/cpp-detect.sh
   ```

   Parse the JSON. If `is_cpp_project` is `false`, refuse — `/sanitize` is C/C++ only.
   Record `build_system` (cmake / meson / make / bazel).

2. **Locate (or materialize) the sanitizer build script:**
   - If `scripts/sanitizer-build.sh` already exists (dropped by `/cpp-init`), use it.
   - Else if `build_system == cmake`, AskUserQuestion to materialize it from
     `${CLAUDE_PLUGIN_ROOT}/templates/cpp/sanitizer-build.sh.tpl` → `scripts/sanitizer-build.sh`,
     then `chmod +x`. **Never overwrite a non-empty existing file without asking** (same
     overwrite policy as `/anchor` and `/cpp-init`).
   - Else (meson / make / bazel): there is no canned script — use the build-system recipe
     from the `cpp-sanitizers` skill, or ask the user for the exact command.

3. **Pick the configuration** (ASan+UBSan and TSan are **mutually exclusive** — never one build):
   - **Default: ASan + UBSan** — combinable, covers the most ground (memory errors + UB).
   - For a hang, an intermittent failure, or a suspected data race, run **TSan** in a
     *separate* build dir instead. If the symptom is ambiguous, AskUserQuestion which to run.

4. **Run, capturing evidence:**
   - Execute the chosen build+test, teeing all output to
     `.harness-anchor/sanitize-<config>-<timestamp>.log` (e.g. `sanitize-asan-ubsan-<ts>.log`).
     `.harness-anchor/` is the project's one gitignored runtime path.
   - The evidence path is mandatory: no verbal "it passed" without a log (invariant #8,
     default-FAIL). If a tool is missing (no clang/cmake), report MISSING TOOLCHAIN with the
     install hint — do not silently skip.

5. **Report — fixed structure** (mirrors `agents/verification-runner.md` so callers can parse):

   ```
   ## Sanitizer Report — <config> (<build_system>)

   ### Build
   - Command: <exact cmake/meson invocation>
   - Result: PASS (exit 0) | FAIL (exit N)
   - Evidence: .harness-anchor/sanitize-<config>-<ts>.log

   ### Tests
   - Command: <ctest / meson test ...>
   - Result: N passed, M failed
   - Evidence: <same log>

   ### Sanitizer findings
   - <none>  |  <error-class> at <file:line>
     (e.g. heap-use-after-free, signed-integer-overflow, data race)
   - For each: the ASan freed→allocated→used trio, or the UB kind + location

   ### Verdict
   - CLEAN — build + tests pass, zero sanitizer reports.
   - DIRTY — <specific sanitizer error(s)>, evidenced above.

   ### Recommendation
   - CLEAN → safe to proceed; name the config that was NOT run (e.g. "TSan not run").
   - DIRTY → fix the root cause. Do NOT add a global suppression to silence a real bug.
     For an unfamiliar error class, consult `ub-failure-patterns.md` or invoke `docs-lookup`.
   ```

6. **Never auto-suppress.** If a finding is in third-party code, surface a suppression
   *suggestion* for the user to approve (per the `cpp-sanitizers` skill) — never write a
   suppressions file on their behalf.

## When NOT to invoke

- Not a C/C++ project (`cpp-detect.sh` → `is_cpp_project: false`).
- No tests yet — sanitizers instrument *test execution*; with no tests there is nothing to exercise.
- Inside a hook — sanitizer runs exceed the hook time budget; this is user-invoked only.

## Related

- `cpp-sanitizers` skill — what each sanitizer catches, how to read output, suppressions.
- `templates/cpp/sanitizer-build.sh.tpl` — the ASan+UBSan CMake script this reuses.
- `/verify` — the general build/type-check/test/lint gate; `/sanitize` is the runtime-instrumented deepening.
- `agents/verification-runner.md` — the report shape this mirrors.
