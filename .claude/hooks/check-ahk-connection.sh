#!/usr/bin/env bash
# PreToolUse hook for mcp__ahk__AHK_Debug_DBGp (the user-wide ahk server's
# debug toolset, hidden until the user enables it).
#
# For actions that need a script connected to the DBGp listener, add a
# launch/port reminder through
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"..."}}
# and exit 0. start/stop/status and every other action: no output, exit 0.
# This hook never blocks the tool (it never exits 2).
#
# The launch commands name the engine the other hooks use: $AHK_CUSTOM_EXE
# when set (and an existing fork engine, see is_fork), else
# bin/AutoHotkey64Console.exe, else bin/AutoHotkey64.exe. When none is usable
# they name ./bin/AutoHotkey64Console.exe and say why: AHK_CUSTOM_EXE is
# missing or not a fork engine (fix or unset it), or no engine is built.
#
# Runs under Git Bash on Windows or any bash 4+; no python/jq. Output is ASCII.

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

if json_raw hook_event_name "$payload" && [[ $REPLY != PreToolUse ]]; then
    exit 0
fi
json_raw tool_name "$payload" || exit 0
[[ $REPLY == *AHK_Debug_DBGp ]] || exit 0
tool_input_action "$payload" || exit 0
action=$REPLY
[[ $action =~ ^[a-z_]+$ ]] || exit 0

case $action in
    capture_error)
        lead="capture_error waits up to its timeout (default 30000 ms) for an error the ahk server has queued, but (as of 2026-10) nothing queues errors, so expect captured:false. For an error's message, line and stack, run the script with mcp__ahk-mcp__run or mcp__ahk-mcp__test instead, or use breakpoint_set, run and stack_trace." ;;
    run|step_into|step_over|step_out|variables_get|evaluate|stack_trace|breakpoint_*)
        lead="AHK_Debug_DBGp $action needs a script connected to the DBGp listener." ;;
    *)
        exit 0 ;;
esac

# --- engine for the launch commands -------------------------------------------
project=${CLAUDE_PROJECT_DIR:-}
if [[ -z $project ]]; then
    project=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)
fi
custom=${AHK_CUSTOM_EXE:-}
if command -v cygpath >/dev/null 2>&1; then
    mixed=$(cygpath -m "$project" ${custom:+"$custom"} 2>/dev/null)
    project=${mixed%%$'\n'*}
    [[ -n $custom ]] && custom=${mixed#*$'\n'}
else
    project=${project//\\//}
    custom=${custom//\\//}
fi
project=${project%/}
# is_fork EXE: status 0 when EXE may run as this fork's engine (the same test
# as ahk-post-edit.sh). A stock AutoHotkey can live anywhere, so a Windows exe
# (MZ header) qualifies only if it contains the UTF-16 text "CHECK PASS" that
# the fork's check verb prints; stock builds have no check verb. A "#!"
# wrapper script is trusted unless it sits in a stock install folder.
is_fork() {
    local magic= p
    [[ -f $1 && -r $1 ]] || return 1
    IFS= read -r -n 2 magic < "$1" 2>/dev/null
    case $magic in
    MZ)
        LC_ALL=C grep -qaP 'C\x00H\x00E\x00C\x00K\x00 \x00P\x00A\x00S\x00S\x00' "$1" 2>/dev/null
        case $? in
            0) return 0 ;;
            1) return 1 ;;
        esac
        LC_ALL=C grep -qa 'C.H.E.C.K. .P.A.S.S' "$1" 2>/dev/null ;;   # grep without -P
    '#!')
        p=${1//\\//}; p=${p,,}
        [[ $p != *"/program files"*"/autohotkey/"* && $p != *"/appdata/local/programs/autohotkey/"* ]] ;;
    *)
        return 1 ;;
    esac
}
engine=
if [[ -n $custom ]]; then
    is_fork "$custom" && engine=$custom
else
    for cand in "$project/bin/AutoHotkey64Console.exe" "$project/bin/AutoHotkey64.exe"; do
        if is_fork "$cand"; then engine=$cand; break; fi
    done
fi
note=
if [[ -z $engine ]]; then
    cli=./bin/AutoHotkey64Console.exe
    if [[ -z $custom ]]; then
        note=" (no usable fork engine was found: build one per BUILD.md)"
    elif [[ -f $custom ]]; then
        note=" (these name the default engine: AHK_CUSTOM_EXE=$custom is not this fork's engine, so the hooks never run it: fix or unset AHK_CUSTOM_EXE)"
    else
        note=" (these name the default engine: AHK_CUSTOM_EXE=$custom does not exist: fix or unset AHK_CUSTOM_EXE)"
    fi
elif [[ -n $project && $engine == "$project"/* ]]; then
    cli=./${engine:${#project}+1}
else
    cli=$engine
fi
if [[ $cli == ./* ]]; then
    ps=".\\${cli#./}"; ps=${ps//\//\\}
else
    ps=${cli//\//\\}
    if [[ $cli == *" "* ]]; then ps="'$ps'"; cli="\"$cli\""; fi
fi

msg="$lead The listener (action start) must already be running before the user launches the script with /Debug."
msg+=" PowerShell: & $ps /Debug script.ahk ; Git Bash: $cli //Debug script.ahk (Git Bash rewrites a bare /Debug into a path)$note."
msg+=" Once connected, the script is paused at its first line until you send action run (or step_into/step_over)."
msg+=" A bare /Debug connects to localhost:9000. The listener uses port 9000 by default but silently moves to 9001+ when 9000 is busy, so check action status and, if it moved, launch with /Debug=localhost:<port> (Git Bash: //Debug=localhost:<port>)."
msg+=" A VS Code AutoHotkey debug session runs its own separate DBGp listener on its own configured port."

json_escape "$msg"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$REPLY" |
    LC_ALL=C tr -c '\n -~' '?'
exit 0
