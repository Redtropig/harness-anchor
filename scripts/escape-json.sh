#!/usr/bin/env bash
# Pure-bash JSON string escaper for hook script output.
# Reads stdin, writes escaped string (without surrounding quotes) to stdout.
# Avoids jq dependency to keep harness-anchor zero-dependency.

set -euo pipefail

s="$(cat)"
s="${s//\\/\\\\}"
s="${s//\"/\\\"}"
s="${s//$'\n'/\\n}"
s="${s//$'\r'/\\r}"
s="${s//$'\t'/\\t}"
printf '%s' "$s"
