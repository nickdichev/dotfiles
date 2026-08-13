#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Sleep Displays
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 💤
# @raycast.packageName System
# @raycast.description Put all displays to sleep without suspending the Mac

exec /usr/bin/pmset displaysleepnow
