#!/usr/bin/env bash
# scaffold.sh — Deterministic template placement for /anchor (generic mode)
# and /cpp-init (--cpp mode).
#
# Safety property (the point of this script): the DEFAULT path has NO
# overwrite branch. An existing non-empty target is physically untouchable
# unless it is named in an explicit --overwrite allowlist — "never silently
# overwrite" enforced as interface shape, not prompt discipline.
# Skip-by-default files (accumulated value; never even listed as conflicts):
# feature_list.json, golden-rules.md. Every other existing non-empty target
# is reported under "conflicts (need decision)" for the caller to resolve
# via AskUserQuestion → a follow-up --overwrite call.
#
# Usage:
#   scaffold.sh [--target <dir>]                     generic scaffold
#   scaffold.sh [--target <dir>] --cpp               C/C++ layer (needs anchor)
#   scaffold.sh [--target <dir>] [--cpp] --overwrite f1,f2   write ONLY these
#   scaffold.sh [--target <dir>] [--cpp] --render <target>   print rendered tpl
#
# Exit: 0 facts reported · 2 usage error · 3 --cpp on non-C/C++ project ·
#       4 --cpp on un-anchored project (no feature_list.json).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TPL_DIR="$PLUGIN_ROOT/templates"

TARGET="."; CPP=0; OVERWRITE=""; RENDER=""
while [ $# -gt 0 ]; do
    case "$1" in
        --target)
            shift
            [ $# -gt 0 ] && [ -d "${1:-}" ] || { echo "scaffold: --target requires an existing directory" >&2; exit 2; }
            TARGET="$1" ;;
        --cpp) CPP=1 ;;
        --overwrite)
            shift
            [ $# -gt 0 ] && [ -n "${1:-}" ] || { echo "scaffold: --overwrite requires a comma-separated file list" >&2; exit 2; }
            OVERWRITE="$1" ;;
        --render)
            shift
            [ $# -gt 0 ] && [ -n "${1:-}" ] || { echo "scaffold: --render requires a target filename" >&2; exit 2; }
            RENDER="$1" ;;
        *) echo "scaffold: unknown argument '$1'" >&2; exit 2 ;;
    esac
    shift
done
if [ -n "$OVERWRITE" ] && [ -n "$RENDER" ]; then
    echo "scaffold: --overwrite and --render are mutually exclusive" >&2; exit 2
fi

# ---- Substitution facts ----
PROJECT_NAME=$(basename "$(cd "$TARGET" && pwd)")
NAME_ESC=$(printf '%s' "$PROJECT_NAME" | sed 's/[&/\]/\\&/g')
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
IS_GIT=0
SHA="uninitialized"
if git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
    IS_GIT=1
    SHA=$(git -C "$TARGET" rev-parse HEAD 2>/dev/null || echo "uninitialized")
fi

render_tpl() { # $1 = template path, $2 = mode (subst|verbatim)
    if [ "$2" = "verbatim" ]; then
        cat "$1"
    else
        sed -e "s/PROJECT_NAME_PLACEHOLDER/${NAME_ESC}/g" \
            -e "s/2026-05-28T00:00:00Z/${NOW}/g" \
            -e "s/PLACEHOLDER_COMMIT_SHA/${SHA}/g" "$1"
    fi
}

# ---- Build the active map: "template-relpath|target-relpath|mode" ----
MODE_NAME="generic"
CPP_WARN=""
if [ "$CPP" -eq 0 ]; then
    MAP="AGENTS.md.tpl|AGENTS.md|subst
golden-rules.md.tpl|golden-rules.md|subst
feature_list.json.tpl|feature_list.json|subst
feature_list.schema.json|feature_list.schema.json|verbatim
init.sh.tpl|init.sh|subst
progress.md.tpl|progress.md|subst
session-handoff.md.tpl|session-handoff.md|subst
PROJECT-TOC.md.tpl|PROJECT-TOC.md|subst
context-budget.md.tpl|context-budget.md|subst"
else
    MODE_NAME="cpp"
    [ -f "$TARGET/feature_list.json" ] || { echo "scaffold: --cpp needs an anchored project (no feature_list.json — run /anchor first)" >&2; exit 4; }
    # cpp-detect emits pretty-printed OR compact JSON depending on its engine
    # path — strip whitespace before matching so both forms parse identically.
    detect=$(bash "$SCRIPT_DIR/cpp-detect.sh" --target "$TARGET" 2>/dev/null | tr -d ' \n\t' || true)
    case "$detect" in
        *'"is_cpp_project":true'*) : ;;
        *) echo "scaffold: --cpp on a non-C/C++ project (cpp-detect: is_cpp_project false)" >&2; exit 3 ;;
    esac
    build_system=$(printf '%s' "$detect" | sed -n 's/.*"build_system":"\([a-z]*\)".*/\1/p')
    MAP="cpp/.clang-format.tpl|.clang-format|verbatim
