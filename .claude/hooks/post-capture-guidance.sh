#!/usr/bin/env bash
# PostToolUse and PostToolUseFailure hook for mcp__ahk__AHK_Debug_DBGp (the
# user-wide ahk server's debug toolset, hidden until the user enables it).
#
# Adds next-step guidance after the key debug-loop results:
#   capture_error  {"captured":false,"reason":"timeout",...}
#                                          -> why: an older server build never
#                                             queues errors; else the run's end
#                                             was already learned (its error
#                                             returned, run said stopped), the
#                                             relaunch was refused by
#                                             #SingleInstance (old run still
#                                             alive: exit 64, never connects),
#                                             no error yet, not connected or
#                                             wrong port (plus a note when the
#                                             result has waiting_connections or
#                                             unconfirmed_reports)
#   capture_error  {"captured":false,"reason":"session_ended",...}
#                                          -> the script ended first (plus a
#                                             note on waiting_connections)
#   capture_error  {"captured":false,"reason":"not_listening"}
#                                          -> call start first
#   capture_error  {"captured":true,...}   -> analyze_error, then apply_fix
#   apply_fix      "Fix applied at ..."    -> ask the user to re-run
#   apply_fix      failure (PostToolUseFailure, "Line mismatch", "Error:")
#                                          -> re-read the line and retry
#   evaluate, or breakpoint_set with a condition, failing with "Command
#   timeout"                               -> an older server: no eval command,
#                                             no conditional breakpoints
#   start / status from a server without the capture fix (start's old
#   "/Debug your_script.ahk" hint; a status with errors_queued but no
#   error_capture)                         -> capture_error cannot capture
# The ahk-mcp capture fix (CLAUDE.md, DBGp Protocol, says where it lives) adds
# error_capture to status; the messages name that test, not a branch.
# Output is {"hookSpecificOutput":{"hookEventName":"<incoming event>",
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
# The outer "reason" of a captured:false result; exit.reason (ok, error, ...)
# never takes these values.
reason_re='reason\\*"[[:space:]]*:[[:space:]]*\\*"(timeout|session_ended|not_listening)\\*"'
fix_applied='\\*"(text|tool_response)\\*"[[:space:]]*:[[:space:]]*\\*"Fix applied at '
fix_failed='\\*"(text|tool_response)\\*"[[:space:]]*:[[:space:]]*\\*"Error: '
# Fields a fixed server adds to a timeout or session_ended result.
waiting_re='waiting_connections\\*"[[:space:]]*:'
unconfirmed_re='unconfirmed_reports\\*"[[:space:]]*:'
# An older server sends evaluate as an eval command and a condition after
# "--"; the engine has neither, and its reply is never matched. The tool then
# fails with "Error: Command timeout" (normally a PostToolUseFailure).
cmd_timeout='Command timeout'
cmd_timeout_text='\\*"(text|tool_response)\\*"[[:space:]]*:[[:space:]]*\\*"Error: Command timeout'
condition_re='"condition"[[:space:]]*:'
# A server without the capture fix: start tells the user to run a bare
# "/Debug your_script.ahk", and status has errors_queued but no error_capture.
old_start='/Debug your_script\.ahk'

