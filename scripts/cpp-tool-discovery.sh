#!/usr/bin/env bash
# cpp-tool-discovery.sh — Answer "does this C/C++ tool actually exist here?" by
# searching PATH *and* this platform's known install locations.
#
# Usage:
#   bash cpp-tool-discovery.sh clang-tidy [clang-format cppcheck ninja ...]
#
# Output (stdout, one line per tool, TAB-separated):
#   FOUND<TAB><tool><TAB><abs-path><TAB><how>
#   NOT_FOUND<TAB><tool><TAB>searched:<comma-list>
# <how> is a closed set: path|vs-llvm|vs-cmake|xcrun|brew|llvm-dir|versioned
# Exit code: ALWAYS 0 — discovery results live in stdout, never in $?. Callers
# must not need `|| true`, and `set -e` callers must not abort on a missing tool.
#
# WHY THIS EXISTS (v0.16.0): `command -v` / `where` only sees PATH. On Windows the
# VS-bundled LLVM and Ninja live inside the VS install and only join PATH after
# vcvars64.bat; on macOS Homebrew's llvm is keg-only. An empty `command -v`
# therefore proves NOTHING about installation. A real agent run concluded "no
# clang-tidy/clang-format on this machine" from an empty `where`, wrote it into
# AGENTS.md, and silently skipped three capabilities for the rest of the session.
#
# RESIDUAL BLIND SPOT: a tool installed in a genuinely non-standard location
# (portable unzip, user-chosen prefix) still reports NOT_FOUND. That is exactly
# why the NOT_FOUND line ENUMERATES what was searched — "not found" must always
# carry its own scope, so a reader can see where the search stopped.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/portable.sh" 2>/dev/null || true
if command -v ha_platform_init >/dev/null 2>&1; then ha_platform_init; fi
: "${HA_OS:=linux}"

# Fallback if portable.sh was unavailable — keep the script self-sufficient.
if ! command -v ha_normalize_path >/dev/null 2>&1; then
    ha_normalize_path() { printf '%s' "${1//\\//}"; }
fi

emit_found()   { printf 'FOUND\t%s\t%s\t%s\n' "$1" "$2" "$3"; }
emit_missing() { printf 'NOT_FOUND\t%s\tsearched:%s\n' "$1" "$2"; }

# Echo the VS installation root (forward-slashed), or nothing.
vs_root() {
    local vswhere out
    for vswhere in \
        "/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe" \
        "/c/Program Files/Microsoft Visual Studio/Installer/vswhere.exe"
    do
        [ -x "$vswhere" ] || continue
        out=$("$vswhere" -latest -products '*' -property installationPath 2>/dev/null | tr -d '\r' | head -1)
        [ -n "$out" ] && { ha_normalize_path "$out"; return 0; }
    done
    [ -n "${VSINSTALLDIR:-}" ] && ha_normalize_path "$VSINSTALLDIR"
}

# candidate_dirs <how-label-var-name-unused> — prints "<how>|<dir>" lines for HA_OS.
candidate_dirs() {
    local root
    case "$HA_OS" in
      windows)
        root=$(vs_root)
        if [ -n "$root" ]; then
            root="${root%/}"
            printf 'vs-llvm|%s\n'  "$root/VC/Tools/Llvm/x64/bin"
            printf 'vs-llvm|%s\n'  "$root/VC/Tools/Llvm/bin"
            printf 'vs-cmake|%s\n' "$root/Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja"
            printf 'vs-cmake|%s\n' "$root/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin"
        fi
        ;;
      darwin)
        if [ -n "${HOMEBREW_PREFIX:-}" ]; then printf 'brew|%s\n' "$HOMEBREW_PREFIX/opt/llvm/bin"; fi
        printf 'brew|%s\n' "/opt/homebrew/opt/llvm/bin"
        printf 'brew|%s\n' "/usr/local/opt/llvm/bin"
        ;;
      linux)
        local d
        for d in /usr/lib/llvm-*/bin /usr/lib64/llvm*/bin; do
            [ -d "$d" ] && printf 'llvm-dir|%s\n' "$d"
        done
        ;;
    esac
}

search_one() {
    local tool="$1" scope="PATH" p how dir

    # 1. PATH
    p=$(command -v "$tool" 2>/dev/null || true)
    if [ -n "$p" ]; then emit_found "$tool" "$p" "path"; return 0; fi

    # 2. macOS: xcrun knows about the toolchain even when PATH does not.
    if [ "$HA_OS" = "darwin" ]; then
        scope="$scope,xcrun"
        p=$(xcrun -f "$tool" 2>/dev/null || true)
        if [ -n "$p" ] && [ -x "$p" ]; then emit_found "$tool" "$p" "xcrun"; return 0; fi
    fi

    # 3. Platform-known install locations.
    while IFS='|' read -r how dir; do
        [ -n "$dir" ] || continue
        case ",$scope," in *",$how,"*) :;; *) scope="$scope,$how";; esac
        for p in "$dir/$tool" "$dir/$tool.exe"; do
            if [ -x "$p" ]; then emit_found "$tool" "$p" "$how"; return 0; fi
        done
    done <<EOF
$(candidate_dirs)
EOF

    # 4. Versioned variants (clang-tidy-20, clang-format-19, ...) on PATH and
    #    in the same known dirs. Newest first.
    scope="$scope,versioned"
    local v
    for v in 22 21 20 19 18 17 16 15 14; do
        p=$(command -v "$tool-$v" 2>/dev/null || true)
        if [ -n "$p" ]; then emit_found "$tool" "$p" "versioned"; return 0; fi
    done
    while IFS='|' read -r how dir; do
        [ -n "$dir" ] || continue
        for v in 22 21 20 19 18 17 16 15 14; do
            for p in "$dir/$tool-$v" "$dir/$tool-$v.exe"; do
                if [ -x "$p" ]; then emit_found "$tool" "$p" "versioned"; return 0; fi
            done
        done
    done <<EOF
$(candidate_dirs)
EOF

    emit_missing "$tool" "$scope"
}

if [ "$#" -eq 0 ]; then
    printf 'usage: cpp-tool-discovery.sh <tool> [<tool>...]\n' >&2
    exit 0
fi

for t in "$@"; do search_one "$t"; done
exit 0
