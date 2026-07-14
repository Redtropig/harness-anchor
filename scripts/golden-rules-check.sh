#!/usr/bin/env bash
# golden-rules-check.sh — Parse golden-rules.md and RUN its mechanical checks.
#
# Tier decision per rule (### GR-<n> — <title>), in precedence order:
#   1. the "- **Check:**" line contains "manual review" (case-insensitive) → MANUAL
#      (even if the line also carries backtick spans — they are prose, not a command)
#   2. else the FIRST backtick span on that line is the mechanical command → MECH
#   3. no backtick span → MANUAL
#
# Verdict semantics for a MECH check (grep-natural convention, documented in
# templates/golden-rules.md.tpl and the capturing-golden-rules skill):
#   - TIMEOUT (>5s)            → CHECK-ERROR (timeout >5s)
#   - exit status > 1          → CHECK-ERROR (exit N) — the check itself broke
#   - any output (exit 0 or 1) → FINDINGS(n) — candidate violations; whether they
#                                are "unexpected" stays the CALLER's judgment
#   - no output                → CLEAN
# CHECK-ERROR is deliberately distinct from CLEAN: a silent sensor must be
# attributable ("found nothing" vs "didn't look") — same principle as /sanitize
# INFRA-FAIL.
#
# Trust boundary: Check commands come from the project's own golden-rules.md —
# the same trust level as the project's init.sh, which /session-end and the
# verification-runner already execute. The per-check 5s watchdog and per-check
# isolation guard against accidents, not malice.
#
# Usage: golden-rules-check.sh [--target <dir>] [--count]
#   --count → single line "N K" (total rules / mechanical rules), nothing else.
# Exit 0 always (facts reported, even "no golden-rules.md"); 2 = usage error.

set -uo pipefail

TARGET="."
COUNT_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --target)
            shift
            [ $# -gt 0 ] && [ -d "${1:-}" ] || { echo "golden-rules-check: --target requires an existing directory" >&2; exit 2; }
            TARGET="$1" ;;
        --count) COUNT_ONLY=1 ;;
        *) echo "golden-rules-check: unknown argument '$1'" >&2; exit 2 ;;
    esac
    shift
done

GR_FILE="$TARGET/golden-rules.md"
if [ ! -f "$GR_FILE" ]; then
    if [ "$COUNT_ONLY" -eq 1 ]; then echo "0 0"; else echo "no golden-rules.md"; fi
    exit 0
fi

# ---- Parse: one TAB-separated record per rule: id \t title \t check-line ----
records=$(awk '
    function flush() { if (id != "") printf "%s\t%s\t%s\n", id, title, check }
    /^### GR-[0-9]+/ {
        flush()
        line = $0; sub(/^### +/, "", line)
        id = line; sub(/[^A-Za-z0-9-].*$/, "", id)
        title = line
        sub(/^GR-[0-9]+[[:space:]]*[^[:space:]]*[[:space:]]*/, "", title)
        check = ""
        next
    }
    id != "" && /^- \*\*Check:\*\*/ && check == "" {
        check = $0; sub(/^- \*\*Check:\*\*[[:space:]]*/, "", check)
        gsub(/\t/, " ", check)
    }
    END { flush() }
' "$GR_FILE")

total=0; mech=0
if [ -n "$records" ]; then
    total=$(printf '%s\n' "$records" | grep -c .)
fi

# ---- Tier classification (precedence: manual-review > first backtick span) ----
tier_of() { # $1 = check line → prints "MANUAL" or "MECH<TAB><cmd>"
    check="$1"
    lc=$(printf '%s' "$check" | tr '[:upper:]' '[:lower:]')
    case "$lc" in
        *"manual review"*) printf 'MANUAL'; return ;;
    esac
    case "$check" in
        *\`*\`*)
            cmd="${check#*\`}"; cmd="${cmd%%\`*}"
            if [ -n "$cmd" ]; then printf 'MECH\t%s' "$cmd"; return; fi ;;
    esac
    printf 'MANUAL'
}

# Pre-count mechanical rules (needed for the header before running anything).
if [ -n "$records" ]; then
    while IFS=$'\t' read -r _rid _rtitle rcheck; do
        case "$(tier_of "$rcheck")" in MECH*) mech=$((mech+1)) ;; esac
    done <<EOF
$records
EOF
fi

if [ "$COUNT_ONLY" -eq 1 ]; then
    echo "$total $mech"
    exit 0
fi

echo "## Golden-rules check — $total rule(s), $mech mechanical"
echo ""
if [ "$total" -eq 0 ]; then
    echo "(no GR entries — seed via capturing-golden-rules)"
    exit 0
fi

# ---- Run one command under a 5s SIGKILL watchdog (macOS-safe; see hooks) ----
run_check() { # $1 = cmd → sets: verdict, evidence (first 10 lines), out_lines
    of=$(mktemp); rf=$(mktemp)
    ( cd "$TARGET" && bash -c "$1" > "$of" 2>&1; echo $? > "$rf" ) &
    cp_=$!
    ( sleep 5; kill -9 "$cp_" 2>/dev/null ) >/dev/null 2>&1 &
    wd=$!
    wait "$cp_" 2>/dev/null
    kill -9 "$wd" 2>/dev/null
    wait "$wd" 2>/dev/null
    if [ ! -s "$rf" ]; then
        verdict="CHECK-ERROR (timeout >5s)"; evidence=""; out_lines=0
    else
        rc=$(tr -cd '0-9' < "$rf"); rc="${rc:-1}"
        out_lines=$(wc -l < "$of" | tr -cd '0-9'); out_lines="${out_lines:-0}"
        if [ "$rc" -gt 1 ]; then
            verdict="CHECK-ERROR (exit $rc)"
            evidence=$(head -3 "$of" 2>/dev/null)
        elif [ -s "$of" ]; then
            if [ "$out_lines" -gt 10 ]; then
                verdict="FINDINGS($out_lines line(s), first 10 shown)"
            else
                verdict="FINDINGS($out_lines line(s))"
            fi
            evidence=$(head -10 "$of" 2>/dev/null)
        else
            verdict="CLEAN"; evidence=""
        fi
    fi
    rm -f "$of" "$rf"
}

while IFS=$'\t' read -r rid rtitle rcheck; do
    [ -n "$rid" ] || continue
    tier=$(tier_of "$rcheck")
    case "$tier" in
        MECH*)
            cmd="${tier#MECH	}"
            run_check "$cmd"
            printf '%s [MECH] %s — `%s`\n' "$rid" "$verdict" "$cmd"
            if [ -n "$evidence" ]; then
                printf '%s\n' "$evidence" | sed 's/^/    /'
            fi
            ;;
        *)
            printf '%s [MANUAL] %s\n' "$rid" "$rtitle"
            ;;
    esac
done <<EOF
$records
EOF

exit 0
