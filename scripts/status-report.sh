#!/usr/bin/env bash
# status-report.sh — Deterministic /status snapshot: all 7 sections in one run.
# Read-only. The /status command prints this output VERBATIM (thin wrapper).
#
# JSON-derived sections (Active feature / Feature counts / active-feature age)
# use a python3→node engine chain emitting a flat key=value protocol; if BOTH
# engines are unavailable or fail, ONLY those parts degrade to
# "(needs python3 or node)" — every other section still reports.
#
# Usage: status-report.sh [--target <dir>]
# Exit 0 always (facts reported; "not anchored" is a fact, not an error);
# 2 = usage error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Platform layer (v0.13.0): engine discovery (python3→python→py→node) + portable mtime.
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/portable.sh" 2>/dev/null || true
command -v ha_platform_init >/dev/null 2>&1 && ha_platform_init
TARGET="."
while [ $# -gt 0 ]; do
    case "$1" in
        --target)
            shift
            [ $# -gt 0 ] && [ -d "${1:-}" ] || { echo "status-report: --target requires an existing directory" >&2; exit 2; }
            TARGET="$1" ;;
        *) echo "status-report: unknown argument '$1'" >&2; exit 2 ;;
    esac
    shift
done

FLIST="$TARGET/feature_list.json"
if [ ! -f "$FLIST" ]; then
    echo "Project not anchored — run /anchor first"
    exit 0
fi

mtime_of() { if command -v ha_mtime >/dev/null 2>&1; then ha_mtime "$1"; else stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; fi; }
fmt_age() { # $1 = seconds
    if   [ "$1" -lt 7200 ];   then echo "$(( $1 / 60 )) minute(s) ago"
    elif [ "$1" -lt 172800 ]; then echo "$(( $1 / 3600 )) hour(s) ago"
    else                           echo "$(( $1 / 86400 )) day(s) ago"; fi
}
NOW=$(date +%s)

