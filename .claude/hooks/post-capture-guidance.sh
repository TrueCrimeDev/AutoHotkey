#!/usr/bin/env bash
# PostToolUse and PostToolUseFailure hook for mcp__ahk__AHK_Debug_DBGp (the
# user-wide ahk server's debug toolset, hidden until the user enables it).
#
# Adds next-step guidance after the key debug-loop results:
#   capture_error  {"captured":false,...}  -> why (the server never queues
#                                             errors; script paused; port)
#   capture_error  {"captured":true,...}   -> analyze_error, then apply_fix
#   apply_fix      "Fix applied at ..."    -> ask the user to re-run
#   apply_fix      failure (PostToolUseFailure, "Line mismatch", "Error:")
#                                          -> re-read the line and retry
# as {"hookSpecificOutput":{"hookEventName":"<incoming event>",
#     "additionalContext":"..."}} on exit 0. Anything else: no output, exit 0.
#
# Runs under Git Bash on Windows or any bash; no python/jq. Output is ASCII.
# Only [[ =~ ]] is used on the payload (pattern-removal expansions are slow
# on large strings). MCP result text arrives JSON-escaped inside
# tool_response, so a key there looks like \"captured\".

payload=$(cat 2>/dev/null)
[[ -n $payload ]] || exit 0

# First unescaped "key": "string" in the payload -> REPLY (JSON-escaped).
json_raw() {
    local re='"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
    REPLY=
    [[ $2 =~ $re ]] || return 1
    REPLY=${BASH_REMATCH[1]}
}
json_escape() {
    local s=$1
    s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\r'/}; s=${s//$'\t'/ }
    REPLY=$s
}
# tool_input's own "action" string -> REPLY (JSON-escaped). A key inside a
# string value arrives escaped (\"action\"), but a nested object in tool_input
# (an error's metadata, say) may carry its own "action" key, so only a direct
# member of tool_input counts. Fast path: action is the first member, the
# order the tool schema lists. Otherwise the members before it are skipped as
# whole values (strings, scalars, objects and arrays nested at most 3 deep)
# within the payload's first 8 KiB, since that regex is slow on long text.
# When action is not found either way, the hook stays silent.
J_STR='"([^"\\]|\\.)*"'
J_ANY='[^]{}["]'
J_N0="(\\{($J_STR|$J_ANY)*\\}|\\[($J_STR|$J_ANY)*\\])"
J_N1="(\\{($J_STR|$J_ANY|$J_N0)*\\}|\\[($J_STR|$J_ANY|$J_N0)*\\])"
J_N2="(\\{($J_STR|$J_ANY|$J_N1)*\\}|\\[($J_STR|$J_ANY|$J_N1)*\\])"
J_MEMBER="[[:space:]]*$J_STR[[:space:]]*:[[:space:]]*($J_STR|[^]{}[\",[:space:]]+|$J_N2)[[:space:]]*,"
J_TI='"tool_input"[[:space:]]*:[[:space:]]*\{'
J_ACTION='"action"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
tool_input_action() {
    local head=${1:0:65536} first="$J_TI[[:space:]]*$J_ACTION" later="$J_TI($J_MEMBER)*[[:space:]]*$J_ACTION"
    REPLY=
    if [[ $head =~ $first ]]; then REPLY=${BASH_REMATCH[1]}; return 0; fi
    head=${1:0:8192}
    [[ $head =~ $later ]] || return 1
    [[ ${BASH_REMATCH[0]} =~ $J_ACTION$ ]] || return 1
    REPLY=${BASH_REMATCH[1]}
}

json_raw hook_event_name "$payload" || exit 0
event=$REPLY
[[ $event == PostToolUse || $event == PostToolUseFailure ]] || exit 0
json_raw tool_name "$payload" || exit 0
[[ $REPLY == *AHK_Debug_DBGp ]] || exit 0
tool_input_action "$payload" || exit 0
action=$REPLY

# capture_error's result starts with the "captured" key; the leftmost match is
# that key, not a later variable value. apply_fix results are plain text that
# starts with "Fix applied at" or "Error: " (tool_response is a content array
# with "text" fields, a plain string, or either one JSON-encoded into a string,
# where the quotes arrive escaped: \"text\":\"Fix applied at).
captured_re='captured\\*"[[:space:]]*:[[:space:]]*(true|false)'
fix_applied='\\*"(text|tool_response)\\*"[[:space:]]*:[[:space:]]*\\*"Fix applied at '
fix_failed='\\*"(text|tool_response)\\*"[[:space:]]*:[[:space:]]*\\*"Error: '

msg_timeout="capture_error timed out without capturing an error (captured:false). This is expected with the current ahk server: capture_error returns only errors the server has queued, and (as of 2026-10) nothing queues them, so retrying or a longer timeout does not help. Also check the session: a script launched with /Debug is paused at its first line until you send action run (or a step), and it must connect to the listener's port (9000, or 9001+ when 9000 was busy: check action status and launch with /Debug=localhost:<port>, in Git Bash //Debug=localhost:<port>). To find a runtime error, run the script with mcp__ahk-mcp__run or mcp__ahk-mcp__test (or the engine CLI) and read its diagnostics, or use breakpoint_set, run, stack_trace and variables_get."
msg_captured="An error was captured. Next: call analyze_error with error set to the captured error object. It returns a Markdown prompt for you to analyze; there is no confidence score or suggested fix. Show the user your diagnosis first, then call apply_fix with file, line, original (the exact current text of that line) and replacement."
msg_fixed="apply_fix succeeded. Ask the user to re-run the script with /Debug to confirm the fix (the listener must be running: check action status). Note: apply_fix rewrites the whole file with LF line endings, so a CRLF file changes line endings; tell the user if the file used CRLF."
msg_fix_failed="apply_fix failed. On a Line mismatch the original text must equal the file's current line (compared after trimming whitespace): re-read that line with AHK_Debug_DBGp get_source (file, line) or the Read tool, then retry apply_fix with the exact text. apply_fix needs file, line, original and replacement, and edits only .ahk files."

msg=
case $action in
    capture_error)
        if [[ $event == PostToolUse && $payload =~ $captured_re ]]; then
            if [[ ${BASH_REMATCH[1]} == false ]]; then msg=$msg_timeout; else msg=$msg_captured; fi
        fi
        ;;
    apply_fix)
        if [[ $event == PostToolUseFailure ]]; then
            msg=$msg_fix_failed
        elif [[ $payload =~ $fix_applied ]]; then
            msg=$msg_fixed
        elif [[ $payload =~ $fix_failed ]]; then
            msg=$msg_fix_failed
        fi
        ;;
esac
[[ -n $msg ]] || exit 0

json_escape "$msg"
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$REPLY"
exit 0
