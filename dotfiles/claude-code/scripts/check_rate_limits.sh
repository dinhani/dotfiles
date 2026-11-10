#!/usr/bin/env bash
set -uo pipefail

# read input
input=$(cat)
state="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/rate-limits.json"

# parse
output=$(jq -b -r '
  (if .rate_limits then {updated_at: (now | todate), rate_limits} | tojson else "" end),
  ([.model.display_name,
    (.rate_limits.five_hour.used_percentage | if . then "5h \(floor)%" else empty end),
    (.rate_limits.seven_day.used_percentage | if . then "7d \(floor)%" else empty end)]
   | map(select(.)) | join(" · "))
' <<<"$input")
limits=${output%%$'\n'*}
line=${output#*$'\n'}

# save limits
if [[ -n $limits ]]; then
  mkdir -p "${state%/*}"
  printf '%s\n' "$limits" >"$state.tmp" && mv -f "$state.tmp" "$state"
fi

# print
printf '%s' "$line"
