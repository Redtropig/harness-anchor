#!/usr/bin/env bash
# portable.sh — platform portability layer for harness-anchor (v0.13.0).
# Sourced by the four hooks and by runtime-surface scripts. bash 3.2 compatible.
#
# JSON engine chain: python3 → python → py -3 → node → narrow pure-bash.
# Detection VALIDATES BY RUNNING a one-liner and checking its output — a tool
# that exists on PATH but cannot run (e.g. the Windows Store python.exe stub)
# is skipped automatically. The pure-bash tier only handles the narrow scalar
# fields hooks need and the plugin's own controlled JSON formats; anything it
# cannot extract yields empty, which callers treat as "check unavailable"
# (warn-only: silent skip, never an infra error in agent context).
#
# Functions: ha_platform_init, ha_normalize_path, ha_find_project_root,
#   ha_json_engine_init, ha_json_field, ha_json_fields, ha_json_escape,
#   ha_json_valid, ha_flist_active, ha_mtime, ha_python.

# ---- platform ----
# HA_OS taxonomy: windows | darwin | linux. validate-anchor's HA_OS_TAXONOMY
# mirrors this list — keep both in sync when adding a platform.
# A pre-set HA_OS is RESPECTED (v0.14.0): tests inject platform states, and a
# user may override classification (containers / WSL / trying a new platform).
# The PATH shield keys on the REAL uname regardless — environment fact and
# taxonomy classification are deliberately decoupled.
ha_platform_init() {
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*)
            # System32 ships incompatible find.exe / sort.exe / timeout.exe.
            # /usr/bin first makes GNU coreutils win for this process tree.
            case ":$PATH:" in
                *":/usr/bin:"*) : ;;
                *) PATH="/usr/bin:$PATH" ;;
            esac
            : "${HA_OS:=windows}"
            ;;
        Darwin) : "${HA_OS:=darwin}" ;;
        *)      : "${HA_OS:=linux}" ;;
    esac
    export HA_OS
}

ha_normalize_path() {
    printf '%s' "${1//\\//}"
}

ha_find_project_root() {
    # Fixed-point walk-up looking for feature_list.json. Terminates on /,
    # drive roots (C:/), '.', and UNC roots alike — dirname(x)==x is the stop.
    local dir parent i=0
    dir="$(ha_normalize_path "${1:-}")"
    while [ -n "$dir" ] && [ "$i" -lt 64 ]; do
        if [ -f "$dir/feature_list.json" ]; then
            printf '%s' "$dir"
            return 0
        fi
        parent="$(dirname "$dir")"
        [ "$parent" = "$dir" ] && break
        dir="$parent"
        i=$((i + 1))
    done
    return 1
}

# ---- engine detection (cached per process) ----
ha_json_engine_init() {
    [ -n "${HA_JSON_ENGINE:-}" ] && return 0
    local out
    if out=$(python3 -c 'print(1)' 2>/dev/null) && [ "$out" = "1" ]; then
        HA_JSON_ENGINE="python3"; HA_PY="python3"
    elif out=$(python -c 'print(1)' 2>/dev/null) && [ "$out" = "1" ]; then
        HA_JSON_ENGINE="python"; HA_PY="python"
    elif out=$(py -3 -c 'print(1)' 2>/dev/null) && [ "$out" = "1" ]; then
        HA_JSON_ENGINE="py"; HA_PY="py -3"
    elif out=$(node -e 'console.log(1)' 2>/dev/null) && [ "$out" = "1" ]; then
        HA_JSON_ENGINE="node"; HA_PY=""
    else
        HA_JSON_ENGINE="none"; HA_PY=""
    fi
    export HA_JSON_ENGINE HA_PY
}

ha_python() {
    ha_json_engine_init
    [ -n "$HA_PY" ] || return 1
    printf '%s' "$HA_PY"
}

# ---- narrow pure-bash tier (last resort) ----
ha_json_field_bash() {
    # $1 = dotted path (leaf key used), $2 = JSON text. Handles unique keys with
    # string values (unescapes \\ \" \/) and unquoted scalars (true/false/nums).
    local leaf="${1##*.}" flat val
    flat=$(printf '%s' "$2" | tr -d '\n\r')
    val=$(printf '%s' "$flat" | sed -nE 's/.*"'"$leaf"'"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' | head -1)
    if [ -n "$val" ]; then
        printf '%s' "$val" | sed -e 's/\\\//\//g' -e 's/\\"/"/g' -e 's/\\\\/\\/g'
        return 0
    fi
    printf '%s' "$flat" | sed -nE 's/.*"'"$leaf"'"[[:space:]]*:[[:space:]]*([A-Za-z0-9.+-]+).*/\1/p' | head -1
}

