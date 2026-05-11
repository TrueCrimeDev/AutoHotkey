#!/bin/bash
# PostToolUse hook for capture_error and analyze_error.
# Provides workflow guidance after key tools complete.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
TOOL_OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // empty' 2>/dev/null)

case "$TOOL_NAME" in
  mcp__autohotkey-debug__capture_error)
    # Check if we got an error or timed out
    if echo "$TOOL_OUTPUT" | jq -e '.status == "timeout"' >/dev/null 2>&1; then
      echo '{"additionalContext": "capture_error timed out. Either the script has not been started with /Debug, or it ran without errors. Ask the user if they want to retry with a longer timeout or check debug_status."}'
    else
      echo '{"additionalContext": "Error captured successfully. Next steps: 1) analyze_error to diagnose, 2) apply_fix to patch the file, 3) tell user to re-run. If watches are set, consider stepping through the error area first."}'
    fi
    ;;
  mcp__autohotkey-debug__analyze_error)
    if echo "$TOOL_OUTPUT" | jq -e '.status == "analyzed"' >/dev/null 2>&1; then
      echo '{"additionalContext": "Claude API analysis complete. Extract the suggested_fix and call apply_fix if confidence is >= 0.7. Show the diagnosis to the user before applying."}'
    elif echo "$TOOL_OUTPUT" | jq -e '.status == "api_error"' >/dev/null 2>&1; then
      echo '{"additionalContext": "API call failed. The analysis_prompt is included in the response — use it to analyze the error yourself."}'
    else
      echo '{"additionalContext": "Analysis prompt returned for client-side analysis. Read the prompt and provide your own diagnosis, then use apply_fix if confident."}'
    fi
    ;;
  mcp__autohotkey-debug__apply_fix)
    if echo "$TOOL_OUTPUT" | jq -e '.success == true' >/dev/null 2>&1; then
      echo '{"additionalContext": "Fix applied successfully. Tell the user to re-run: bin\\AutoHotkey64.exe /Debug script.ahk"}'
    else
      echo '{"additionalContext": "Fix failed — likely a line mismatch. Read the actual line content from the error, adjust the original parameter, and retry apply_fix."}'
    fi
    ;;
  *)
    echo '{}'
    ;;
esac
