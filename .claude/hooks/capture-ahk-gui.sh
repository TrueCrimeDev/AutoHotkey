#!/bin/bash
# Captures AHK GUI window after script runs
# Returns image path for Claude to read

# Check if an AHK script was just run (from tool_input in stdin)
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only trigger for AHK script executions
if [[ "$TOOL_NAME" == "Bash" ]] && [[ "$TOOL_INPUT" == *"AutoHotkey"* ]] && [[ "$TOOL_INPUT" == *".ahk"* ]]; then
    # Longer wait for background scripts (contain &)
    if [[ "$TOOL_INPUT" == *"&"* ]]; then
        sleep 2.5
    else
        sleep 1.0
    fi

    # Try to find AHK window and capture it (PS script has retry logic)
    CAPTURE_PATH=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\uphol\Documents\AHK\capture-ahk-window.ps1" 2>/dev/null | tr -d '\r')

    if [[ -n "$CAPTURE_PATH" ]]; then
        WSL_PATH=$(wslpath "$CAPTURE_PATH" 2>/dev/null)
        if [[ -f "$WSL_PATH" ]]; then
            echo ""
            echo "─────────────────────────────────────────"
            echo "GUI Screenshot captured: $WSL_PATH"
            echo "Use Read tool to view the GUI."
            echo "─────────────────────────────────────────"
        fi
    fi
fi
