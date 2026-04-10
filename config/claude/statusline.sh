#!/usr/bin/env bash
input=$(cat)

dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
dir_name=$(basename "$dir")
session_name=$(echo "$input" | jq -r '.session_name // empty')

branch=$(git -C "$dir" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)

used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five_hour=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
total_cost=$(echo "$input" | jq -r '.total_cost_usd // empty')

# --- Branch color pill ---
# Derive a stable bg color from the branch name using a curated palette of
# visually distinct, readable xterm-256 colors (medium-brightness, not too dark).
# Palette: a hand-picked set of 20 colors that look good as backgrounds in a
# dimmed terminal and are spread across the hue wheel.
PALETTE=(
  39   # bright cyan-blue
  33   # dodger blue
  27   # deep blue
  57   # blue-violet
  93   # purple
  129  # magenta-purple
  165  # hot pink
  197  # crimson
  160  # red
  166  # orange-red
  172  # orange
  178  # gold
  106  # olive green
  64   # forest green
  35   # medium green
  36   # teal-green
  37   # teal
  38   # cyan-teal
  68   # steel blue
  98   # slate purple
)
PALETTE_LEN=${#PALETTE[@]}

# Determine the label for the pill: prefer session_name, fall back to branch,
# then dir_name.
if [ -n "$session_name" ]; then
  pill_label="$session_name"
elif [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
  pill_label="$branch"
else
  pill_label="$dir_name"
fi

# Hash the pill label to pick a palette index (cksum is available on macOS/Linux).
hash_val=$(printf '%s' "$pill_label" | cksum | awk '{print $1}')
color_idx=$(( hash_val % PALETTE_LEN ))
bg_color=${PALETTE[$color_idx]}

# Use bright white text on the colored background for maximum contrast.
# ESC[48;5;Xm = set bg to 256-color X, ESC[97m = bright white fg, ESC[1m = bold
pill="$(printf '\033[48;5;%dm\033[97m\033[1m %s \033[0m' "$bg_color" "$pill_label")"

parts=("$pill")

# Directory (dimmed, only when it differs from the pill label)
if [ "$pill_label" != "$dir_name" ]; then
  parts+=("$(printf '\033[34m%s\033[0m' "$dir_name")")
fi

# Git ahead/behind remote
if [ -n "$dir" ]; then
  ahead_behind=$(git -C "$dir" --no-optional-locks rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
  if [ -n "$ahead_behind" ]; then
    ahead=$(echo "$ahead_behind" | awk '{print $1}')
    behind=$(echo "$ahead_behind" | awk '{print $2}')
    git_sync=""
    if [ "$ahead" -gt 0 ] 2>/dev/null; then
      git_sync="$(printf '\033[32m↑%d\033[0m' "$ahead")"
    fi
    if [ "$behind" -gt 0 ] 2>/dev/null; then
      behind_str="$(printf '\033[33m↓%d\033[0m' "$behind")"
      if [ -n "$git_sync" ]; then
        git_sync="$git_sync $behind_str"
      else
        git_sync="$behind_str"
      fi
    fi
    if [ -n "$git_sync" ]; then
      parts+=("$git_sync")
    fi
  fi
fi

# Dev server status (look for process-compose, vike, vite, or node dev processes)
if pgrep -f 'process-compose' > /dev/null 2>&1 || \
   pgrep -f 'vike' > /dev/null 2>&1 || \
   pgrep -f 'vite' > /dev/null 2>&1 || \
   pgrep -f 'node.*dev' > /dev/null 2>&1; then
  parts+=("$(printf '\033[32m●\033[0m dev')")
else
  parts+=("$(printf '\033[31m●\033[0m dev')")
fi

# Git lines changed (added/removed vs HEAD)
if [ -n "$dir" ]; then
  diff_stat=$(git -C "$dir" --no-optional-locks diff --stat HEAD 2>/dev/null | tail -1)
  if [ -n "$diff_stat" ]; then
    added=$(echo "$diff_stat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
    removed=$(echo "$diff_stat" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')
    lines_seg=""
    if [ -n "$added" ] && [ "$added" -gt 0 ] 2>/dev/null; then
      lines_seg="$(printf '\033[32m+%d\033[0m' "$added")"
    fi
    if [ -n "$removed" ] && [ "$removed" -gt 0 ] 2>/dev/null; then
      removed_str="$(printf '\033[31m-%d\033[0m' "$removed")"
      if [ -n "$lines_seg" ]; then
        lines_seg="$lines_seg $removed_str"
      else
        lines_seg="$removed_str"
      fi
    fi
    if [ -n "$lines_seg" ]; then
      parts+=("$lines_seg")
    fi
  fi
fi

# Context window usage — percentage only
if [ -n "$used_pct" ]; then
  used_int=$(printf '%.0f' "$used_pct")
  if [ "$used_int" -ge 80 ]; then
    ctx_color='\033[31m'
  elif [ "$used_int" -ge 50 ]; then
    ctx_color='\033[33m'
  else
    ctx_color='\033[32m'
  fi
  parts+=("$(printf "ctx ${ctx_color}%d%%\033[0m" "$used_int")")
fi

# 5-hour rate limit
if [ -n "$five_hour" ]; then
  five_int=$(printf '%.0f' "$five_hour")
  if [ "$five_int" -ge 80 ]; then
    parts+=("$(printf '\033[31m5h:%d%%\033[0m' "$five_int")")
  else
    parts+=("$(printf '5h:%d%%' "$five_int")")
  fi
fi

# 7-day rate limit
if [ -n "$seven_day" ]; then
  seven_int=$(printf '%.0f' "$seven_day")
  if [ "$seven_int" -ge 80 ]; then
    parts+=("$(printf '\033[31m7d:%d%%\033[0m' "$seven_int")")
  else
    parts+=("$(printf '7d:%d%%' "$seven_int")")
  fi
fi

# Session cost
if [ -n "$total_cost" ]; then
  cost_check=$(printf '%.6f' "$total_cost" 2>/dev/null)
  if [ -n "$cost_check" ] && awk "BEGIN{exit !($total_cost > 0)}" 2>/dev/null; then
    parts+=("$(printf '\$%.2f' "$total_cost")")
  fi
fi

printf '%s' "$(IFS=' | '; echo "${parts[*]}")"