# ---- JSON engine: emit key=value facts from feature_list (+archive) ----
ARCHIVE="$TARGET/feature_archive.json"
[ -f "$ARCHIVE" ] || ARCHIVE=""
facts=""
HA_PY="${HA_PY:-}"
command -v ha_python >/dev/null 2>&1 && HA_PY=$(ha_python || true)
if [ -n "$HA_PY" ] && [ "${HA_JSON_ENGINE:-}" != "node" ]; then
    # shellcheck disable=SC2086
    facts=$($HA_PY - "$FLIST" "$ARCHIVE" <<'PY' 2>/dev/null || true
import json, sys, time, calendar
def clean(s): return str(s).replace("\n", " ").replace("\r", " ").replace("\t", " ")
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(3)
print("project=%s" % clean(d.get("project", "(unnamed)")))
counts = {}
active = None
for f in d.get("features", []):
    s = f.get("status", "unknown")
    counts[s] = counts.get(s, 0) + 1
    if s == "in-progress" and active is None:
        active = f
if active is not None:
    print("active_id=%s" % clean(active.get("id", "?")))
    print("active_name=%s" % clean(active.get("name", "")))
    print("active_desc=%s" % clean(active.get("description", ""))[:120])
    c = active.get("createdAt", "")
    if c:
        try:
            t = calendar.timegm(time.strptime(c, "%Y-%m-%dT%H:%M:%SZ"))
            print("active_created_epoch=%d" % t)
        except Exception:
            pass
for k in ("planned", "in-progress", "pass", "blocked"):
    print("count_%s=%d" % (k.replace("-", "_"), counts.get(k, 0)))
if len(sys.argv) > 2 and sys.argv[2]:
    try:
        a = json.load(open(sys.argv[2]))
        print("archived=%d" % len(a.get("features", [])))
    except Exception:
        print("archived=-1")
PY
)
fi
if [ -z "$facts" ] && command -v node >/dev/null 2>&1; then
    facts=$(node -e '
const fs = require("fs");
const clean = s => String(s).replace(/[\n\r\t]/g, " ");
let d;
try { d = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (e) { process.exit(3); }
console.log("project=" + clean(d.project === undefined ? "(unnamed)" : d.project));
const counts = {};
let active = null;
for (const f of (d.features || [])) {
    const s = f.status === undefined ? "unknown" : f.status;
    counts[s] = (counts[s] || 0) + 1;
    if (s === "in-progress" && active === null) active = f;
}
if (active !== null) {
    console.log("active_id=" + clean(active.id === undefined ? "?" : active.id));
    console.log("active_name=" + clean(active.name || ""));
    console.log("active_desc=" + clean(active.description || "").slice(0, 120));
    const t = Date.parse(active.createdAt || "");
    if (!isNaN(t)) console.log("active_created_epoch=" + Math.floor(t / 1000));
}
for (const k of ["planned", "in-progress", "pass", "blocked"])
    console.log("count_" + k.replace(/-/g, "_") + "=" + (counts[k] || 0));
if (process.argv[2]) {
    try {
        const a = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
        console.log("archived=" + (a.features || []).length);
    } catch (e) { console.log("archived=-1"); }
}
' "$FLIST" "$ARCHIVE" 2>/dev/null || true)
fi

# Windows python/node emit \r\n; the multi-line facts keep a stray CR on every
# internal line, which `while read -r` preserves and contaminates each value
# (e.g. active_id="f-b\r"). Strip all CR before parsing. (v0.13.0)
facts="${facts//$'\r'/}"

degraded=0
[ -n "$facts" ] || degraded=1
fact() { # $1 = key → value or empty
    printf '%s\n' "$facts" | while IFS= read -r line; do
        case "$line" in "$1="*) printf '%s' "${line#"$1"=}"; break ;; esac
    done
}

project="(unnamed)"
if [ "$degraded" -eq 0 ]; then p=$(fact project); [ -n "$p" ] && project="$p"; fi
[ "$degraded" -eq 1 ] && project=$(basename "$(cd "$TARGET" && pwd)")

echo "## Status — $project"
echo ""
echo "### Active feature"
if [ "$degraded" -eq 1 ]; then
    echo "(needs python3 or node)"
elif [ -n "$(fact active_id)" ]; then
    echo "- **$(fact active_id)**: $(fact active_name) ($(fact active_desc)) — status: in-progress"
else
    echo "(no in-progress feature)"
fi
echo ""
echo "### Feature counts"
if [ "$degraded" -eq 1 ]; then
    echo "(needs python3 or node)"
else
    echo "- planned: $(fact count_planned)"
    echo "- in-progress: $(fact count_in_progress)"
    archived=$(fact archived)
    if [ "$archived" = "-1" ]; then
        echo "- pass: $(fact count_pass) (archive unreadable)"
    elif [ -n "$archived" ]; then
        echo "- pass: $(fact count_pass) (+$archived archived)"
    else
        echo "- pass: $(fact count_pass)"
    fi
    echo "- blocked: $(fact count_blocked)"
fi
echo ""
echo "### Git working tree"
if git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
    tree=$(git -C "$TARGET" status --porcelain 2>/dev/null || true)
    if [ -n "$tree" ]; then printf '%s\n' "$tree"; else echo "(clean)"; fi
else
    echo "(not a git repo)"
fi
echo ""
echo "### TOC freshness"
if [ -x "$SCRIPT_DIR/toc-freshness.sh" ]; then
    bash "$SCRIPT_DIR/toc-freshness.sh" "$TARGET"
else
    echo "(toc-freshness.sh missing — plugin install incomplete)"
fi
echo ""
echo "### Session handoff (head)"
if [ -f "$TARGET/session-handoff.md" ]; then
    head -15 "$TARGET/session-handoff.md"
else
    echo "(no session-handoff.md — run /session-end after work)"
fi
echo ""
echo "### Harness health"
if [ -f "$TARGET/golden-rules.md" ] && [ -x "$SCRIPT_DIR/golden-rules-check.sh" ]; then
    gc_counts=$(bash "$SCRIPT_DIR/golden-rules-check.sh" --target "$TARGET" --count 2>/dev/null || echo "0 0")
    echo "- golden rules: ${gc_counts%% *} rule(s) (${gc_counts##* } mechanical)"
else
    echo "- golden rules: (none — seed via capturing-golden-rules)"
fi
newest_drift=$(ls -t "$TARGET/.harness-anchor"/drift-*.md 2>/dev/null | head -1 || true)
if [ -n "$newest_drift" ] && [ -f "$newest_drift" ]; then
    dm=$(mtime_of "$newest_drift"); dm="${dm:-$NOW}"
    dv=$(awk '/^### Verdict/{f=1; next} f && /^- /{print; exit}' "$newest_drift" 2>/dev/null || true)
    case "$dv" in
        *"DRIFT FOUND"*) dverdict="DRIFT FOUND" ;;
        *CLEAN*)         dverdict="CLEAN" ;;
        *)               dverdict="(verdict unparsed)" ;;
    esac
    echo "- last /gc scan: $(fmt_age $((NOW - dm))) — $dverdict"
else
    echo "- last /gc scan: never — run /gc"
fi
if [ "$degraded" -eq 1 ]; then
    echo "- active feature age: (needs python3 or node)"
elif [ -n "$(fact active_created_epoch)" ]; then
    echo "- active feature age: $(fmt_age $((NOW - $(fact active_created_epoch))))"
elif [ -n "$(fact active_id)" ]; then
    echo "- active feature age: (no createdAt recorded)"
else
    echo "- active feature age: (no active feature)"
fi
if [ -f "$TARGET/session-handoff.md" ]; then
    hm=$(mtime_of "$TARGET/session-handoff.md"); hm="${hm:-$NOW}"
    echo "- handoff age: $(fmt_age $((NOW - hm)))"
else
    echo "- handoff age: (no handoff)"
fi
budgets=""
for spec in "progress.md:65536" "feature_list.json:32768" "golden-rules.md:8192" "AGENTS.md:8192" "session-handoff.md:4096"; do
    bf="${spec%%:*}"; bcap="${spec##*:}"
    bp="$TARGET/$bf"
    [ -f "$bp" ] || continue
    bs=$(wc -c < "$bp" 2>/dev/null | tr -cd '0-9'); bs="${bs:-0}"
    entry="$bf $(( (bs + 1023) / 1024 ))KB/$((bcap / 1024))KB"
    [ "$bs" -gt "$bcap" ] && entry="$entry OVER — /session-end offers archival/trim"
    if [ -z "$budgets" ]; then budgets="$entry"; else budgets="$budgets · $entry"; fi
done
echo "- state budgets: ${budgets:-"(no budgeted state files present)"}"
exit 0
