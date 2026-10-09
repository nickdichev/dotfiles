#!/bin/bash

# Required parameters:
# @vicinae.schemaVersion 1
# @vicinae.title Sleep Displays
# @vicinae.mode silent

# Optional parameters:
# @vicinae.icon 💤
# @vicinae.packageName System
# @vicinae.description Put all displays to sleep without suspending the Mac

exec /usr/bin/pmset displaysleepnow
