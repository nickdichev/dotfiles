#!/bin/bash

# Required parameters:
# @vicinae.schemaVersion 1
# @vicinae.title Toggle System Appearance
# @vicinae.mode silent

# Optional parameters:
# @vicinae.icon 🌗
# @vicinae.packageName System
# @vicinae.description Switch macOS between light and dark appearance

exec /usr/bin/osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to not dark mode'
