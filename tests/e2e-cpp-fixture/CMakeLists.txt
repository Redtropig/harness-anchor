# E2E fixture — portable CMake project for full /anchor → /cpp-init → work → /verify → /session-end lifecycle.
cmake_minimum_required(VERSION 3.20)
project(e2e_cpp_fixture CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_compile_options(-Wall -Wextra)

# Engine as a library — compiled once, linked by BOTH the app and the tests.
# (PUBLIC include dir propagates to every consumer, so they need no extra
#  target_include_directories.)
add_library(engine STATIC src/engine.cpp)
target_include_directories(engine PUBLIC include)

# Main application
add_executable(e2e_app src/main.cpp)
target_link_libraries(e2e_app PRIVATE engine)

# Test executable (gtest via FetchContent)
include(FetchContent)
FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        v1.14.0
)
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

enable_testing()

# Tests link the engine library (so Engine symbols resolve) + gtest_main.
add_executable(e2e_test tests/test_engine.cpp)
target_link_libraries(e2e_test PRIVATE engine GTest::gtest_main)

include(GoogleTest)
gtest_discover_tests(e2e_test)
