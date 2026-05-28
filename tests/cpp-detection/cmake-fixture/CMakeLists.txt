# Minimal CMake fixture for harness-anchor cpp-detect.sh tests.
cmake_minimum_required(VERSION 3.20)
project(cmake_fixture CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_executable(app src/main.cpp)
