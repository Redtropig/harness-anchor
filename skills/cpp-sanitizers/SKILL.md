---
name: cpp-sanitizers
description: Use in C/C++ projects when debugging crashes, hangs, undefined behavior, data races, or memory errors. ASan/UBSan/TSan are runtime checkers — they catch what static analysis misses. Build sanitizer config separately; don't mix with release config.
---

# C/C++ Sanitizers — Runtime Bug Catchers

Sanitizers are compiler-instrumented runtime checks. They catch what static analysis can't (path-sensitive errors, race conditions, memory errors discovered at runtime). They run your normal tests under instrumentation; failures abort with a precise report.

| Sanitizer | What it catches | Slowdown |
|---|---|---|
| **ASan** (Address) | Use-after-free, heap/stack overflow, leaks | 2-3x |
| **UBSan** (UB) | Signed overflow, null deref, misaligned, OOB shift, ... | ~1.1x |
| **TSan** (Thread) | Data races, deadlocks | 5-10x |
| **MSan** (Memory) | Use of uninitialized memory | 3x (Linux only, Clang only) |

Note: ASan + UBSan are combinable. TSan is **mutually exclusive** with ASan/MSan.

## Prerequisites

- Clang or recent GCC (`-fsanitize=` family supported since GCC 4.8 / Clang 3.1+)
- A separate sanitizer build directory (don't mix configs)
- Tests that actually exercise the suspect code paths

## Standard build setup

### ASan + UBSan (most useful default)

```bash
# CMake
cmake -S . -B .build/asan \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -g -O1" \
    -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined"
cmake --build .build/asan
ctest --test-dir .build/asan --output-on-failure
```

```bash
# Meson
meson setup builddir-asan -Db_sanitize=address,undefined -Db_lundef=false
meson test -C builddir-asan
```

### TSan (separately)

```bash
cmake -S . -B .build/tsan \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_CXX_FLAGS="-fsanitize=thread -fno-omit-frame-pointer -g -O1" \
    -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=thread"
cmake --build .build/tsan
```

### valgrind (Linux, when sanitizers unavailable)

```bash
valgrind --tool=memcheck --leak-check=full ./your_test_binary
```

slower than ASan (10-50x) but works without recompiling.

## Reading sanitizer output

ASan example:
```
==12345==ERROR: AddressSanitizer: heap-use-after-free on address 0x60200000001c
READ of size 4 at 0x60200000001c thread T0
    #0 main main.cpp:42
    #1 ...
freed by thread T0 here:
    #0 ...
    #1 main.cpp:30
previously allocated by thread T0 here:
    #0 ...
    #1 main.cpp:25
```

Reading order: **error class → access pattern → freed/allocated stack traces**. The use-after-free trio (allocated → freed → used) almost always tells you the bug.

## Suppressions

For known bugs in third-party code, use a suppression file (`asan-suppressions.txt`):

```
leak:libfontconfig
race:third_party/lib_with_known_race
```

Run: `ASAN_OPTIONS=suppressions=asan-suppressions.txt ./your_test`

## Anti-patterns

- ❌ Running sanitizers in production builds — they're for testing only
- ❌ Disabling a sanitizer check globally to silence a warning — fix the bug
- ❌ Mixing ASan and TSan in one build — they conflict
- ❌ Treating UBSan warnings as informational — UB is real, fix it

## When to invoke

- Test fails intermittently → likely a race (TSan)
- Crash with cryptic memory address → likely UAF or buffer overflow (ASan)
- Test passes but behavior is weird → maybe uninitialized read (MSan, or UBSan)
- Before any release / merge to main → run full ASan+UBSan suite

## See `ub-failure-patterns.md` for common UBSan signatures and their fixes.
