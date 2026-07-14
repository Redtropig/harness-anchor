---
description: Initialize C/C++ project-specific harness files (.clang-format, .clang-tidy, sanitizer build, init.sh tuned per build system). Run AFTER /anchor.
allowed-tools: Read, Write, Bash, AskUserQuestion
---

# /cpp-init

Add the C/C++ config layer to a project already anchored via `/anchor`.
The mechanical work is `scripts/scaffold.sh --cpp` — same conflict protocol
as `/anchor`, C/C++ template map (init.sh per build system, `.clang-format`,
`.clang-tidy`, `scripts/lint.sh`, and `scripts/sanitizer-build.sh` on CMake).

## Steps

1. **Run the C/C++ scaffold:**

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.sh --target "$(pwd)" --cpp
   ```

   Refusals (surface the message, suggest the fix, stop):
   - exit 4 — not anchored: run `/anchor` first.
   - exit 3 — not a C/C++ project: this command does not apply.

2. **Resolve conflicts** exactly as in `/anchor` step 3 — AskUserQuestion
   `[Overwrite / Skip / Show diff]` per conflict, `--render <file>` (with
   `--cpp`) for the diff, then one
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.sh --target "$(pwd)" --cpp --overwrite <f1,f2>`
   call for the approved set. A user-customized `init.sh`, `.clang-format`,
   or `.clang-tidy` encodes work/taste — that is exactly why they land in
   conflicts instead of being replaced.

3. **Print the script's next-steps block verbatim.** If the report carries a
   `note:` line (make/bazel/unknown build system — no canned init.sh), relay
   it and point at the `cpp-build-systems` skill.

## Related

- `cpp-build-systems` / `cpp-static-analysis` / `cpp-formatting` skills —
  what each dropped config controls.
- `/anchor` — the generic scaffold this layers on top of.
- `/sanitize` — uses `scripts/sanitizer-build.sh` dropped here.
