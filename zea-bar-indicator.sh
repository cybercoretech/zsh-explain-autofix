#!/usr/bin/env bash
#
# zea-bar-indicator — Omarchy bar widget indicator for zsh-explain-autofix
#
# Prints "⚠" if the last command failed (failure state file exists),
# otherwise prints nothing. Use this in your Omarchy shell.json bar config
# or in your status bar script.
#
# Usage:
#   source /path/to/zea-bar-indicator.sh   # sets ZEA_FAILURE indicator
#   # or
#   /path/to/zea-bar-indicator.sh           # prints ⚠ or nothing
#
# Environment:
#   ZEA_STATE_DIR   (default: ${XDG_CACHE_HOME:-$HOME/.cache}/zsh-explain-autofix)
#

ZEA_STATE_DIR="${ZEA_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zsh-explain-autofix}"
ZEA_STATE_FILE="$ZEA_STATE_DIR/last-failure.json"

if [[ -f "$ZEA_STATE_FILE" ]]; then
    # Extract exit code for the indicator text
    exit_code=$(python3 -c "import json; print(json.load(open('$ZEA_STATE_FILE'))['exit_code'])" 2>/dev/null || echo "?")
    echo "⚠ exit:$exit_code"
else
    echo ""
fi
