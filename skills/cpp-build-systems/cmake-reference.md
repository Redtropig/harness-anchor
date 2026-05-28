# CMake Quick Reference

Common patterns harness-anchor expects in `CMakeLists.txt`.

## Minimal modern project

```cmake
cmake_minimum_required(VERSION 3.20)
project(my_project CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_executable(my_app src/main.cpp)
target_compile_options(my_app PRIVATE -Wall -Wextra -Wpedantic)
```

## Library target

```cmake
add_library(my_lib STATIC src/lib.cpp)
target_include_directories(my_lib PUBLIC include)
target_compile_features(my_lib PUBLIC cxx_std_20)
```

## Find a system package

```cmake
find_package(fmt REQUIRED)
target_link_libraries(my_app PRIVATE fmt::fmt)
```

## Tests with GoogleTest (FetchContent)

```cmake
include(FetchContent)
FetchContent_Declare(googletest
    URL https://github.com/google/googletest/archive/v1.14.0.tar.gz)
FetchContent_MakeAvailable(googletest)

enable_testing()
add_executable(my_tests tests/test_main.cpp)
target_link_libraries(my_tests PRIVATE GTest::gtest_main my_lib)
include(GoogleTest)
gtest_discover_tests(my_tests)
```

## Sanitizer build (ASan + UBSan)

```cmake
if(CMAKE_BUILD_TYPE STREQUAL "Asan")
    add_compile_options(-fsanitize=address -fsanitize=undefined -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address -fsanitize=undefined)
endif()
```

Then: `cmake -S . -B .build/asan -DCMAKE_BUILD_TYPE=Asan`.

## Anti-patterns

- ❌ `file(GLOB ...)` for sources — opaque to CMake; sources won't update when files added. Use explicit lists.
- ❌ `include_directories(...)` (global) — use `target_include_directories(<target> PUBLIC|PRIVATE ...)`.
- ❌ `link_libraries(...)` (global) — use `target_link_libraries`.
- ❌ Hard-coding compiler flags inside `if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")` cascades — use generator expressions or `target_compile_options` per-target.

## Useful CLI flags

| Flag | Purpose |
|---|---|
| `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON` | Required for tooling |
| `-DCMAKE_BUILD_TYPE=Debug\|Release\|RelWithDebInfo` | Standard configs |
| `-DCMAKE_VERBOSE_MAKEFILE=ON` | Verbose build output |
| `-G Ninja` | Use Ninja (faster than Make) |
| `--graphviz=out.dot` | Generate dependency graph |