msg_timeout="capture_error timed out without capturing an error (captured:false)."
msg_timeout_body=" If action status does not list error_capture, this ahk server lacks the ahk-mcp capture fix (see CLAUDE.md, DBGp Protocol) or was not restarted after a rebuild: it never queues an error, so retrying or a longer timeout does not help. With the fix, the usual causes are: you already learned how the last run ended (the previous capture_error returned its error, a run reply said Status: stopped, or clear_errors ran after the script had ended), and this call waited for a launch that has not happened (have the user relaunch, then call capture_error); the relaunch was refused because the previous run of the same script was still alive (paused, running or persistent): #SingleInstance refuses a second instance, and under /Headless it prints \"Another instance is already running\" and exits 64 without ever connecting, so send run (or stop) and let the old run exit before the user relaunches; no uncaught error was thrown in time (the script may still be running or waiting for input); or the script never connected. Check action status (connected, engine_state, session, port): the user must launch with /Debug=localhost:<port>, the port start or status reports (Git Bash: //Debug=localhost:<port>). To find a runtime error either way, run the script with mcp__ahk-mcp__run or mcp__ahk-mcp__test (or the engine CLI) and read its diagnostics, or use breakpoint_set, run, stack_trace and variables_get."
msg_timeout_waiting=" This result has waiting_connections: another script (or a copy of one with #SingleInstance Off) connected while a script is still attached, and it waits, paused at its first line, until that script ends (a persistent script, or one waiting for input, may never end). End the attached script, or call stop (which detaches every script, so all of them run on without the debugger), to let it run. A relaunch of the same script is never counted here: #SingleInstance refuses it while the old run is alive."
msg_timeout_unconfirmed=" This result has unconfirmed_reports: the engine printed an error report but the script kept running. A report becomes a capture if the script then exits with an error and is dropped if it exits normally (OutputDebug text in the report format looks the same)."
msg_ended="capture_error returned session_ended: the script ended (or detached) with no further error to return; session is the run that ended. exit holds the engine's final status and reason: reason ok means it finished without an unhandled error, reason error means it ended on one (usually the error an earlier capture_error already returned). A script that ended while nobody waited is reported this way once, by the next capture_error, unless a run reply already said it stopped, one of its errors was returned, or clear_errors ran after it ended (clear_errors drops queued errors and a remembered end; a script that ends after clear_errors is still reported once): then capture_error waits for a relaunch instead. If you expected an error that was not captured, run the script with mcp__ahk-mcp__run or mcp__ahk-mcp__test and read its diagnostics, or set a breakpoint before the suspect line. To try again, have the user relaunch with /Debug=localhost:<port> (the port action status reports) and call capture_error: it waits for the new run."
msg_ended_waiting=" This result has waiting_connections: the next script that connected meanwhile is attached now, paused at its first line; call capture_error (or run) to run it."
msg_not_listening="capture_error returned not_listening: no DBGp listener is running. Call action start, note the port it reports, have the user launch the script with /Debug=localhost:<port> (Git Bash: //Debug=localhost:<port>), then call capture_error again."
msg_captured="An error was captured (error.session is the run it came from; one older than action status session is a leftover from an earlier run, and clear_errors drops those). Next: call analyze_error with error set to the captured error object. It returns a Markdown prompt for you to analyze; there is no confidence score or suggested fix. error.line is AutoHotkey's Error.Line (the caller's line when error.what names a function); stack_trace[0] is where the throw ran, the line this fork's own stderr report names. detected_by stderr has no stack or variables, unconfirmed:true (the connection was lost before the engine confirmed the report) can be OutputDebug text rather than an error, and unverified_fields names fields the engine may have garbled. If a step stopped the script at this throw, it is still paused there: send run and let it exit before the user relaunches (#SingleInstance refuses a relaunch of the same script while it is alive). Show the user your diagnosis first, then call apply_fix with file, line, original (the exact current text of that line) and replacement."
msg_fixed="apply_fix succeeded. Ask the user to re-run the script with /Debug=localhost:<port> to confirm the fix (the listener must still be running: check action status; with no listener on that port the engine prints \"Debugger error: Could not connect to localhost:<port>; continuing without the debugger.\" and runs the script without the debugger, so nothing is captured; an engine older than f14d7427 shows a modal box instead), then call capture_error: the relaunched script waits paused at its first line until run or capture_error, and on a server with the capture fix capture_error resumes it and returns session_ended with exit reason ok when the script finishes cleanly. The old run must have exited first: while it is alive (paused at a breakpoint or at a throw after a step, still running, or persistent), #SingleInstance refuses the relaunch, which under /Headless prints \"Another instance is already running...\" and exits 64 without connecting (capture_error then times out, or returns the old run's session_ended, which says nothing about the fix). So send run (or stop, which detaches it; then call start again) and let it exit; a persistent script must be closed. capture_error returns any error still queued first: clear_errors drops those before the relaunch. Note: apply_fix rewrites the whole file with LF line endings, so a CRLF file changes line endings; tell the user if the file used CRLF."
msg_fix_failed="apply_fix failed. On a Line mismatch the original text must equal the file's current line (compared after trimming whitespace): re-read that line with AHK_Debug_DBGp get_source (file, line) or the Read tool, then retry apply_fix with the exact text. apply_fix needs file, line, original and replacement, and edits only .ahk files."
msg_eval_timeout="evaluate failed with Command timeout. AutoHotkey's debugger has no eval command, and an ahk server without the ahk-mcp capture fix sends one anyway and then waits 10 s for a reply it cannot match, so its evaluate always fails this way (action status without error_capture confirms that build). Read values with variables_get (context 0 local, 1 global) instead. A server with the fix reads a variable or property path (x, obj.prop, arr[1]) and rejects operators at once."
msg_cond_timeout="breakpoint_set failed with Command timeout. AutoHotkey has no conditional breakpoints, and an ahk server without the ahk-mcp capture fix sends the condition anyway and then waits 10 s for a reply it cannot match. Set the breakpoint again with file and line only."
msg_old_build="This ahk server lacks the ahk-mcp capture fix (see CLAUDE.md, DBGp Protocol) or was not restarted after a rebuild: its capture_error never captures and always times out with captured:false, its evaluate (and a breakpoint_set with a condition) fails with Command timeout after 10 s, and start ignores its port argument. Read values with variables_get; find runtime errors with breakpoint_set, run, stack_trace and variables_get, or run the script with mcp__ahk-mcp__run or mcp__ahk-mcp__test. Have the user launch with /Debug=localhost:<port>, the port start reported (a bare /Debug always means 9000)."

msg=
case $action in
    capture_error)
        if [[ $event == PostToolUse && $payload =~ $captured_re ]]; then
            if [[ ${BASH_REMATCH[1]} == true ]]; then
                msg=$msg_captured
            elif [[ $payload =~ $reason_re ]]; then
                case ${BASH_REMATCH[1]} in
                    session_ended)
                        msg=$msg_ended
                        [[ $payload =~ $waiting_re ]] && msg+=$msg_ended_waiting ;;
                    not_listening) msg=$msg_not_listening ;;
                    *) msg=timeout ;;
                esac
            else
                msg=timeout
            fi
            if [[ $msg == timeout ]]; then
                msg=$msg_timeout
                [[ $payload =~ $waiting_re ]] && msg+=$msg_timeout_waiting
                [[ $payload =~ $unconfirmed_re ]] && msg+=$msg_timeout_unconfirmed
                msg+=$msg_timeout_body
            fi
        fi
        ;;
    evaluate|breakpoint_set)
        if [[ ($event == PostToolUseFailure && $payload =~ $cmd_timeout) || $payload =~ $cmd_timeout_text ]]; then
            if [[ $action == evaluate ]]; then
                msg=$msg_eval_timeout
            elif [[ $payload =~ $condition_re ]]; then
                msg=$msg_cond_timeout
            fi
        fi
        ;;
    start)
        [[ $event == PostToolUse && $payload =~ $old_start ]] && msg=$msg_old_build
        ;;
    status)
        if [[ $event == PostToolUse && $payload =~ errors_queued && ! $payload =~ error_capture ]]; then
            msg=$msg_old_build
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
