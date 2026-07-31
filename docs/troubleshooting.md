# Troubleshooting — harness-anchor

<!-- doc-align: 230abfc99e07fdcda103c63824253346623d7c5d · 2026-07-31 · harness-anchor v0.17.1 -->
> **Aligned with commit** [`230abfc`](https://github.com/Redtropig/harness-anchor/commit/230abfc99e07fdcda103c63824253346623d7c5d) (harness-anchor v0.17.1, 2026-07-31).
> **Scope of that verification:** all 15 entries re-checked against `hooks/` and
> `scripts/` at this commit — every mechanically checkable claim (file paths, script
> invocation forms, emitted message strings, constant names, compile-DB search order,
> manifest field paths, test file names) was run or grepped rather than read. Two were
> stale and are fixed in the same pass: #5 drew a tool-absent conclusion from a
> PATH-only check (pre-0.16.0), and #6 required `python3` specifically (pre-0.13.0).
> Prose advice that is not mechanically checkable — "choose skip for files you
> customized" — was read, not executed. Re-verify and bump this marker when the hooks
> or scripts change; the marker had sat at v0.9.0 through eight releases, including two
> that added entries to this very file.

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

**Related symptom:** instead of warnings you get a single *"clang-tidy could not fully parse
`<file>` … diagnostics suppressed"* notice. That is the hook's signal-fidelity guard: the TU
failed to parse (typically a missing SDK sysroot — macOS + Homebrew clang-tidy), so its
diagnostics would be garbage and are withheld. Fix the toolchain, not the code: run
`bash scripts/lint.sh` (sysroot-aware, dropped by `/cpp-init`), or add
`--extra-arg=-isysroot --extra-arg="$(xcrun --show-sdk-path)"` — see `cpp-static-analysis`
("macOS failure mode").

**Diagnosis:**
1. Check for `compile_commands.json` in project root, `.build/`, `build/`, or `builddir/`.
2. Check CMake was configured with `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`.

**Fix:**
- Re-configure CMake: `cmake -S . -B .build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`
- Or symlink: `ln -s .build/compile_commands.json compile_commands.json`
- Run `/cpp-init` to tune `init.sh` for your build system.

---

## 3. PROJECT-TOC.md reports "stale"

**Symptom:** TOC freshness shows "stale (N file(s) changed since anchor <sha>)".

**Cause:** Tracked content really changed since the TOC was generated — commits past the anchor, or working-tree changes (untracked files count too: the TOC doesn't cover them). `PROJECT-TOC.md` itself is **excluded** from the count, so committing the regenerated TOC does *not* re-stale it — the canonical `/index-project` → `git commit` loop converges to "fresh". (Older versions counted the TOC itself, producing a permanent false-stale; that was fixed.)

**Diagnosis:**
1. Run `bash scripts/toc-freshness.sh <project-dir>` — check the anchor commit vs HEAD.
2. `git diff --name-only <anchor> HEAD -- . ':(exclude)PROJECT-TOC.md'` lists exactly the files driving the staleness.

**Fix:**
- Run `/index-project` (re-anchors at current HEAD), then commit the TOC.
- Mid-feature with only 1–2 changed files, it's fine to ignore the warning until `/session-end` — it's a warning, not a blocker.

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
- Install missing build tools (cmake, clang-tidy, etc.) — but confirm they are
  actually missing first. `init.sh`'s tool checks are `command -v`, i.e. **PATH-only**,
  and the generated `WARN` line says `not on PATH` for exactly that reason: a tool can
  be installed and off PATH (VS-bundled LLVM before `vcvars64.bat`, keg-only Homebrew
  llvm). Resolve it properly before installing a second copy — see entry 15.
- Fix CMakeLists.txt errors before re-running `init.sh`.

---

## 6. Hook contract tests fail

**Symptom:** Running `bash tests/hook-contracts/<test>.sh` reports FAIL.

**Cause:** Most commonly, the hook script has been modified and produces unexpected
output. Less commonly, `git` is unavailable.

**A missing `python3` is not a cause.** Since v0.13.0 the JSON engine chain is
`python3` → `python` → `py -3` → `node` → a narrow pure-bash fallback, and a machine
with none of them gets an honest `SKIP json-validity (no JSON engine on this
machine)` rather than a FAIL. So a FAIL is never about the engine — chasing the
interpreter is the pre-0.13.0 reflex and will waste your time.

**Diagnosis:**
1. Run the failing test with verbose output to see what's expected vs actual.
2. Run `bash scripts/validate-anchor.sh` — does the SessionStart smoke test pass?
3. Check `git` is on PATH. Engine presence only changes SKIP vs OK, never OK vs FAIL.

**Fix:**
- If you modified a hook, re-run the contract test for that hook.
- If `validate-anchor.sh` also fails, fix the underlying issue first.
- Read the SKIP lines before concluding the suite passed: a run that is all-SKIP on
  the JSON assertions checked less than a run that is all-OK.

---

## 7. `validate-manifests.sh` reports version mismatch

**Symptom:** After bumping the version in `plugin.json`, `validate-manifests.sh` reports versions don't match.

**Cause:** Both `plugin.json` and `marketplace.json` must have the same version. Forgetting to update one is a common drift site.

**Fix:**
- Update both files simultaneously: `plugin.json` → `version` and `marketplace.json` → `plugins[0].version`.
- Run `bash scripts/validate-manifests.sh` to confirm sync.

---

## 8. Stop hook: "Hook JSON output validation failed"

**Symptom:** When the agent wraps up, Claude Code reports a Stop-hook JSON validation error (or the wrap-up reminder never appears), pointing at `hooks/stop`.

**Cause:** The **Stop** event accepts only top-level fields — it has **no `hookSpecificOutput` / `additionalContext` channel** (unlike SessionStart, PostToolUse, and UserPromptSubmit). harness-anchor before v0.3.2 emitted `hookSpecificOutput`, which the Stop schema rejects.

**Fix:**
- Upgrade to **v0.3.2+**: `hooks/stop` now emits a non-blocking `systemMessage` (warn-only — never `decision: "block"` or `stopReason`, per design invariant #1).
- Verify your copy: `bash tests/hook-contracts/stop-wrap-up.sh` should report `STATUS: PASSED`. As of v0.3.2 that test asserts the full Stop output schema, not just JSON validity — so it catches this class of regression.

## 9. Windows: banner shows `harness-anchor vunknown` (pre-0.13.0) or ledger lines degraded

**Symptom:** SessionStart banner reports `vunknown`, `Project type: generic` on a C++
project, or `Active feature: (needs python3 or node)`.

**Diagnosis:** No working JSON engine. Windows Python installs `python.exe`/`py.exe`
(no `python3`); the Store's `python.exe` stub exists but cannot run. From 0.13.0 the
engine chain tries python3 → python → py -3 → node, and plugin-controlled formats
(version, cpp-detect) parse even with zero engines — only feature-ledger parsing
still needs a real engine.

**Fix:** Install Python (any launcher name) or Node.js. Verify: `python -c "print(1)"`
or `node -e "console.log(1)"` in Git Bash.

## 10. Windows: `$'\r': command not found` when running scripts manually

**Symptom:** Running a repo script by hand fails with `\r` errors.

**Diagnosis:** The checkout predates the 0.13.0 `.gitattributes` eol rules (CRLF
working tree), or the file lost its attribute coverage.

**Fix:** One-time re-smudge: delete the affected files, then `git checkout -- .`.
Verify: `git ls-files --eol -- hooks/session-start` shows `w/lf`. `tests/windows-compat.sh`
guards the attribute coverage.

## 11. Windows: `timeout`/`find`/`sort` behave bizarrely in your own scripts

**Symptom:** `timeout 5 cmd` complains about arguments; `find -mmin` errors; sort
order is wrong — but the plugin's hooks are fine.

**Diagnosis:** `C:\Windows\System32` ships incompatible same-name binaries. Hooks
shield themselves (`ha_platform_init` prepends `/usr/bin`), but scripts you run
outside the hooks inherit your own PATH.

**Fix:** In your scripts, source `${CLAUDE_PLUGIN_ROOT}/scripts/lib/portable.sh` and
call `ha_platform_init`, or put Git's `/usr/bin` first on PATH yourself.

## 12. Platform content not injected / injected on the wrong platform

**Symptom:** An `<!-- os-<name> -->` region of the meta-skill never appears in the
SessionStart context, or appears on the wrong OS.

**Diagnosis:** A region is kept only when `<name>` equals the runtime `HA_OS`
(`windows` | `darwin` | `linux`). Everything else — typos, names outside the
taxonomy, a pre-set `HA_OS` override in the environment — is dropped silently
(fail-slim: an unknown name never fattens the injection).

**Fix:** Check the runtime value and overrides:
`bash -c '. scripts/lib/portable.sh; ha_platform_init; echo $HA_OS'` and
`env | grep '^HA_OS='`. `scripts/validate-anchor.sh` ([7/12]) rejects
malformed or off-taxonomy markers at authoring time.

## 13. Pulse nudges: what they mean, how to tune or silence them

Since v0.15.0 the PostToolUse hook watches every tool call (the "pulse"):
`Pulse: '<tool>' called 3x with identical input` / `failed 3x in a row` /
`Context is filling` / `Context is heavily filled` / `Pulse checkpoint: ...`.
All warn-only additionalContext — nothing is ever blocked.

State lives in `.harness-anchor/pulse-<session>[-<agent>].tsv` (+ one-shot
markers; subagent streams get their own window via `agent_id`) inside
the anchored project — runtime-only, gitignored. Silence is NOT proof of health:
only exact-input repeats, prefix-detectable errors, transcript byte watermarks,
and the cadence checkpoint are observed (full blind-spot list in the hook header).

Tuning: constants at the top of `hooks/post-tool-use` — `PULSE_DUP_N`,
`PULSE_ERR_N`, `PULSE_COOLDOWN`, `PULSE_SELFCHECK_EVERY` (env-overridable),
`FLUSH_THRESHOLD_BYTES`, `RESET_THRESHOLD_BYTES`. Reset a session's pulse state:
delete `.harness-anchor/pulse-<session>.*` and the session's
`flush-warned-*` / `reset-advised-*` markers. A misfire costs one context line;
a persistently misbehaving detector is a bug — report it rather than hand-patch
the window file.

## 14. `/gc` doc-drift: empty, `PARTIAL`, or hundreds of rows about one word

**Symptom:** The drift report's doc-drift section says nothing at all; or it lists
dozens of rows keyed on a common word (`read`, `file`, `check`); or it says results
are `PARTIAL`.

**Diagnosis:** `scripts/doc-drift-scan.sh` puts the candidate list on **stdout** and
its *coverage* on **stderr**, because empty stdout has several meanings that must not
be confused. Read stderr first:

| stderr line | Meaning |
|---|---|
| `skipped — <reason>` | **No scan ran.** Unreadable target, not a git repo, no usable base ref, no tracked `*.md`, no changed file in a scanned language (`SCAN_PATHSPEC` is a whitelist — a language off it contributes zero symbols), no symbol extracted from the files that did change, or every extracted symbol below the length floor. |
| `not searched — <tokens>` | Those tokens were never looked for: under 3 characters, where case-insensitive prefix matching makes every row undecidable. |
| `symbol set truncated to N of M — results are PARTIAL` | Only `N` symbols were searched. |
| `per-symbol cap N hit by <sym(count)>…` | Those symbols show a first-`N` sample; the parenthesised number is the real total. |
| `candidate list truncated to N of M — results are PARTIAL` | stdout is the first `N` rows of `M`. |
| `scanned N symbol(s) x M doc(s), K candidate(s), S shown` | The coverage statement. `S < K` means you have a sample. |

Only a `scanned …` line with `S == K` and no `PARTIAL` / `not searched` line above
it means "searched, found nothing".

**Fix:** Nothing is broken in most of these cases. Rows are **candidates, not
violations** — matching is deliberately prefix-based (the symbol `cancel` has to
match the prose word "Cancellation"), so a common-word symbol floods by design;
discount its rows as a unit rather than reading each. Run the scan yourself to see
both streams:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/doc-drift-scan.sh" --base <ref> --target "$(pwd)"
```

Tuning lives in named constants in that script: `SCAN_PATHSPEC` (add your
language), `SYM_MINLEN`, `ROW_CAP_PER_SYM`, `ROW_CAP_TOTAL`. Widening `SCAN_PATHSPEC`
is the supported way to extend coverage. Note the standing blind spot: only
call/definition-shaped symbols are extracted, so a changed global, macro, enum
constant, struct field or typedef produces no symbol — and a claim naming no symbol
at all ("the pool is fast") has nothing to key on. A clean section is never "the docs
were verified".

## 15. A tool reports `NOT_FOUND` / "searched …, not found" but you know it is installed

**Symptom:** `/cpp-init`, `cpp-static-analysis` or `cpp-formatting` reports
`NOT_FOUND<TAB>clang-tidy<TAB>searched:PATH,vs-llvm,vs-cmake,versioned` for a tool
that is definitely on the machine.

**Diagnosis:** This is `scripts/cpp-tool-discovery.sh`'s documented residual blind
spot, and the `searched:` list is there precisely so you can see where the search
stopped. It covers PATH, the platform's known install locations (VS-bundled LLVM and
Ninja on Windows, `xcrun` and keg-only Homebrew llvm on macOS, `/usr/lib/llvm-*` on
Linux) and glob-enumerated versioned variants (`clang-tidy-21`, …). A portable unzip
or a user-chosen prefix is in none of those.

**Fix:** Put the directory on PATH — on Windows that usually means running
`vcvars64.bat` in the shell first — then re-run discovery to confirm:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cpp-tool-discovery.sh" clang-tidy clang-format
```

A `FOUND` line's absolute path is usable directly; the tool does not need to be on
PATH for you to invoke it. If it stays `NOT_FOUND`, record that as
`searched <scope>, not found (as of <YYYY-MM-DD>)` — never "not installed" or "not on
this machine". The date is what lets the next session re-check it: `init-verification`
step 6 re-checks inherited negative conclusions at session start, but **only** ones
written in that exact form.
