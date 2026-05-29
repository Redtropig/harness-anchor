# AGENTS.md — e2e-cpp-fixture

## Project
Portable CMake C++20 fixture for testing harness-anchor lifecycle commands.

## Build & Test
```bash
cmake -S . -B .build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build .build
cd .build && ctest --output-on-failure
```

## Architecture
- `src/main.cpp` — CLI entry point
- `src/engine.cpp` / `include/engine.h` — Engine class (RAII)
- `tests/test_engine.cpp` — gtest unit tests

## Conventions
- C++20, clang-format LLVM style
- clang-tidy: bugprone-*, clang-analyzer-*
