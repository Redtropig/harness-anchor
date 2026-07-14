#!/usr/bin/env bash
# session-end-precheck.sh — One-call fact gathering for /session-end.
# Replaces the ritual's scattered mechanical steps (active feature, init.sh
# run, archival dry-run, ledger validation, whole-tree scan, TOC structural
# hint) with a single deterministic block. FACTS ONLY — the judgment half of
# /session-end (handoff/progress composition, status flips, archival consent,
# commits) stays with the calling agent.
#
# Usage: session-end-precheck.sh [--target <dir>] [--skip-init]
# Exit 0 always (facts reported); 2 = usage error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="."; SKIP_INIT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --target)
            shift
            [ $# -gt 0 ] && [ -d "${1:-}" ] || { echo "session-end-precheck: --target requires an existing directory" >&2; exit 2; }
            TARGET="$1" ;;
        --skip-init) SKIP_INIT=1 ;;
        *) echo "session-end-precheck: unknown argument '$1'" >&2; exit 2 ;;
    esac
    shift
done

echo "## Session-end pre-check — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# ---- 1. Active feature + counts (python3→node engine, key=value protocol) ----
echo "### Active feature"
FLIST="$TARGET/feature_list.json"
if [ ! -f "$FLIST" ]; then
    echo "(no feature_list.json — un-anchored; suggest /anchor)"
else
    facts=""
    if command -v python3 >/dev/null 2>&1; then
        facts=$(python3 - "$FLIST" <<'PY' 2>/dev/null || true
import json, sys
def clean(s): return str(s).replace("\n", " ").replace("\t", " ")
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(3)
counts = {}
active = None
for f in d.get("features", []):
    s = f.get("status", "unknown")
    counts[s] = counts.get(s, 0) + 1
    if s == "in-progress" and active is None:
        active = f
if active is not None:
    print("active=%s: %s" % (clean(active.get("id", "?")), clean(active.get("name", ""))))
print("counts=planned %d / in-progress %d / pass %d / blocked %d" % (
    counts.get("planned", 0), counts.get("in-progress", 0),
    counts.get("pass", 0), counts.get("blocked", 0)))
PY
)
    fi
    if [ -z "$facts" ] && command -v node >/dev/null 2>&1; then
        facts=$(node -e '
const fs = require("fs");
const clean = s => String(s).replace(/[\n\t]/g, " ");
let d; try { d = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (e) { process.exit(3); }
const counts = {}; let active = null;
for (const f of (d.features || [])) {
    const s = f.status || "unknown";
    counts[s] = (counts[s] || 0) + 1;
    if (s === "in-progress" && active === null) active = f;
}
if (active !== null) console.log("active=" + clean(active.id || "?") + ": " + clean(active.name || ""));
console.log("counts=planned " + (counts["planned"]||0) + " / in-progress " + (counts["in-progress"]||0)
    + " / pass " + (counts["pass"]||0) + " / blocked " + (counts["blocked"]||0));
' "$FLIST" 2>/dev/null || true)
    fi
    if [ -z "$facts" ]; then
        echo "(needs python3 or node)"
    else
        av=$(printf '%s\n' "$facts" | sed -n 's/^active=//p')
        cv=$(printf '%s\n' "$facts" | sed -n 's/^counts=//p')
        if [ -n "$av" ]; then echo "- **${av%%:*}**:${av#*:}"; else echo "- (no in-progress feature)"; fi
        echo "- counts: $cv"
    fi
fi
echo ""

# ---- 2. init.sh under a 60s SIGKILL watchdog ----
echo "### init.sh"
if [ "$SKIP_INIT" -eq 1 ]; then
    echo "- init.sh: SKIPPED (--skip-init)"
elif [ ! -f "$TARGET/init.sh" ]; then
    echo "- init.sh: (no init.sh)"
else
    of=$(mktemp); rf=$(mktemp)
    ( cd "$TARGET" && bash init.sh > "$of" 2>&1; echo $? > "$rf" ) &
    ip=$!
    ( sleep 60; kill -9 "$ip" 2>/dev/null ) >/dev/null 2>&1 &
    wd=$!
    wait "$ip" 2>/dev/null
    kill -9 "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
    if [ ! -s "$rf" ]; then
        echo "- init.sh: TIMEOUT (>60s)"
        tail -5 "$of" 2>/dev/null | sed 's/^/    /'
    else
        irc=$(tr -cd '0-9' < "$rf"); irc="${irc:-1}"
        if [ "$irc" -eq 0 ]; then
            echo "- init.sh: PASS (exit 0)"
        else
            echo "- init.sh: FAIL (exit $irc)"
            tail -5 "$of" 2>/dev/null | sed 's/^/    /'
        fi
    fi
    rm -f "$of" "$rf"
fi
echo ""

# ---- 3. Archival backlog ----
echo "### Archival backlog (state-archive --dry-run)"
if command -v node >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/state-archive.mjs" ]; then
    node "$SCRIPT_DIR/state-archive.mjs" --dry-run --target "$TARGET" 2>&1 || true
else
    echo "archival needs Node — hot files keep working; the SessionStart sentinel keeps reminding"
fi
echo ""

# ---- 4. Ledger validation ----
echo "### Ledger validation (feature-list-validate)"
if [ ! -f "$FLIST" ]; then
    echo "- (no feature_list.json)"
elif command -v node >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/feature-list-validate.mjs" ]; then
    if lv=$(node "$SCRIPT_DIR/feature-list-validate.mjs" "$FLIST" 2>&1); then
        echo "- ledger: OK"
    else
        printf '%s\n' "$lv"
    fi
else
    echo "- ledger: (needs Node)"
fi
echo ""

# ---- 5. Working tree, two columns (state files vs source) ----
echo "### Working tree"
if git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
    porcelain=$(git -C "$TARGET" status --short 2>/dev/null || true)
    state_lines=""; source_lines=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        path="${line#???}"
        path="${path#* -> }"
        base=$(basename "$path")
        case "$base" in
            AGENTS.md|feature_list.json|feature_list.schema.json|progress.md|progress-archive.md|session-handoff.md|PROJECT-TOC.md|golden-rules.md|feature_archive.json|context-budget.md|init.sh)
                state_lines="${state_lines}    ${line}
" ;;
            *)
                source_lines="${source_lines}    ${line}
