#!/usr/bin/env bash
# SessionStart hook: plain stdout (exit 0) is added to Claude's context.
#
# Prints a short, ASCII-only map of this fork's agent tooling. Engine and
# ahk-mcp facts are detected at runtime (an is_fork content scan, a PE header
# read for GUI vs console, and a few --version/--capabilities calls, each
# about 50 ms and capped at 2 s, so even the worst case stays well under
# the 10 s SessionStart timeout); everything else is static and must stay
# true. Engine order matches ahk-post-edit.sh: $AHK_CUSTOM_EXE only when set,
# else bin/AutoHotkey64Console.exe, else bin/AutoHotkey64.exe; an exe that is
# missing or not this fork's engine (see is_fork) is never run.
# Runs under Git Bash on Windows or any bash 4+; no python/jq.

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

runner=() limit=
tpath=$(command -v timeout 2>/dev/null)
if [[ $tpath == /usr/bin/* || $tpath == /bin/* ]]; then runner=(timeout 2); limit=" within 2 s"; fi

# Relative ./ form for paths inside the project.
show() { if [[ $1 == "$project"/* ]]; then REPLY=./${1:${#project}+1}; else REPLY=$1; fi; }
# is_fork EXE: status 0 when EXE may run as this fork's engine, else 1 with
# the reason in REPLY. A stock AutoHotkey takes "--version" or "check" as a
# script name and shows a modal "Script file not found" dialog, and it can
# live anywhere (Program Files, %LOCALAPPDATA%\Programs\AutoHotkey, a portable
# copy), so a Windows exe (MZ header) qualifies only if it contains the
# UTF-16 text "CHECK PASS" that the fork's check verb prints; stock builds
# have no check verb. That takes about 20 ms and ignores the path, so a fork
# build under Program Files is accepted. A "#!" wrapper script cannot be
# inspected: it is trusted unless it sits in a stock install folder.
is_fork() {
    local magic= p
    REPLY="not a readable file"
    [[ -f $1 && -r $1 ]] || return 1
    IFS= read -r -n 2 magic < "$1" 2>/dev/null
    case $magic in
    MZ)
        LC_ALL=C grep -qaP 'C\x00H\x00E\x00C\x00K\x00 \x00P\x00A\x00S\x00S\x00' "$1" 2>/dev/null
        case $? in
            0) return 0 ;;
            1) ;;
            *) LC_ALL=C grep -qa 'C.H.E.C.K. .P.A.S.S' "$1" 2>/dev/null && return 0 ;;  # grep without -P
        esac
        REPLY="a Windows exe without the fork's check verb, such as a stock AutoHotkey" ;;
    '#!')
        p=${1//\\//}; p=${p,,}
        [[ $p != *"/program files"*"/autohotkey/"* && $p != *"/appdata/local/programs/autohotkey/"* ]] && return 0
        REPLY="a script inside a stock AutoHotkey install folder" ;;
    *)
        REPLY="neither a Windows exe nor a #! script" ;;
    esac
    return 1
}
# gui_build EXE: status 0 for a GUI-subsystem build, which PowerShell neither
# waits for nor takes $LASTEXITCODE from unless its output is piped. A PE says
# so in its header (Subsystem at e_lfanew+92: 2 GUI, 3 console); anything else
# (a "#!" wrapper, no od) is judged by its name.
gui_build() {
    local magic= lf= ss=
    IFS= read -r -n 2 magic < "$1" 2>/dev/null
    if [[ $magic == MZ ]]; then
        lf=$(od -An -tu4 -j60 -N4 "$1" 2>/dev/null); lf=${lf//[[:space:]]/}
        if [[ $lf =~ ^[0-9]{1,7}$ ]]; then
            ss=$(od -An -tu2 -j$((lf + 92)) -N2 "$1" 2>/dev/null); ss=${ss//[[:space:]]/}
        fi
        [[ $ss == 2 ]] && return 0
        [[ $ss == 3 ]] && return 1
    fi
    [[ ${1##*/} == AutoHotkey64.exe || ${1##*/} == AutoHotkey32.exe ]]
}
# caps_state TEXT -> REPLY: current (lists processPipe), old (a capabilities
# answer without it: the build predates a551fcd4) or unknown (no answer).
caps_state() {
    if [[ $1 == *'"processPipe":true'* ]]; then REPLY=current
    elif [[ $1 == *'"kind":"capabilities"'* ]]; then REPLY=old
    else REPLY=unknown
    fi
}

# --- engine -----------------------------------------------------------------
engine= custom_bad= why= rejected=
if [[ -n $custom ]]; then
    if [[ ! -f $custom ]]; then
        custom_bad=missing
    elif ! is_fork "$custom"; then
        custom_bad=notfork why=$REPLY
    else
        engine=$custom
    fi
else
    for cand in "$project/bin/AutoHotkey64Console.exe" "$project/bin/AutoHotkey64.exe"; do
        [[ -f $cand ]] || continue
        is_fork "$cand" && { engine=$cand; break; }
        why=$REPLY; show "$cand"
        rejected+="${rejected:+; }$REPLY is not this fork's engine ($why), so the hooks never run it"
    done
fi

engine_lines=()
caps= gui=
if [[ -n $engine ]]; then
    show "$engine"; cli=$REPLY
    version=$("${runner[@]}" "$engine" --version 2>/dev/null)
    version=${version//$'\r'/}
    first=${version%%$'\n'*}
    rev_re='revision=([^ ]+)'
    rev=; [[ $version =~ $rev_re ]] && rev=${BASH_REMATCH[1]}
    caps=$("${runner[@]}" "$engine" --capabilities 2>/dev/null)
    engine_lines+=("Engine (hooks and examples): $cli = ${first:-unknown (no answer to --version$limit)}${rev:+, revision=$rev}")
    [[ -n $rejected ]] && engine_lines+=("  Skipped: $rejected.")
    caps_state "$caps"
    case $REPLY in
        old)
            engine_lines+=("  This build predates a551fcd4: its --capabilities lists no Inspect, ProcessPipe or --coverage, and its mcp verb lacks check/run/test. Rebuild per BUILD.md.") ;;
        unknown)
            engine_lines+=("  --capabilities gave no answer$limit (timed out or failed), so this build's features are unknown: run $cli --capabilities yourself before relying on Inspect, ProcessPipe or --coverage.") ;;
    esac
    if gui_build "$engine"; then
        gui=1
        missing=; [[ -z $custom && $engine == "$project/bin/AutoHotkey64.exe" ]] && missing=" (no usable bin/AutoHotkey64Console.exe)"
        engine_lines+=("  This is the GUI build$missing. PowerShell waits for a GUI exe and sets \$LASTEXITCODE only when its output is piped: see the PowerShell form below.")
    fi
    gate="enabled (engine: $cli)"
