#!/usr/bin/env bash

set -euo pipefail

payload="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "unknown-model [?] ?%"
  exit 0
fi

model_name="$(printf '%s' "$payload" | jq -r '.model.display_name // .model.id // "unknown-model"')"
context_pct="$(printf '%s' "$payload" | jq -r '(.context_window.used_percentage // 0) | floor')"
blocks_total=10
blocks_filled=$((context_pct * blocks_total / 100))
yellow_threshold="${CLAUDE_CTX_YELLOW:-70}"
red_threshold="${CLAUDE_CTX_RED:-90}"

if [ "$blocks_filled" -lt 0 ]; then
  blocks_filled=0
fi
if [ "$blocks_filled" -gt "$blocks_total" ]; then
  blocks_filled=$blocks_total
fi

color_green="$(printf '\033[32m')"
color_yellow="$(printf '\033[33m')"
color_red="$(printf '\033[31m')"
color_reset="$(printf '\033[0m')"

if [ "$context_pct" -ge "$red_threshold" ]; then
  color="$color_red"
elif [ "$context_pct" -ge "$yellow_threshold" ]; then
  color="$color_yellow"
else
  color="$color_green"
fi

filled="$(printf '%*s' "$blocks_filled" '' | tr ' ' '#')"
empty="$(printf '%*s' "$((blocks_total - blocks_filled))" '' | tr ' ' '-')"

printf '%s %b[%s%s]%b %s%%\n' "$model_name" "$color" "$filled" "$empty" "$color_reset" "$context_pct"
