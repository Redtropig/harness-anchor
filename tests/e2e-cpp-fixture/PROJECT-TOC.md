# PROJECT TOC

> One-line index of every git-tracked source file.

## Files

- `CMakeLists.txt` — CMake build configuration with gtest via FetchContent
- `src/main.cpp` — entry point, parses CLI args, initializes Engine
- `src/engine.cpp` — Engine implementation, owns lifecycle and state
- `include/engine.h` — Engine class interface, RAII over runtime state
- `tests/test_engine.cpp` — gtest unit tests for Engine class
- `feature_list.json` — scope boundary with 3 features (planned/in-progress/pass)
- `AGENTS.md` — project operating manual
- `init.sh` — health check script (cmake configure + state file presence)
- `.clang-format` — LLVM-based C++ formatting config
- `.clang-tidy` — clang-tidy checks (bugprone + clang-analyzer)

## Decisions

- 2026-05-28: Use gtest via FetchContent for portable test infrastructure
