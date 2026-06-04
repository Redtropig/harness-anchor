# non-cpp-fixture

Negative fixture for `scripts/cpp-detect.sh`: a project with **no** C/C++ build
system and **no** C/C++ sources. `cpp-detect.sh` must emit
`{"is_cpp_project": false, ...}` for this directory.

This guards the gate behind design invariant #5 — the C/C++ skills/commands
must stay dormant in non-C/C++ projects. The four positive fixtures
(`cmake/meson/make/bazel-fixture`) cover the detect-true paths; this covers the
detect-false path.
