#!/usr/bin/env bash
# init.sh — Health check for the e2e-cpp-fixture project.
set -euo pipefail

echo "=== e2e-cpp-fixture init check ==="

# Check state files exist
for f in feature_list.json AGENTS.md; do
    if [ -f "$f" ]; then
        echo "  OK  $f present"
    else
        echo "  FAIL  $f missing" >&2
        exit 1
    fi
done

# Check CMake can configure
if command -v cmake >/dev/null 2>&1; then
    cmake -S . -B .build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -Wno-dev 2>/dev/null
    echo "  OK  cmake configure succeeded"
else
    echo "  WARN cmake not found — skipping configure check"
fi

echo "=== init check complete ==="
