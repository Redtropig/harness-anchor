# clang-tidy vs cppcheck vs IWYU — When to Use Which

## Side-by-side

| Concern | clang-tidy | cppcheck | IWYU |
|---|---|---|---|
| Speed | Slow (full AST) | Fast | Slow |
| Setup | Needs compile_commands | Standalone | Needs compile_commands |
| Bug detection | Excellent (clang-analyzer + bugprone) | Good (own engine) | None (focused on includes) |
| Style | Excellent (readability-*) | Limited | None |
| Modernization | modernize-* | None | None |
| Include hygiene | misc-include-cleaner | None | **Primary purpose** |
| False positive rate | Moderate | Low-Moderate | High (review carefully) |
| Auto-fix | `-fix` flag (be careful!) | None | iwyu_fix_includes.py |

## Recommended workflow

1. **On every edit** → clang-tidy (incremental, via PostToolUse hook)
2. **Before claiming pass** → clang-tidy full + cppcheck second-opinion *(C projects: also `gcc -fanalyzer`)*
3. **Quarterly / before release** → IWYU pass + clang-tidy modernize-*

## Quick decisions

- "Is my code style-correct?" → clang-tidy
- "Did I leak memory?" → clang-tidy clang-analyzer-* + cppcheck
- "Is my include set tight?" → IWYU
- "Did I use a banned API?" → clang-tidy cert-* / cppcoreguidelines-*
- "Is this loop slow?" → clang-tidy performance-*

## Why not just one tool?

Each has blind spots:

- clang-tidy misses some leak patterns cppcheck catches (different engines)
- cppcheck doesn't understand modern templates as well as clang-tidy
- Neither focuses on include hygiene like IWYU

In a serious project, all three should be in CI. In hobby projects, clang-tidy alone is 80% of the value.

## Beyond the big three

Two more engines, for when the three above aren't enough:

- **Clang Static Analyzer** — already on via clang-tidy's `clang-analyzer-*` (per-TU). Use
  `scan-build` only for a whole-build pass with HTML path reports, or when you can't produce
  `compile_commands.json` (scan-build wraps the build instead).
- **GCC `-fanalyzer`** (**C only** — not C++) — a different engine; a free second opinion on
  C builds (double-free, UAF, leaks, taint). For C++ it adds nothing; stick with the above.