" ;;
        esac
    done <<EOF
$porcelain
EOF
    echo "state files:"
    if [ -n "$state_lines" ]; then printf '%s' "$state_lines"; else echo "    (clean)"; fi
    echo "source/other:"
    if [ -n "$source_lines" ]; then printf '%s' "$source_lines"; else echo "    (clean)"; fi
else
    echo "(not a git repo)"
fi
echo ""

# ---- 6. TOC structural changes since anchor (A/D/R + untracked, cap 20) ----
echo "### TOC structural changes since anchor"
toc="$TARGET/PROJECT-TOC.md"
anchor=""
if [ -f "$toc" ]; then
    # Same extraction pattern as toc-freshness.sh (kept in sync by tests there).
    anchor=$(grep -oE 'generated-at-commit:[[:space:]]*[A-Za-z0-9_]+' "$toc" 2>/dev/null | head -1 | awk '{print $NF}' || true)
fi
if [ -z "$anchor" ] || [ "$anchor" = "PLACEHOLDER_COMMIT_SHA" ] \
   || ! git -C "$TARGET" cat-file -t "$anchor" >/dev/null 2>&1; then
    echo "(no TOC anchor)"
else
    changes=$( { git -C "$TARGET" diff --name-status -M "$anchor" HEAD 2>/dev/null | awk '$1 ~ /^(A|D|R)/'; \
                 git -C "$TARGET" status --porcelain 2>/dev/null | awk '$1 == "??" { printf "A(untracked)\t%s\n", $2 }'; } || true)
    if [ -z "$changes" ]; then
        echo "(none)"
    else
        total=$(printf '%s\n' "$changes" | grep -c .)
        printf '%s\n' "$changes" | head -20
        [ "$total" -gt 20 ] && echo "(+$((total - 20)) more)"
    fi
fi
exit 0
