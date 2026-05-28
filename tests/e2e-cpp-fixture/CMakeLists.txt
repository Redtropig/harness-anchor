# E2E fixture — a small CMake project for verifying full /anchor + /cpp-init + /verify flow.
cmake_minimum_required(VERSION 3.20)
project(e2e_cpp_fixture CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_compile_options(-Wall -Wextra)

add_executable(e2e_app src/main.cpp)
