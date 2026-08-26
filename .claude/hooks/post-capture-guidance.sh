#!/bin/bash
# PostToolUse hook for mcp__ahk__AHK_Debug_DBGp.
# Provides workflow guidance after the key debug-loop actions complete.
# The action lives in tool_input.action (one tool, many actions).
# JSON parsing uses python3 — jq is NOT installed in this WSL.

INPUT=$(cat)

printf '%s' "$INPUT" | python3 -c '
import json, sys

def ctx(msg):
    print(json.dumps({"additionalContext": msg}))

try:
    d = json.load(sys.stdin)
except Exception:
    print("{}"); raise SystemExit

if d.get("tool_name") != "mcp__ahk__AHK_Debug_DBGp":
    print("{}"); raise SystemExit

action = (d.get("tool_input") or {}).get("action", "")
out = d.get("tool_output")
if isinstance(out, str):
    try: out = json.loads(out)
    except Exception: out = {}
if not isinstance(out, dict):
    out = {}

if action == "capture_error":
    if out.get("status") == "timeout":
        ctx("capture_error timed out. Either the script has not been started with /Debug, "
            "or it ran without errors. Ask the user if they want to retry with a longer "
            "timeout or check action: status.")
    else:
        ctx("Error captured. Next: 1) analyze_error to diagnose, 2) apply_fix to patch "
            "the file, 3) tell user to re-run.")
elif action == "analyze_error":
    if out.get("status") == "analyzed":
        ctx("Claude API analysis complete. Extract the suggested_fix and call apply_fix "
            "if confidence is >= 0.7. Show the diagnosis to the user before applying.")
    else:
        ctx("Analysis prompt returned for client-side analysis. Provide your own "
            "diagnosis, then use apply_fix if confident.")
elif action == "apply_fix":
    if out.get("success") is True:
        ctx("Fix applied. Tell the user to re-run: bin\\AutoHotkey64.exe /Debug script.ahk")
    else:
        ctx("Fix failed — likely a line mismatch. Read the actual line content from the "
            "error, adjust the original parameter, and retry apply_fix.")
else:
    print("{}")
'
