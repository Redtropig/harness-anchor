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
#
# NO VERSION LADDER (v0.17.0): versioned variants are found by globbing, not by
# walking a hard-coded list of version numbers. Such a list is itself an
# expiring negative assertion — "there is no version newer than N" — and it
# expires silently, reporting NOT_FOUND for a tool that is installed. That is
# the same failure this script was written to prevent, so reintroducing a
# ladder here would be self-defeating.

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

# Highest numerically-suffixed variant of <tool> in <dir>, or nothing.
# Deliberately a glob, NOT a version ladder: a hard-coded list of version
# numbers is itself an expiring negative assertion ("there is nothing newer
# than 22"), which is precisely the class of error this script exists to
# prevent. A ladder would have to be re-edited roughly annually, and the
# release that forgot would recreate the original bug. Do not reintroduce one.
best_versioned() {   # <dir> <tool>
    local dir="$1" tool="$2" p v best="" bestv=-1
    for p in "$dir/$tool"-*; do
        [ -x "$p" ] || continue
        v="${p##*-}"; v="${v%.exe}"
        case "$v" in ''|*[!0-9]*) continue;; esac   # non-numeric suffix is not a version
        if [ "$v" -gt "$bestv" ]; then bestv="$v"; best="$p"; fi
    done
    [ -n "$best" ] && printf '%s' "$best"
}

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

    # 4. Versioned variants (clang-tidy-20, clang-format-19, ...) — on PATH and
    #    in the same known dirs. Highest version wins. Glob-enumerated, never
    #    from a hard-coded ladder; see best_versioned().
    scope="$scope,versioned"
    local d best="" bestv=-1 cand="" candv=""
    # PATH side: $PATH is colon-separated here, including under Git-Bash. Split
    # it ONCE into an array rather than setting IFS around a `for` — the split
    # happens when the `for` is evaluated, so juggling IFS inside the body is
    # both pointless and easy for a later edit to break. This function also uses
    # `IFS='|' read` further down; leaving a modified IFS in scope would corrupt
    # it.
    local -a path_dirs
    IFS=':' read -r -a path_dirs <<< "$PATH"
    for d in "${path_dirs[@]}"; do
        [ -n "$d" ] && [ -d "$d" ] || continue
        cand=$(best_versioned "$d" "$tool")
        if [ -n "$cand" ]; then
            candv="${cand##*-}"; candv="${candv%.exe}"
            if [ "$candv" -gt "$bestv" ]; then bestv="$candv"; best="$cand"; fi
        fi
    done
    # Known install locations side.
    while IFS='|' read -r how dir; do
        [ -n "$dir" ] || continue
        cand=$(best_versioned "$dir" "$tool")
        if [ -n "$cand" ]; then
            candv="${cand##*-}"; candv="${candv%.exe}"
            if [ "$candv" -gt "$bestv" ]; then bestv="$candv"; best="$cand"; fi
        fi
    done <<EOF
$(candidate_dirs)
EOF
    if [ -n "$best" ]; then emit_found "$tool" "$best" "versioned"; return 0; fi

    emit_missing "$tool" "$scope"
}

if [ "$#" -eq 0 ]; then
    printf 'usage: cpp-tool-discovery.sh <tool> [<tool>...]\n' >&2
    exit 0
fi

for t in "$@"; do search_one "$t"; done
exit 0
