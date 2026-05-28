---
name: cpp-static-analysis
description: Use in C/C++ projects when reviewing changed code, before claiming a feature done, or when investigating bugs. Runs clang-tidy / cppcheck / include-what-you-use (IWYU). Requires compile_commands.json. Surface warnings on changed lines only — don't dump the world.
---

# C/C++ Static Analysis

Static analysis catches an enormous class of bugs at zero runtime cost: null derefs, leaks, dangling refs, integer overflow, missing initializers, unused includes, banned APIs.

Three tools cover most needs:

| Tool | What it catches | Cost |
|---|---|---|
| **clang-tidy** | Style + correctness + modernize + bugprone | Heavy (uses full AST) |
| **cppcheck** | Quick correctness, leaks, off-by-one | Light (own parser) |
| **IWYU** | Missing/superfluous `#include` | Heavy (compile-driven) |

## Prerequisites (hard)

- `compile_commands.json` exists at project root or symlinked
- The tools are installed (`clang-tidy --version`, `cppcheck --version`, `include-what-you-use --version`)
- A `.clang-tidy` config exists at project root (use template if not)

If any prerequisite is missing, **say so explicitly** instead of pretending to analyze:

> "Cannot run clang-tidy because compile_commands.json is missing. Generate it via `cmake -S . -B .build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON` then symlink to root."

## clang-tidy — daily-driver

### Incremental usage (preferred)

After an Edit/Write to a .c/.cpp/.h file:

```bash
clang-tidy -p .build --quiet path/to/changed_file.cpp
```

- `-p .build` points at compile_commands.json's directory
- `--quiet` suppresses progress noise
- Returns 0 if clean, non-zero if warnings

For changed lines only (large existing codebases), use [`clang-tidy-diff.py`](https://github.com/llvm/llvm-project/blob/main/clang-tools-extra/clang-tidy/tool/clang-tidy-diff.py):

```bash
git diff -U0 main | clang-tidy-diff.py -p1 -path .build
```

### Full-project scan

```bash
run-clang-tidy -p .build -quiet -j$(nproc) > clang-tidy-report.txt 2>&1
```

Use sparingly — slow on large codebases.

### Common check categories

| Category | What it covers | Recommendation |
|---|---|---|
| `bugprone-*` | Likely bugs | Always on |
| `cert-*` | CERT secure coding | Often on |
| `clang-analyzer-*` | Path-sensitive analysis | Always on |
| `cppcoreguidelines-*` | C++ Core Guidelines | Selective |
| `modernize-*` | Convert to modern idioms | Off in legacy code, on in greenfield |
| `performance-*` | Perf antipatterns | Selective |
| `readability-*` | Style | Selective |

The template `.clang-tidy` enables a safe baseline; tune per project.

## cppcheck — second opinion

```bash
cppcheck --enable=warning,style,performance,portability --suppress=missingIncludeSystem -j$(nproc) src/ 2>&1
```

cppcheck catches things clang-tidy misses (and vice versa). Run before claiming a feature done.

## IWYU — keep includes honest

```bash
include-what-you-use -Xiwyu --no_fwd_decls path/to/file.cpp 2>&1
```

Reports: which includes are unused, which symbols come from indirect includes (should be added). Use `iwyu_tool.py` for project-wide.

Note: IWYU has false positives; review suggestions, don't auto-apply.

## Warn-only philosophy

The PostToolUse hook surfaces clang-tidy warnings as `additionalContext`. You see them on the next turn. You decide whether to fix each one — there are legitimate reasons to suppress (e.g., `// NOLINT(specific-check)` with a comment).

Anti-patterns:
- Silencing warnings with broad disables (`// NOLINTBEGIN/NOLINTEND` on hundreds of lines)
- Adding the suppressed check to `.clang-tidy` to "make it stop"
- Ignoring warnings indefinitely

If a warning is wrong (false positive), file a one-line `// NOLINT(check-name) — reason` with explanation. Be specific.

## When to defer

If a warning is in code you didn't change (legacy area) and not a regression risk, defer it: note in `progress.md`, don't fix in this session. Scope discipline.

## Templates

- `.clang-tidy` baseline config: `templates/cpp/.clang-tidy.tpl` (copied by `/cpp-init`)
- See `tool-comparison.md` for clang-tidy vs cppcheck vs IWYU side-by-side decisions.