cpp/.clang-tidy.tpl|.clang-tidy|verbatim
cpp/lint.sh.tpl|scripts/lint.sh|verbatim"
    case "$build_system" in
        cmake)
            MAP="cpp/cmake-init.sh.tpl|init.sh|verbatim
${MAP}
cpp/sanitizer-build.sh.tpl|scripts/sanitizer-build.sh|verbatim" ;;
        meson)
            MAP="cpp/meson-init.sh.tpl|init.sh|verbatim
${MAP}" ;;
        *)
            CPP_WARN="note: build system '${build_system}' has no canned init.sh — existing init.sh kept; sanitizer setup is build-system-specific (see cpp-sanitizers skill)" ;;
    esac
fi

# ---- --render: print one rendered target and exit ----
if [ -n "$RENDER" ]; then
    while IFS='|' read -r tpl tgt mode; do
        [ -n "$tpl" ] || continue
        if [ "$tgt" = "$RENDER" ]; then
            render_tpl "$TPL_DIR/$tpl" "$mode"
            exit 0
        fi
    done <<EOF
$MAP
EOF
    echo "scaffold: '$RENDER' is not a scaffold target in $MODE_NAME mode" >&2
    exit 2
fi

# ---- overwrite allowlist membership ----
in_overwrite() { # $1 = target relpath
    case ",$OVERWRITE," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

written=""; kept=""; conflicts=""
append() { # $1=list-name $2=item — comma-space join without assoc arrays
    eval "cur=\$$1"
    if [ -z "$cur" ]; then eval "$1=\"\$2\""; else eval "$1=\"\$cur, \$2\""; fi
}

while IFS='|' read -r tpl tgt mode; do
    [ -n "$tpl" ] || continue
    src="$TPL_DIR/$tpl"
    dst="$TARGET/$tgt"
    if [ ! -f "$src" ]; then
        append conflicts "$tgt (missing template: $tpl)"
        continue
    fi
    if [ -n "$OVERWRITE" ]; then
        # Overwrite mode: ONLY the allowlisted targets are touched.
        if in_overwrite "$tgt"; then
            case "$tgt" in */*) mkdir -p "$TARGET/$(dirname "$tgt")" ;; esac
            render_tpl "$src" "$mode" > "$dst"
            case "$tgt" in *.sh) chmod +x "$dst" ;; esac
            append written "$tgt"
        fi
        continue
    fi
    if [ -s "$dst" ]; then
        case "$tgt" in
            feature_list.json|golden-rules.md) append kept "$tgt" ;;
            *) append conflicts "$tgt" ;;
        esac
    else
        case "$tgt" in */*) mkdir -p "$TARGET/$(dirname "$tgt")" ;; esac
        render_tpl "$src" "$mode" > "$dst"
        case "$tgt" in *.sh) chmod +x "$dst" ;; esac
        append written "$tgt"
    fi
done <<EOF
$MAP
EOF

echo "## Scaffold report — $PROJECT_NAME ($MODE_NAME)"
if [ "$IS_GIT" -eq 1 ]; then echo "git repo: yes"; else echo "git repo: not-git"; fi
echo "written: ${written:-(none)}"
if [ -n "$OVERWRITE" ]; then
    echo "(overwrite mode: only the allowlisted targets were touched)"
else
    echo "kept (skip-by-default): ${kept:-(none)}"
    echo "conflicts (need decision): ${conflicts:-(none)}"
fi
[ -n "$CPP_WARN" ] && echo "$CPP_WARN"
echo ""
echo "Next:"
if [ "$CPP" -eq 0 ]; then
    cat <<'NEXT'
  1. Edit AGENTS.md "Project Context" and "Verification Commands" sections.
  2. Replace the example entry in feature_list.json with a real first feature.
  3. Run `bash init.sh` to verify it executes.
  4. (Optional) Run /index-project to generate PROJECT-TOC.md from your sources.
  5. (Optional, C/C++ only) Run /cpp-init to add clang-format/.clang-tidy.
  6. Leave golden-rules.md empty for now — add your first rule when a pattern recurs.
NEXT
else
    cat <<'NEXT'
  1. Run `bash init.sh` — should succeed if your project is well-configured.
  2. Review .clang-tidy and disable any checks too noisy for this codebase.
  3. Run `bash scripts/lint.sh` for a sysroot-correct clang-tidy pass.
  4. Run `clang-format --dry-run -Werror $(git ls-files '*.cpp' '*.h')` to preview.
  5. (CMake) scripts/sanitizer-build.sh runs the ASan+UBSan pass — see /sanitize.
NEXT
fi
exit 0
