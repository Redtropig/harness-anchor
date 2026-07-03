---
description: Initialize C/C++ project-specific harness files (.clang-format, .clang-tidy, sanitizer build, init.sh tuned per build system). Run AFTER /anchor.
allowed-tools: Read, Write, Bash, AskUserQuestion
---

# /cpp-init

Add C/C++-specific config files to a project already anchored via `/anchor`. Tunes `init.sh` for the detected build system; drops `.clang-format`, `.clang-tidy`, and a sanitizer build script.

## Steps

1. **Verify `/anchor` already ran** — check `feature_list.json` exists. If not, refuse and tell the user to run `/anchor` first.

2. **Detect project type**:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/cpp-detect.sh
   ```

   Parse the JSON. If `is_cpp_project: false`, refuse: this command is C/C++ only.

3. **Replace `init.sh`** with the build-system-specific template:

   | Detected build system | Template |
   |---|---|
   | `cmake` | `templates/cpp/cmake-init.sh.tpl` → `init.sh` |
   | `meson` | `templates/cpp/meson-init.sh.tpl` → `init.sh` |
   | `make` / `bazel` / `unknown` | Keep generic `init.sh`; warn that auto-init.sh isn't customized for this build system yet |

   Use AskUserQuestion before overwriting — never silently replace user-customized init.sh.

4. **Drop `.clang-format` and `.clang-tidy`** from `templates/cpp/*.tpl` (skip if present and non-empty — ask user).

5. **Drop `scripts/sanitizer-build.sh`** from `templates/cpp/sanitizer-build.sh.tpl` if the project is CMake (other build systems: ask user, sanitizer setup is build-system-specific).

6. **Drop `scripts/lint.sh`** from `templates/cpp/lint.sh.tpl` (any C/C++ project —
   clang-tidy is build-system-agnostic given `compile_commands.json`). Same skip-if-present
   ask policy. This is the sysroot-correct lint entry point (macOS Homebrew clang-tidy
   fails without it — see `cpp-static-analysis`).

7. **chmod +x** the shell scripts written.

8. **Print next-steps**:

   ```
   ✓ /cpp-init complete:
     - init.sh tuned for <build system>
     - .clang-format applied (LLVM base + 4-space indent + 100 col)
     - .clang-tidy applied (bugprone/cert/clang-analyzer/cppcoreguidelines baseline)
     - scripts/lint.sh applied (sysroot-correct clang-tidy entry point)
     - scripts/sanitizer-build.sh available for ASan+UBSan runs

   Next:
     1. Run `bash init.sh` — should succeed if your project is well-configured
     2. Review .clang-tidy and disable any checks too noisy for this codebase
     3. Run `bash scripts/lint.sh` for a clang-tidy pass (sysroot handled)
     4. Run `clang-format --dry-run -Werror $(git ls-files '*.cpp' '*.h')` to see what would change
     5. Optionally run scripts/sanitizer-build.sh to do a full ASan+UBSan pass
   ```

## Overwrite policy (hard rule)

The same policy as `/anchor`: any existing non-empty file gets AskUserQuestion[overwrite/skip/diff]. Never silently overwrite. Especially:

- A user-customized `init.sh` reflects work; don't lose it
- A `.clang-format` already in the repo encodes team taste; ask before changing
- A `.clang-tidy` already there may suppress noisy checks; ask before changing

## When NOT to invoke

- Project is not C/C++ → cpp-detect.sh returns `is_cpp_project: false`
- Build system is `unknown` with no `.c/.cpp/.h` files anywhere → strongly suggest the user pick a build system first

## Related

- `cpp-build-systems` skill — explains what each command does
- `cpp-static-analysis` skill — explains what `.clang-tidy` config controls
- `cpp-formatting` skill — explains `.clang-format` choices
- `/anchor` — the generic scaffold this layers on top of
