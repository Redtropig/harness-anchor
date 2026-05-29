# Troubleshooting — harness-anchor

Common failure modes with diagnosis and fix steps.

---

## 1. SessionStart banner missing after install

**Symptom:** Starting a new Claude session, no `<harness-anchor-state>` block appears in the agent's awareness.

**Cause:** The hook script isn't being invoked, or the plugin isn't installed/enabled.

**Diagnosis:**
1. Check `/plugin` output — is `harness-anchor` listed and enabled?
2. Check `hooks/hooks.json` exists and the SessionStart entry points to the right script.
3. Run manually: `CLAUDE_PLUGIN_ROOT=/path/to/harness-anchor bash hooks/session-start` — does it produce JSON?

**Fix:**
- Re-register the local marketplace: `claude /plugin marketplace add /path/to/harness-anchor`
- Re-install: `claude /plugin install harness-anchor@harness-anchor-local`
- Start a fresh session (`/clear` or new `claude` invocation)

---

## 2. PostToolUse silent on C/C++ edits

**Symptom:** Editing a `.cpp` file produces no clang-tidy warnings, even though clang-tidy is installed.

**Cause:** Missing `compile_commands.json`. The hook skips silently when the compilation database isn't found (warn-only design).

**Diagnosis:**
1. Check for `compile_commands.json` in project root, `.build/`, `build/`, or `builddir/`.
2. Check CMake was configured with `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`.

**Fix:**
- Re-configure CMake: `cmake -S . -B .build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`
- Or symlink: `ln -s .build/compile_commands.json compile_commands.json`
- Run `/cpp-init` to tune `init.sh` for your build system.

---

## 3. PROJECT-TOC.md always reports "stale"

**Symptom:** Every session, TOC freshness shows "stale (N file(s) changed)" even after running `/index-project`.

**Cause:** Running `/index-project` regenerates the TOC with the current HEAD as anchor, but committing the TOC advances HEAD by 1 — making it "stale" again immediately. This is an inherent limitation of the commit-then-anchor approach.

**Diagnosis:**
1. Run `bash scripts/toc-freshness.sh <project-dir>` — check the anchor commit vs HEAD.
2. If the anchor is 1 commit behind and the only changed file is `PROJECT-TOC.md` itself, this is the expected behavior.

**Fix:**
- Run `/index-project` after committing other changes but before committing the TOC itself.
- Or accept the stale status — it's a warning, not a blocker. The TOC content is still accurate; only the anchor lags.

---

## 4. `/anchor` refuses to overwrite existing files

**Symptom:** Running `/anchor` asks about overwriting files that already exist, and you're not sure what to do.

**Cause:** By design, `/anchor` checks each target file and uses `AskUserQuestion` before overwriting. This prevents destructive overwrites of customized state files.

**Fix:**
- Choose "skip" for files you've customized (e.g., `feature_list.json` with your features).
- Choose "overwrite" only for files you want to reset to defaults (e.g., `init.sh`).
- To start completely fresh, delete the existing anchor files first, then run `/anchor`.

---

## 5. `init.sh` exits non-zero

**Symptom:** Running `bash init.sh` produces errors and exits with a non-zero code.

**Cause:** `init.sh` checks for required state files and tools. A missing `feature_list.json`, absent CMake, or failed `cmake configure` will cause it to fail.

**Diagnosis:**
1. Read the stderr output — it tells you exactly which check failed.
2. Check that `feature_list.json` exists (run `/anchor` if not).
3. If C++: check that `cmake` is installed and the CMakeLists.txt is valid.

**Fix:**
- Run `/anchor` first to scaffold missing state files.
- Install missing build tools (cmake, clang-tidy, etc.).
- Fix CMakeLists.txt errors before re-running `init.sh`.

---

## 6. Hook contract tests fail

**Symptom:** Running `bash tests/hook-contracts/<test>.sh` reports FAIL.

**Cause:** Most commonly, the hook script has been modified and produces unexpected output. Less commonly, the test environment differs (missing `python3`, missing `git`).

**Diagnosis:**
1. Run the failing test with verbose output to see what's expected vs actual.
2. Run `bash scripts/validate-anchor.sh` — does the SessionStart smoke test pass?
3. Check that `python3` and `git` are available in your PATH.

**Fix:**
- If you modified a hook, re-run the contract test for that hook.
- If `validate-anchor.sh` also fails, fix the underlying issue first.
- If tools are missing, install them or mark the test as expected-skip.

---

## 7. `validate-manifests.sh` reports version mismatch

**Symptom:** After bumping the version in `plugin.json`, `validate-manifests.sh` reports versions don't match.

**Cause:** Both `plugin.json` and `marketplace.json` must have the same version. Forgetting to update one is a common drift site.

**Fix:**
- Update both files simultaneously: `plugin.json` → `version` and `marketplace.json` → `plugins[0].version`.
- Run `bash scripts/validate-manifests.sh` to confirm sync.
