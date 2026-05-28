#!/usr/bin/env bash
# cpp-detect.sh — Detect C/C++ project type and emit JSON to stdout.
#
# Usage:
#   bash cpp-detect.sh [--target <dir>]
#
# Output: JSON with build_system, build_file, compile_commands path, tool presence, etc.
# Exit code: always 0 (this is detection, not validation).

set -uo pipefail

TARGET="${1:-}"
if [ "$TARGET" = "--target" ] && [ -n "${2:-}" ]; then
    TARGET="$2"
fi
if [ -z "$TARGET" ]; then
    TARGET="$(pwd)"
fi

cd "$TARGET" 2>/dev/null || { echo '{"error":"cannot cd to target","is_cpp_project":false}'; exit 0; }

# ---- detect build system ----
build_system="unknown"
build_file=""
if   [ -f CMakeLists.txt ]; then build_system="cmake";  build_file="CMakeLists.txt"
elif [ -f meson.build ];    then build_system="meson";  build_file="meson.build"
elif [ -f BUILD.bazel ] || [ -f BUILD ] || [ -f WORKSPACE ] || [ -f MODULE.bazel ]; then
    build_system="bazel"
    for f in BUILD.bazel BUILD MODULE.bazel WORKSPACE; do
        if [ -f "$f" ]; then build_file="$f"; break; fi
    done
elif [ -f Makefile ] || [ -f makefile ] || [ -f GNUmakefile ]; then
    build_system="make"
    for f in Makefile makefile GNUmakefile; do
        if [ -f "$f" ]; then build_file="$f"; break; fi
    done
fi

# ---- detect source files (light scan, top-level + src/) ----
has_cpp_sources=false
shopt -s nullglob 2>/dev/null || true
for d in . src include lib; do
    [ -d "$d" ] || continue
    matches=$(find "$d" -maxdepth 3 \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.cxx' -o -name '*.h' -o -name '*.hpp' \) 2>/dev/null | head -1)
    if [ -n "$matches" ]; then
        has_cpp_sources=true
        break
    fi
done

# ---- if no build system AND no sources, not a cpp project ----
if [ "$build_system" = "unknown" ] && [ "$has_cpp_sources" = "false" ]; then
    printf '{"is_cpp_project":false,"build_system":"unknown","build_file":null,"has_cpp_sources":false}\n'
    exit 0
fi

# ---- find compile_commands.json ----
compile_commands_path="null"
for candidate in compile_commands.json .build/compile_commands.json build/compile_commands.json out/compile_commands.json; do
    if [ -f "$candidate" ]; then
        compile_commands_path="\"$candidate\""
        break
    fi
done

# ---- detect config files ----
has_clang_format=false; [ -f .clang-format ] && has_clang_format=true
has_clang_tidy=false;   [ -f .clang-tidy ]   && has_clang_tidy=true

# ---- guess test framework (heuristic) ----
test_framework="unknown"
if grep -rq --include='CMakeLists.txt' --include='*.cmake' 'GoogleTest\|find_package(GTest' . 2>/dev/null; then
    test_framework="gtest"
elif grep -rq --include='*.cpp' --include='*.cc' '#include "catch2' 2>/dev/null; then
    test_framework="catch2"
elif grep -rq --include='*.cpp' --include='*.cc' '#include <doctest' 2>/dev/null; then
    test_framework="doctest"
fi

# ---- guess C++ standard (CMake-only heuristic) ----
standard="unknown"
if [ "$build_system" = "cmake" ] && [ -f CMakeLists.txt ]; then
    std_match=$(grep -oE 'CXX_STANDARD[[:space:]]+(11|14|17|20|23|26)' CMakeLists.txt 2>/dev/null | head -1 | awk '{print $NF}')
    if [ -n "$std_match" ]; then
        standard="c++$std_match"
    fi
fi

# ---- emit JSON ----
[ -z "$build_file" ] && build_file_json="null" || build_file_json="\"$build_file\""

cat <<EOF
{
  "is_cpp_project": true,
  "build_system": "$build_system",
  "build_file": $build_file_json,
  "compile_commands": $compile_commands_path,
  "has_clang_format": $has_clang_format,
  "has_clang_tidy": $has_clang_tidy,
  "has_cpp_sources": $has_cpp_sources,
  "test_framework": "$test_framework",
  "standard": "$standard"
}
EOF

exit 0
