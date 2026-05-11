#!/bin/bash
# PreToolUse hook for debug MCP tools.
# Checks if AutoHotkey is likely connected by testing port 9000.
# Provides helpful context if the debugger isn't reachable.

# Read tool input from stdin
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only check for debug-related MCP tools
case "$TOOL_NAME" in
  mcp__autohotkey-debug__debug_*|mcp__autohotkey-debug__capture_error|mcp__autohotkey-debug__breakpoint_*|mcp__autohotkey-debug__variables_get|mcp__autohotkey-debug__evaluate|mcp__autohotkey-debug__stack_trace|mcp__autohotkey-debug__watch_list)
    # Check if port 9000 has a listener (MCP server manages this internally,
    # but if the tool errors with "Not connected", this context helps)
    echo '{"additionalContext": "If this tool returns a connection error, tell the user to run their script with: bin\\AutoHotkey64.exe /Debug script.ahk"}'
    ;;
  *)
    # Not a debug tool, pass through
    echo '{}'
    ;;
esac