else
    cli=./bin/AutoHotkey64Console.exe
    if [[ $custom_bad == notfork ]]; then
        engine_lines+=("Engine: AHK_CUSTOM_EXE=$custom is not this fork's engine ($why), so the hooks never run it and the gate is disabled. Point AHK_CUSTOM_EXE at a fork build or unset it.")
        gate="DISABLED until AHK_CUSTOM_EXE names a fork engine"
    elif [[ $custom_bad == missing ]]; then
        engine_lines+=("Engine: AHK_CUSTOM_EXE=$custom does not exist, so the hooks treat the engine as unavailable. Fix or unset AHK_CUSTOM_EXE.")
        gate="DISABLED until AHK_CUSTOM_EXE names an existing engine"
    elif [[ -n $rejected ]]; then
        engine_lines+=("Engine: NOT FOUND. $rejected. Build the fork per BUILD.md.")
        gate="DISABLED until a fork engine is built"
    else
        engine_lines+=("Engine: NOT FOUND. bin/AutoHotkey64Console.exe and bin/AutoHotkey64.exe are absent (the engines in bin/ (bin/*.exe) are not in git, so a fresh clone has none). Build one per BUILD.md.")
        gate="DISABLED until an engine is built"
    fi
fi
# Command forms: ./bin/x.exe (Git Bash) and .\bin\x.exe (PowerShell); an
# absolute path with a space is quoted for each shell.
if [[ $cli == ./* ]]; then
    ps=".\\${cli#./}"; ps=${ps//\//\\}
else
    ps=${cli//\//\\}
    if [[ $cli == *" "* ]]; then ps="'$ps'"; cli="\"$cli\""; fi
fi
# PowerShell does not wait for a GUI-subsystem exe (nor update $LASTEXITCODE)
# unless its output is piped; "2>&1 | Out-String" waits and keeps the output.
if [[ -n $gui ]]; then
    ps_check="& $ps check /Diag=json file.ahk 2>&1 | Out-String, then read \$LASTEXITCODE (plain /Flags work; this GUI build needs the pipe: unpiped, PowerShell does not wait for it and \$LASTEXITCODE keeps the previous command's value)."
else
    ps_check="& $ps check /Diag=json file.ahk (plain /Flags work; \$LASTEXITCODE is the exit code)."
fi

# --- project MCP server (.mcp.json) ------------------------------------------
mcp_line=
mcp_json=
[[ -f $project/.mcp.json ]] && mcp_json=$(< "$project/.mcp.json")
cmd_re='"ahk-mcp"[^}]*"command"[[:space:]]*:[[:space:]]*"([^"]*)"'
if [[ $mcp_json =~ $cmd_re ]]; then
    mcp_cmd=${BASH_REMATCH[1]}
    if [[ $mcp_cmd =~ ^([A-Za-z]:|/) ]]; then mcp_exe=$mcp_cmd; else mcp_exe=$project/${mcp_cmd#./}; fi
    mcp_exe=${mcp_exe//\\//}
    if [[ ! -f $mcp_exe ]]; then
        mcp_line="- ahk-mcp (project .mcp.json runs: $mcp_cmd mcp): that exe does not exist, so the server and its tools (mcp__ahk-mcp__check, run, test, ...) are unavailable. Build per BUILD.md."
    elif [[ $mcp_exe != "$engine" ]] && ! is_fork "$mcp_exe"; then
        mcp_line="- ahk-mcp (project .mcp.json runs: $mcp_cmd mcp): that is not this fork's engine ($REPLY; a stock AutoHotkey has no mcp verb), so expect no mcp__ahk-mcp__check/run/test tools. Point .mcp.json at ./bin/AutoHotkey64Console.exe and build it per BUILD.md."
    else
        if [[ $mcp_exe == "$engine" ]]; then mcp_caps=$caps; else mcp_caps=$("${runner[@]}" "$mcp_exe" --capabilities 2>/dev/null); fi
        caps_state "$mcp_caps"
        case $REPLY in
            current)
                mcp_line="- ahk-mcp (project .mcp.json runs: $mcp_cmd mcp, the engine's native MCP server): ast_outline, source_outline, workspace_symbols, get_source_context, check, run, test, server_status. Prefer mcp__ahk-mcp__check / mcp__ahk-mcp__run / mcp__ahk-mcp__test for fork scripts (timeout_ms default 30000, 8 MiB output cap)." ;;
            old)
                mcp_line="- ahk-mcp (project .mcp.json runs: $mcp_cmd mcp): this build predates check/run/test (no mcp__ahk-mcp__check) and lists only ast_outline, source_outline, workspace_symbols, get_source_context, server_status. Use the engine CLI to check/run/test." ;;
            *)
                mcp_line="- ahk-mcp (project .mcp.json runs: $mcp_cmd mcp, the engine's native MCP server): its --capabilities gave no answer$limit, so whether it has check/run/test is unknown; mcp__ahk-mcp__server_status lists the live tools. A current build has ast_outline, source_outline, workspace_symbols, get_source_context, check, run, test, server_status: prefer mcp__ahk-mcp__check / run / test for fork scripts when they are listed." ;;
        esac
    fi
else
    mcp_line="- ahk-mcp: no ahk-mcp server entry found in .mcp.json, so there are no mcp__ahk-mcp__check/run/test tools."
fi

# --- output (ASCII only) -------------------------------------------------------
{
echo "## AutoHotkey fork: agent tooling (from .claude/hooks/ahk-debug-context.sh)"
echo
printf '%s\n' "${engine_lines[@]}"
cat <<EOF

### Engine CLI
- Git Bash (the Bash tool): $cli check --diag=json file.ahk
  Git Bash rewrites a bare /Flag argument into a path (/Diag=json becomes C:/Program Files/Git/Diag=json, then "Script file not found"). Use the aliases --diag=json, --headless, --eval, --trace, --coverage=PATH, --crashlog=PATH, --stderrfile=PATH; /Debug, /ErrorStdOut and /include have none, so double the slash: //Debug, //ErrorStdOut, //include. Pass scripts as relative or C:/... paths.
- PowerShell: $ps_check
- Verbs: check (load only), test, run, repl, mcp; --version, --capabilities. check and test imply headless.
EOF
cat <<'EOF'
- Exit codes: 0 ok, 10 runtime error, 11 critical, 12 parse/load, 13 check failed, 14 test failure, 64 usage, 130 interrupted (--capabilities is authoritative).
- check: 0 prints CHECK PASS. 13 is a syntax error, but also a missing script file ("Script file not found.", line 0) or a failed #DllLoad: read the message. Warnings print as "==> Warning:" on stderr with exit 0.
- --diag=json: NDJSON, one flat object per line {kind,severity,type,code,message,extra,file,line,...} on stderr (#Warn ..., StdOut sends warnings to stdout); the pass marker {"kind":"check","status":"pass"} is on stdout. Read both streams.
- test: 0 pass. An uncaught runtime error keeps 10 and a parse error 12; 14 comes only from ExitApp(14), a persistent script, or an exec failure.
- --headless (and check/test) only turn error dialogs into stderr text. MsgBox, InputBox and Gui still block: never run GUI/MsgBox scripts unattended; check them, or run a copy with MsgBox -> Print.
- check is not a sandbox: loading performs #DllLoad. Do not check or run untrusted scripts.
- Fork BIFs (no #Include): Print, Eval (needs #EnableEval or /Eval), JSON, Inspect, ProcessPipe, Check, TSParse (structure only, not a validity test), _ScriptGetLines, SyntaxError.

### MCP servers
EOF
echo "$mcp_line"
cat <<'EOF'
- ahk (user-wide Node server, if connected): only the core toolset is listed by default (AHK_Check, AHK_Run, AHK_Eval, AHK_File_View/List/Active/Edit/Create, AHK_Navigate, AHK_Doc_Search, AHK_Config, AHK_Settings). It runs scripts with the engine its AHK_PATH names: normally a stock AutoHotkey (the maintainer's was v2.1-alpha.32 as of 2026-10), not this fork unless AHK_PATH is repointed at this repo's bin\AutoHotkey64Console.exe. On a stock engine AHK_Run/AHK_Check/AHK_Eval do not see fork BIFs or directives such as #EnableEval (an error that Print does not exist gives it away), and AHK_Eval and the uia_* tools fail: use mcp__ahk-mcp__* or the engine CLI instead.
- Its debug (AHK_Debug_DBGp), uia (uia_*), library, extras and legacy toolsets stay hidden until AHK_Settings {"action":"enable_toolset","toolset":"debug"} (one toolset per call). That persists machine-wide in %APPDATA%\ahk-mcp\tool-settings.json: enable a toolset only when the user asks. Use the /uia skill before UI automation.

### DBGp debug loop (AHK_Debug_DBGp, debug toolset)
1. Call action start BEFORE the user launches the script. The listener uses port 9000 but silently moves to 9001+ when 9000 is busy: check action status.
EOF
cat <<EOF
2. The user launches with /Debug (bare = localhost:9000, else /Debug=localhost:<port>). PowerShell: & $ps /Debug script.ahk. Git Bash: $cli //Debug script.ahk (//Debug=localhost:<port>)
EOF
cat <<'EOF'
3. The script connects paused at its first line and waits there until you send action run (or step_into/step_over). Set line breakpoints (breakpoint_set with file, line) while it is paused there, then run (before the script connects, breakpoint_set fails with Not connected); while it is stopped use stack_trace, variables_get and evaluate.
4. capture_error returns only errors the ahk server has queued, and (as of 2026-10) nothing queues them, so expect captured:false; retrying or a longer timeout does not help. For an error's message, line and stack, run the script with mcp__ahk-mcp__run / mcp__ahk-mcp__test (or the engine CLI) and read the diagnostics. If an error is ever captured: analyze_error returns a Markdown prompt for you to analyze (no confidence score); show the user your diagnosis, then apply_fix (file, line, the exact current line as original, replacement) and have the user re-run.

### Hooks (.claude/settings.json)
EOF
echo "- Post-edit syntax gate, $gate: after Edit/Write/MultiEdit/AHK_File_Edit/AHK_File_Create of a .ahk file inside this project it runs check; a failure comes back as \"AHK syntax check failed (exit N)\" with the engine output. Fix it before moving on. Fixtures test_crashlog_parse*.ahk and test_parse_error*.ahk are skipped."
cat <<'EOF'
- AHK_Debug_DBGp calls get launch/port reminders (PreToolUse) and next-step guidance (PostToolUse, PostToolUseFailure).

### AHK v2 reminders
- := for assignment (never =); arrays are 1-based; ByRef is &var; ComObject() and Gui() objects.
- Parentheses on every call: Print("x"), never Print "x". The backtick is the escape character in strings; backslashes are literal.
EOF
} | LC_ALL=C tr -c '\n -~' '?'
exit 0
