---
description: Initialize C/C++ project-specific harness files (.clang-format, .clang-tidy, sanitizer build, init.sh tuned per build system). Run AFTER /anchor.
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion
---

# /cpp-init

Add the C/C++ config layer to a project already anchored via `/anchor`.
The mechanical work is `scripts/scaffold.sh --cpp` — same conflict protocol
as `/anchor`, C/C++ template map (init.sh per build system, `.clang-format`,
`.clang-tidy`, `scripts/lint.sh`, and `scripts/sanitizer-build.sh` on CMake).

## Steps

1. **Resolve the toolchain before scaffolding config for it:**

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/cpp-tool-discovery.sh clang-format clang-tidy
   ```

   Record each `FOUND` line's **`<how>` column as well as its path** — step 5
   branches on `<how>`, so the path alone is not enough. The point is that a
   later session never has to rediscover (and mis-conclude) the tool; whether
   that is best served by a bare name or a recorded path depends on `<how>`.
   A `NOT_FOUND` tool is still worth scaffolding config for (the config is
   version-controlled; the tool may arrive later) — but say so as
   **"searched PATH + \<listed locations\>, not found"**, never "not installed" / "on this machine".

2. **Run the C/C++ scaffold:**

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.sh --target "$(pwd)" --cpp
   ```

   Refusals (surface the message, suggest the fix, stop):
   - exit 4 — not anchored: run `/anchor` first.
   - exit 3 — not a C/C++ project: this command does not apply.

3. **Resolve conflicts** exactly as in `/anchor` step 3 — AskUserQuestion
   `[Overwrite / Skip / Show diff]` per conflict, `--render <file>` (with
   `--cpp`) for the diff, then one
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.sh --target "$(pwd)" --cpp --overwrite <f1,f2>`
   call for the approved set. A user-customized `init.sh`, `.clang-format`,
   or `.clang-tidy` encodes work/taste — that is exactly why they land in
   conflicts instead of being replaced.

4. **Print the script's next-steps block verbatim.** If the report carries a
   `note:` line (make/bazel/unknown build system — no canned init.sh), relay
   it and point at the `cpp-build-systems` skill.

5. **Record the resolved tools in the generated files — portably.**
   `scripts/lint.sh` and `AGENTS.md` are git-tracked and shared, so a bare
   absolute path from step 1 breaks the next machine and CI. Branch on step 1's
   `<how>` column:

   - **`how=path`** — leave the bare tool name as-is. It is already portable;
     substituting `/usr/bin/clang-tidy` would replace something that works
     everywhere with something that works only here, and then commit it.
   - **any other `how`** (`vs-llvm`, `vs-cmake`, `brew`, `llvm-dir`, `versioned`)
     — PATH cannot see the tool on this machine, which is precisely what the
     absolute path is for. Write a PATH-first lookup with the resolved path as
     the fallback, so this machine and a PATH-having one both work:

     ```bash
     CLANG_TIDY="${CLANG_TIDY:-$(command -v clang-tidy || echo '<resolved path from step 1>')}"
     ```

   Fill `AGENTS.md`'s `# Lint:` line with the command a reader should actually
   run. If every tool was `NOT_FOUND`, write `# Lint: none resolved — searched
   PATH + platform install locations; re-run /cpp-init after installing.` — never
   "not installed" / "on this machine" (e.g. not "none configured — not on this machine").

## Related

- `cpp-build-systems` / `cpp-static-analysis` / `cpp-formatting` skills —
  what each dropped config controls.
- `/anchor` — the generic scaffold this layers on top of.
- `/sanitize` — uses `scripts/sanitizer-build.sh` dropped here.
