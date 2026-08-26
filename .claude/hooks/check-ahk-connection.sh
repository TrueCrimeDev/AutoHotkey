#!/bin/bash
# PreToolUse hook for the DBGp debug tool (mcp__ahk__AHK_Debug_DBGp).
# Provides helpful context if the debugger isn't reachable.
# JSON parsing uses python3 — jq is NOT installed in this WSL.

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "
import json,sys
try: print(json.load(sys.stdin).get('tool_name',''))
except Exception: pass
" 2>/dev/null)

case "$TOOL_NAME" in
  mcp__ahk__AHK_Debug_DBGp)
    echo '{"additionalContext": "DBGp: the listener (action start) must be up BEFORE the script runs. If this returns a connection error, tell the user to run: bin\\AutoHotkey64.exe /Debug script.ahk — and remember port 9000 allows one listener (VS Code F5 debugging conflicts)."}'
    ;;
  *)
    # Not a debug tool, pass through
    echo '{}'
    ;;
esac