# ---- field extraction ----
ha_json_field() {
    # $1 = dotted field path; JSON on stdin; echoes scalar (bools → true/false).
    local field="$1" data out=""
    data=$(cat 2>/dev/null || true)
    [ -n "$data" ] || return 0
    ha_json_engine_init
    case "$HA_JSON_ENGINE" in
        python3|python|py)
            # shellcheck disable=SC2086
            out=$(printf '%s' "$data" | $HA_PY -c '
import json, sys
try:
    d = json.load(sys.stdin)
    for part in sys.argv[1].split("."):
        d = d.get(part) if isinstance(d, dict) else None
    if isinstance(d, bool):
        print("true" if d else "false")
    elif isinstance(d, (str, int, float)):
        print(d)
except Exception:
    pass' "$field" 2>/dev/null || true) ;;
        node)
            out=$(printf '%s' "$data" | node -e '
let d;
try { d = JSON.parse(require("fs").readFileSync(0, "utf8")); } catch (e) { process.exit(0); }
for (const p of process.argv[1].split(".")) d = (d && typeof d === "object") ? d[p] : undefined;
if (typeof d === "boolean") process.stdout.write(String(d));
else if (typeof d === "string" || typeof d === "number") process.stdout.write(String(d));
' "$field" 2>/dev/null || true) ;;
    esac
    # Windows python/node stdout is text-mode: print() emits \r\n. A single-line
    # value loses the trailing CR via $(...), but strip defensively regardless.
    out="${out//$'\r'/}"
    [ -n "$out" ] || out=$(ha_json_field_bash "$field" "$data")
    printf '%s' "$out"
}

ha_json_fields() {
    # $@ = field paths; JSON on stdin; one value per line in argument order.
    local data out="" f
    data=$(cat 2>/dev/null || true)
    [ -n "$data" ] || return 0
    ha_json_engine_init
    case "$HA_JSON_ENGINE" in
        python3|python|py)
            # shellcheck disable=SC2086
            out=$(printf '%s' "$data" | $HA_PY -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for path in sys.argv[1:]:
    v = d
    for part in path.split("."):
        v = v.get(part) if isinstance(v, dict) else None
    if isinstance(v, bool):
        print("true" if v else "false")
    elif isinstance(v, (str, int, float)):
        print(v)
    else:
        print("")' "$@" 2>/dev/null || true) ;;
        node)
            out=$(printf '%s' "$data" | node -e '
let d;
try { d = JSON.parse(require("fs").readFileSync(0, "utf8")); } catch (e) { process.exit(0); }
const lines = [];
for (const path of process.argv.slice(1)) {
    let v = d;
    for (const p of path.split(".")) v = (v && typeof v === "object") ? v[p] : undefined;
    if (typeof v === "boolean") lines.push(String(v));
    else lines.push((typeof v === "string" || typeof v === "number") ? String(v) : "");
}
process.stdout.write(lines.join("\n") + "\n");
' "$@" 2>/dev/null || true) ;;
    esac
    # Windows python/node emit \r\n on EVERY line; $(...) only strips the final
    # trailing newline, so internal lines keep a stray CR. Strip all of them so
    # per-field `sed -n Np` extraction is clean without the double-$() dance.
    out="${out//$'\r'/}"
    if [ -z "$out" ]; then
        for f in "$@"; do
            ha_json_field_bash "$f" "$data"
            printf '\n'
        done
        return 0
    fi
    printf '%s\n' "$out"
}

ha_json_escape() {
    # Raw string on stdin → JSON-escaped (no outer quotes). O(n) via engine;
    # pure-bash fallback is the pre-v0.13 escaper (quadratic on huge payloads —
    # acceptable last resort, same as pre-v0.10 behavior).
    local data out="" s
    data=$(cat 2>/dev/null || true)
    ha_json_engine_init
    case "$HA_JSON_ENGINE" in
        python3|python|py)
            # shellcheck disable=SC2086
            out=$(printf '%s' "$data" | $HA_PY -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null || true) ;;
        node)
            out=$(printf '%s' "$data" | node -e 'const s=require("fs").readFileSync(0,"utf8");process.stdout.write(JSON.stringify(s).slice(1,-1));' 2>/dev/null || true) ;;
    esac
    if [ -z "$out" ] && [ -n "$data" ]; then
        s="$data"
        s="${s//\\/\\\\}"
        s="${s//\"/\\\"}"
        s="${s//$'\n'/\\n}"
        s="${s//$'\r'/\\r}"
        s="${s//$'\t'/\\t}"
        out="$s"
    fi
    printf '%s' "$out"
}

ha_json_valid() {
    # JSON on stdin → exit 0 valid / 1 invalid / 2 no engine (caller may SKIP).
    local data
    data=$(cat 2>/dev/null || true)
    ha_json_engine_init
    case "$HA_JSON_ENGINE" in
        python3|python|py)
            # shellcheck disable=SC2086
            printf '%s' "$data" | $HA_PY -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null ;;
        node)
            printf '%s' "$data" | node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))' 2>/dev/null ;;
        *)  return 2 ;;
    esac
}

ha_flist_active() {
    # $1 = feature_list.json → "id: name" of first in-progress feature, or the
    # literal "(no in-progress feature)" when the file parses but none is
    # in-progress. Empty output = no engine / unreadable (engines only —
    # arbitrary user JSON is beyond the bash tier by design).
    [ -f "${1:-}" ] || return 0
    ha_json_engine_init
    case "$HA_JSON_ENGINE" in
        python3|python|py)
            # shellcheck disable=SC2086
            $HA_PY - "$1" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    for feat in d.get('features', []):
        if feat.get('status') == 'in-progress':
            print("%s: %s" % (feat.get('id', '?'), feat.get('name', '')))
            break
    else:
        print("(no in-progress feature)")
except Exception:
    pass
PY
            ;;
        node)
            node -e '
let d;
try { d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); } catch (e) { process.exit(0); }
let hit = null;
for (const f of (d.features || [])) {
    if (f && f.status === "in-progress") { hit = (f.id === undefined ? "?" : f.id) + ": " + (f.name || ""); break; }
}
console.log(hit === null ? "(no in-progress feature)" : hit);
' "$1" 2>/dev/null || true
            ;;
    esac
}

ha_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}
