#!/usr/bin/env bash
# test-hooks.sh - contract tests for the Claude Code hooks in this directory.
#
#   bash .claude/hooks/test-hooks.sh       (Git Bash on Windows, or any bash 4+)
#
# Every hook runs the way Claude Code runs it: `bash <hook>` with a JSON
# payload on stdin and CLAUDE_PROJECT_DIR exported. Exit code, stdout and
# stderr are captured and asserted separately against the contract in
# README.md. Needs no jq, python or cmd.exe: JSON output is checked by the
# small bash parser below.
#
# Cases that need the real fork engine pick it the way the hooks do
# (AHK_CUSTOM_EXE when set, else bin/AutoHotkey64Console.exe, else
# bin/AutoHotkey64.exe, each only if it passes the hooks' is_fork content
# test) and are SKIPPED, loudly, only when no fork engine is usable. The
# harness never executes a file that fails is_fork: a stock AutoHotkey takes
# --version or check as a script name and shows a modal dialog. Every other
# case uses throwaway fake engines ("#!" scripts that log their calls, and
# non-executable MZ lookalikes of a stock exe), so it runs anywhere.
# Scratch files live in a private `mktemp -d` directory (TMPDIR is honoured)
# that is removed on exit; nothing in the repository is written.
#
# Output: "=== section ===" headers, one "PASS <case>", "FAIL <case>" or
# "SKIP <case> -- <reason>" line per case (test-hooks-gui.ahk parses these),
# then "RESULT: ...". Set NO_COLOR=1 to disable colour on a terminal.
# Exit status: the number of failed cases (at most 254); 255 means the
# harness could not run at all (a FATAL line says why).

if [[ -z ${BASH_VERSINFO[0]:-} ]] || (( BASH_VERSINFO[0] < 4 )); then
    echo "FATAL: bash 4 or newer is required (this is ${BASH_VERSION:-not bash})"
    exit 255
fi

HOOKS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || { echo "FATAL: cannot locate the hooks directory"; exit 255; }
REPO=$(cd "$HOOKS_DIR/../.." && pwd) || { echo "FATAL: cannot locate the repository"; exit 255; }

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    C_PASS=$'\e[32m' C_FAIL=$'\e[31m' C_SKIP=$'\e[33m' C_HEAD=$'\e[1m' C_OFF=$'\e[0m'
else
    C_PASS= C_FAIL= C_SKIP= C_HEAD= C_OFF=
fi

# --- platform helpers ----------------------------------------------------------
if command -v cygpath >/dev/null 2>&1; then ON_WINDOWS=1; else ON_WINDOWS=0; fi
to_win()   { if (( ON_WINDOWS )); then REPLY=$(cygpath -w "$1"); else REPLY=$1; fi; }
to_mixed() { if (( ON_WINDOWS )); then REPLY=$(cygpath -m "$1"); else REPLY=$1; fi; }
to_unix()  { if (( ON_WINDOWS )); then REPLY=$(cygpath -u "$1"); else REPLY=$1; fi; }

now_us() {    # microseconds -> REPLY
    if [[ -n ${EPOCHREALTIME:-} ]]; then
        REPLY=${EPOCHREALTIME/[.,]/}
    else
        REPLY=$(date +%s%N 2>/dev/null)
        if [[ $REPLY =~ ^[0-9]{16,}$ ]]; then REPLY=$(( REPLY / 1000 )); else REPLY=$(( SECONDS * 1000000 )); fi
    fi
}

# --- scratch directory ---------------------------------------------------------
WORK=$(mktemp -d "${TMPDIR:-/tmp}/hooktest.XXXXXX" 2>/dev/null) || WORK=$(mktemp -d 2>/dev/null)
[[ -n $WORK && -d $WORK ]] || { echo "FATAL: mktemp -d failed"; exit 255; }
WORK=$(cd "$WORK" && pwd)
to_mixed "$WORK"; work_m=$REPLY; to_mixed "$REPO"; repo_m=$REPLY
if [[ "${work_m,,}/" == "${repo_m,,}/"* ]]; then
    rm -rf "$WORK"
    echo "FATAL: the scratch directory $WORK is inside the repository; point TMPDIR elsewhere"
    exit 255
fi
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM

# --- JSON parser (validates; flattens into JT/JV/JK) ---------------------------
# json_parse TEXT succeeds only when TEXT is exactly one JSON value. Paths are
# R, R.key, R.key[0], ...; JT[path] is the type, JV[path] the decoded scalar
# (or an array's length), JK[path] an object's keys, one per line.
declare -A JT JV JK
_JS_RE='^"(([^"\[:cntrl:]]|\\["\/bfnrt]|\\u[0-9A-Fa-f]{4})*)"'
_JN_RE='^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?'
_jp_ws() { [[ $_J =~ ^[[:space:]]+ ]] && _J=${_J:${#BASH_REMATCH[0]}}; return 0; }
_jp_unescape() {
    local s=$1
    s=${s//\\\\/$'\001'}; s=${s//\\\"/\"}; s=${s//\\\//\/}
    s=${s//\\n/$'\n'}; s=${s//\\t/$'\t'}; s=${s//\\r/$'\r'}; s=${s//\\b/$'\b'}; s=${s//\\f/$'\f'}
    REPLY=${s//$'\001'/\\}
}
_jp_string() {
    [[ $_J =~ $_JS_RE ]] || return 1
    _J=${_J:${#BASH_REMATCH[0]}}
    _jp_unescape "${BASH_REMATCH[1]}"
}
_jp_value() {
    local path=$1 key i
    _jp_ws
    case ${_J:0:1} in
    '{') _J=${_J:1}; JT[$path]=object; JK[$path]=; _jp_ws
         if [[ ${_J:0:1} == '}' ]]; then _J=${_J:1}; return 0; fi
         while :; do
             _jp_ws; _jp_string || return 1; key=$REPLY
             _jp_ws; [[ ${_J:0:1} == : ]] || return 1; _J=${_J:1}
             JK[$path]+=$key$'\n'
             _jp_value "$path.$key" || return 1
             _jp_ws
             case ${_J:0:1} in ,) _J=${_J:1} ;; '}') _J=${_J:1}; return 0 ;; *) return 1 ;; esac
         done ;;
    '[') _J=${_J:1}; JT[$path]=array; i=0; _jp_ws
         if [[ ${_J:0:1} == ']' ]]; then _J=${_J:1}; JV[$path]=0; return 0; fi
         while :; do
             _jp_value "$path[$i]" || return 1; i=$((i + 1))
             _jp_ws
             case ${_J:0:1} in ,) _J=${_J:1} ;; ']') _J=${_J:1}; JV[$path]=$i; return 0 ;; *) return 1 ;; esac
         done ;;
    '"') _jp_string || return 1; JT[$path]=string; JV[$path]=$REPLY ;;
    t|f|n) [[ $_J =~ ^(true|false|null) ]] || return 1
         JT[$path]=${BASH_REMATCH[1]}; JV[$path]=${BASH_REMATCH[1]}; _J=${_J:${#BASH_REMATCH[0]}} ;;
    *)   [[ $_J =~ $_JN_RE ]] || return 1
         JT[$path]=number; JV[$path]=${BASH_REMATCH[0]}; _J=${_J:${#BASH_REMATCH[0]}} ;;
    esac
}
json_parse() {
    JT=(); JV=(); JK=(); _J=$1
    _jp_value R || return 1
    _jp_ws
    [[ -z $_J ]]
}

# jesc TEXT -> REPLY: TEXT as the inside of a JSON string literal.
jesc() {
    local s=$1
    s=${s//\\/\\\\}; s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
    REPLY=$s
}

# --- cases and results ---------------------------------------------------------
PASSED=0 FAILED=0 SKIPPED=0 ENGINE_SKIPS=0
CASE= RAN=0 OUT= ERR= CTX= RC= MS=0
ERRS=()

section() { printf '\n%s=== %s ===%s\n' "$C_HEAD" "$1" "$C_OFF"; }
snip() {      # one sanitized line for failure reports -> REPLY
    local s=${1//$'\r'/\\r}
    s=${s//$'\n'/ | }
    (( ${#s} > 240 )) && s="${s:0:240}..."
    REPLY=$(printf '%s' "$s" | LC_ALL=C tr -c ' -~' '?')
}
t_begin() { CASE=$1; ERRS=(); RAN=0; }
bad() { ERRS+=("$*"); }
t_end() {
    local e
    if (( ${#ERRS[@]} == 0 )); then
        PASSED=$((PASSED + 1))
        printf '  %sPASS%s %s\n' "$C_PASS" "$C_OFF" "$CASE"
    else
        FAILED=$((FAILED + 1))
        printf '  %sFAIL%s %s\n' "$C_FAIL" "$C_OFF" "$CASE"
        for e in "${ERRS[@]}"; do snip "$e"; printf '       - %s\n' "$REPLY"; done
        if (( RAN )); then
            snip "$OUT"; printf '       stdout: %s\n' "${REPLY:-<empty>}"
            snip "$ERR"; printf '       stderr: %s\n' "${REPLY:-<empty>}"
        fi
    fi
}
skip() {
    SKIPPED=$((SKIPPED + 1))
    printf '  %sSKIP%s %s -- %s\n' "$C_SKIP" "$C_OFF" "$1" "$2"
}

# --- running a hook ------------------------------------------------------------
# Claude Code runs: bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<name>". On Windows
# CLAUDE_PROJECT_DIR is a C:\ path, so use the same mixed-separator form.
if (( ON_WINDOWS )); then to_win "$REPO"; HOOK_BASE="$REPLY/.claude/hooks"; else HOOK_BASE=$HOOKS_DIR; fi
RUNNER=()
command -v timeout >/dev/null 2>&1 && RUNNER=(timeout 60)

# Environment for the next run: CLAUDE_PROJECT_DIR=$H_PROJECT and
# AHK_CUSTOM_EXE=$H_CUSTOM, where "-" leaves the variable unset.
H_PROJECT=- H_CUSTOM=-
# run HOOK PAYLOAD -> RC, OUT, ERR (trailing newlines trimmed), MS
run() {
    local t0
    RAN=1; CTX=
    now_us; t0=$REPLY
    (
        cd "$WORK" || exit 99
        if [[ $H_PROJECT == - ]]; then unset CLAUDE_PROJECT_DIR; else export CLAUDE_PROJECT_DIR=$H_PROJECT; fi
        if [[ $H_CUSTOM == - ]]; then unset AHK_CUSTOM_EXE; else export AHK_CUSTOM_EXE=$H_CUSTOM; fi
        printf '%s' "$2" | "${RUNNER[@]}" bash "$HOOK_BASE/$1" >"$WORK/hook.out" 2>"$WORK/hook.err"
    )
    RC=$?
    now_us; MS=$(( (REPLY - t0) / 1000 ))
    OUT=$(<"$WORK/hook.out"); ERR=$(<"$WORK/hook.err")
}

# --- expectations on the last run ----------------------------------------------
want_rc()      { [[ $RC == "$1" ]] || bad "exit code $RC, want $1"; }
want_no_out()  { [[ -z $OUT ]] || bad "stdout should be empty"; }
want_no_err()  { [[ -z $ERR ]] || bad "stderr should be empty"; }
want_silent()  { want_rc 0; want_no_out; want_no_err; }
_stream() { case $1 in out) S_TEXT=$OUT S_NAME=stdout ;; err) S_TEXT=$ERR S_NAME=stderr ;; *) S_TEXT=$CTX S_NAME=additionalContext ;; esac; }
want_has()   { local n; _stream "$1"; shift; for n; do [[ $S_TEXT == *"$n"* ]] || bad "$S_NAME lacks \"$n\""; done; }
want_hasi()  { local n; _stream "$1"; shift; for n; do [[ ${S_TEXT,,} == *"${n,,}"* ]] || bad "$S_NAME lacks \"$n\" (any case)"; done; }
want_lacks() { local n; _stream "$1"; shift; for n; do [[ $S_TEXT != *"$n"* ]] || bad "$S_NAME contains \"$n\""; done; }
want_lacksi() { local n; _stream "$1"; shift; for n; do [[ ${S_TEXT,,} != *"${n,,}"* ]] || bad "$S_NAME contains \"$n\" (any case)"; done; }
count_lines() { local -a l; [[ -z $1 ]] && { REPLY=0; return; }; mapfile -t l <<< "$1"; REPLY=${#l[@]}; }
want_ascii() {    # raw stdout/stderr bytes: printable ASCII, tab and LF only
    local f n
    for f in out err; do
        n=$(LC_ALL=C tr -d '\t\n -~' < "$WORK/hook.$f" | wc -c)
        (( n == 0 )) || bad "std$f has $((n)) non-ASCII or control bytes (CR included)"
    done
}
want_fast() { (( MS < $1 )) || bad "took ${MS} ms, limit $1 ms"; }

# want_hso EVENT: stdout is exactly one JSON object whose additionalContext is
# inside hookSpecificOutput (never top level) with hookEventName EVENT. Sets
# CTX to the decoded additionalContext.
TOP_KEYS=' continue suppressOutput stopReason decision systemMessage reason hookSpecificOutput '
want_hso() {
    local k
    CTX=
    if ! json_parse "$OUT"; then bad "stdout is not exactly one JSON value"; return; fi
    [[ ${JT[R]} == object ]] || { bad "stdout JSON is not an object"; return; }
    while IFS= read -r k; do
        [[ -z $k ]] && continue
        if [[ $k == additionalContext ]]; then
            bad "top-level additionalContext (Claude Code ignores it; it belongs in hookSpecificOutput)"
        elif [[ $TOP_KEYS != *" $k "* ]]; then
            bad "unknown top-level key \"$k\""
        fi
    done <<< "${JK[R]}"
    [[ ${JT[R.hookSpecificOutput]:-} == object ]] || { bad "no hookSpecificOutput object"; return; }
    [[ ${JV[R.hookSpecificOutput.hookEventName]:-} == "$1" ]] ||
        bad "hookSpecificOutput.hookEventName is \"${JV[R.hookSpecificOutput.hookEventName]:-}\", want \"$1\""
    if [[ ${JT[R.hookSpecificOutput.additionalContext]:-} == string && -n ${JV[R.hookSpecificOutput.additionalContext]} ]]; then
        CTX=${JV[R.hookSpecificOutput.additionalContext]}
    else
        bad "hookSpecificOutput.additionalContext is missing or empty"
    fi
}

# --- payloads shaped like Claude Code's ------------------------------------------
to_win "$REPO"; jesc "$REPLY"; J_CWD=$REPLY
J_TRANSCRIPT='C:\\Users\\tester\\.claude\\projects\\hooktest\\0001.jsonl'

# envelope EVENT TOOL INPUT_JSON [MORE_FIELDS] -> REPLY
envelope() {
    REPLY="{\"session_id\":\"hooktest-0001\",\"transcript_path\":\"$J_TRANSCRIPT\",\"cwd\":\"$J_CWD\",\"permission_mode\":\"default\",\"hook_event_name\":\"$1\",\"tool_name\":\"$2\",\"tool_input\":$3${4:+,$4},\"tool_use_id\":\"toolu_hooktest\"}"
}
# text_blocks TEXT... -> REPLY: an MCP content array
text_blocks() {
    local t out=
    for t; do jesc "$t"; out+="${out:+,}{\"type\":\"text\",\"text\":\"$REPLY\"}"; done
    REPLY="[$out]"
}
# edit_payload TOOL PATH -> REPLY: PostToolUse payload of an edit-family tool
edit_payload() {
    local tool=$1 p in resp
    jesc "$2"; p=$REPLY
    case $tool in
    Edit)
        in="{\"file_path\":\"$p\",\"old_string\":\"x := 1\",\"new_string\":\"x := Abs(\",\"replace_all\":false}"
        resp="\"tool_response\":{\"filePath\":\"$p\",\"oldString\":\"x := 1\",\"newString\":\"x := Abs(\",\"originalFile\":\"x := 1\\n\",\"structuredPatch\":[{\"oldStart\":1,\"oldLines\":1,\"newStart\":1,\"newLines\":1,\"lines\":[\"-x := 1\",\"+x := Abs(\"]}],\"userModified\":false,\"replaceAll\":false}" ;;
    Write)
        in="{\"file_path\":\"$p\",\"content\":\"x := Abs(\\n\"}"
        resp="\"tool_response\":{\"type\":\"update\",\"filePath\":\"$p\",\"content\":\"x := Abs(\\n\",\"structuredPatch\":[]}" ;;
    MultiEdit)
        in="{\"file_path\":\"$p\",\"edits\":[{\"old_string\":\"x := 1\",\"new_string\":\"x := Abs(\",\"replace_all\":false}]}"
        resp="\"tool_response\":{\"filePath\":\"$p\",\"edits\":[{\"old_string\":\"x := 1\",\"new_string\":\"x := Abs(\",\"replace_all\":false}],\"originalFileContents\":\"x := 1\\n\",\"structuredPatch\":[],\"userModified\":false}" ;;
    NotebookEdit)
        in="{\"notebook_path\":\"$p\",\"cell_id\":\"cell-1\",\"new_source\":\"x := Abs(\",\"edit_mode\":\"replace\"}"
        resp="\"tool_response\":{\"new_source\":\"x := Abs(\",\"cell_id\":\"cell-1\",\"edit_mode\":\"replace\"}" ;;
    mcp__ahk__AHK_File_Edit)
        in="{\"action\":\"replace\",\"search\":\"x := 1\",\"newContent\":\"x := Abs(\",\"filePath\":\"$p\"}"
        text_blocks "**Edit Successful**"$'\n\n'"**File:** $2"$'\n'"**Operation:** Replaced 1 occurrence"$'\n'
        resp="\"tool_response\":$REPLY" ;;
    mcp__ahk__AHK_File_Create)
        in="{\"filePath\":\"$p\",\"content\":\"x := Abs(\\n\",\"overwrite\":true}"
        text_blocks "AutoHotkey file created successfully." "{"$'\n'"  \"filePath\": \"$p\","$'\n'"  \"dryRun\": false"$'\n'"}"
        resp="\"tool_response\":$REPLY" ;;
    esac
    envelope PostToolUse "$tool" "$in" "$resp"
}
# dbgp EVENT ACTION [MORE_FIELDS] -> REPLY: an mcp__ahk__AHK_Debug_DBGp payload
dbgp() { envelope "$1" mcp__ahk__AHK_Debug_DBGp "{\"action\":\"$2\"}" "${3:-}"; }

# --- fake engines ----------------------------------------------------------------
# make_engine PATH RC OUTPUT: an executable stand-in for the AutoHotkey engine.
# It logs "<argv0>|<arg1>|<arg2>" to $CALLS, answers --version and
# --capabilities, and otherwise prints OUTPUT (@FILE@ = its 2nd argument) to
# stderr and exits with RC.
CALLS=$WORK/engine-calls.log
make_engine() {
    mkdir -p "${1%/*}"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'log=%q rc=%q out=%q\n' "$CALLS" "$2" "${3:-}"
        cat <<'EOS'
printf '%s|%s|%s\n' "$0" "${1:-}" "${2:-}" >> "$log"
case ${1:-} in
    --version) printf 'AutoHotkey v9.9.9-fake+Console\nrevision=fake0000 compiler=none architecture=x64\n'; exit 0 ;;
    --capabilities) printf '{"processPipe":true}\n'; exit 0 ;;
esac
[[ -n $out ]] && printf '%s\n' "${out//@FILE@/${2:-}}" >&2
exit "$rc"
EOS
    } > "$1"
    chmod +x "$1"
}
calls_reset() { : > "$CALLS"; }
# want_called FRAGMENT [FILE]: the engine ran once, its path contains FRAGMENT,
# its arguments were: check FILE
want_called() {
    local n c0 c1 c2
    n=$(wc -l < "$CALLS")
    (( n == 1 )) || { bad "the engine ran $((n)) times, want once"; (( n == 0 )) && return; }
    IFS='|' read -r c0 c1 c2 < "$CALLS"
    [[ $c0 == *"$1"* ]] || bad "ran engine $c0, want one matching *$1*"
    [[ $c1 == check ]] || bad "engine verb \"$c1\", want check"
    if [[ -n ${2:-} ]]; then
        if (( ON_WINDOWS )); then    # Windows paths compare case-insensitively
            [[ ${c2,,} == "${2,,}" ]] || bad "engine file argument \"$c2\", want \"$2\""
        else
            [[ $c2 == "$2" ]] || bad "engine file argument \"$c2\", want \"$2\""
        fi
    fi
}
want_not_called() { [[ ! -s $CALLS ]] || bad "the engine ran: $(head -n 1 "$CALLS")"; }

# want_blocked REL [EXIT]: exit 2, nothing on stdout, and the gate's stderr
# report for REL (the path relative to the project).
want_blocked() {
    local first
    want_rc 2; want_no_out; want_ascii
    first=${ERR%%$'\n'*}
    [[ $first == "AHK syntax check failed (exit ${2:-13}) for $1:" ]] ||
        bad "first stderr line is \"$first\", want \"AHK syntax check failed (exit ${2:-13}) for $1:\""
    want_hasi err "re-check"
}
# want_note: a non-blocking engine problem: exit 1 and one stderr line.
want_note() {
    want_rc 1; want_no_out; want_ascii
    count_lines "$ERR"
    (( REPLY == 1 )) || bad "stderr has $REPLY lines, want exactly 1"
    want_lacks err "syntax check failed"
}

# =================================================================================
# Fixtures
# =================================================================================
P=$WORK/proj                         # the temporary project for most cases
NONASCII=$'caf\xc3\xa9 bad.ahk'     # "cafe" with an e-acute, plus a space
mkdir -p "$P/deep/nested" "$P/sub dir" "$WORK/projx" "$WORK/outside" "$WORK/noengine" "$WORK/fakeproj"
printf 'x := 1\n' > "$P/good.ahk"
printf 'x := Abs(\n' > "$P/bad.ahk"                         # Missing ")"
for f in deep/nested/bad.ahk "sub dir/$NONASCII" UPPER.AHK my_test_parse_error.ahk \
         test_parse_error_demo.ahk test_crashlog_parse_demo.ahk deep/test_parse_error_2.ahk \
         notes.txt bad.ahk.bak; do
    cp "$P/bad.ahk" "$P/$f"
done
printf '#Include "%s"\n' 'does-not-exist.ahk' > "$P/badinclude.ahk"
cp "$P/bad.ahk" "$WORK/projx/bad.ahk"                       # sibling whose name extends proj
cp "$P/bad.ahk" "$WORK/outside/bad.ahk"
[[ -f $REPO/.mcp.json ]] && cp "$REPO/.mcp.json" "$WORK/noengine/.mcp.json"

to_win "$P"; P_WIN=$REPLY
to_mixed "$P"; P_MIX=$REPLY
if (( ON_WINDOWS )); then SEP='\'; else SEP=/; fi
# pn REL -> REPLY: $P/REL in the native form Claude Code sends (C:\... on Windows)
pn() { REPLY="$P_WIN$SEP${1//\//$SEP}"; }
pn bad.ahk; BAD_WIN=$REPLY

# "flag" engine: always reports a syntax error in the file it was given.
FLAG=$WORK/engines/flag/AutoHotkey64Console.exe
make_engine "$FLAG" 13 '@FILE@ (1) : ==> Missing ")"'$'\n''     Specifically: x := Abs('
to_win "$FLAG"; FLAG_WIN=$REPLY

# is_fork EXE: the hooks' engine test, copied from ahk-debug-context.sh (keep
# them in step). Status 0 when EXE may run as this fork's engine; else 1 with
# the reason in REPLY. A stock AutoHotkey can live anywhere, so a Windows exe
# (MZ header) qualifies only if it contains the UTF-16 text "CHECK PASS" that
# the fork's check verb prints, whatever its path; a "#!" wrapper is trusted
# unless it sits in a stock install folder. Nothing that fails it is run.
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
# Stock AutoHotkey install locations: machine-wide (Program Files\AutoHotkey\)
# and per-user (%LOCALAPPDATA%\Programs\AutoHotkey\). is_fork uses them only
# for "#!" wrappers; the fake stock installs below must sit in one.
is_stock_path() {
    to_mixed "$1"; local p=${REPLY,,}
    [[ $p == *"/program files"*"/autohotkey/"* || $p == *"/appdata/local/programs/autohotkey/"* ]]
}

# The real fork engine, chosen the way the hooks choose it.
ENGINE= ENGINE_WHY= ENGINE_VER= ENGINE_NOTE=
if [[ -n ${AHK_CUSTOM_EXE:-} ]]; then
    to_unix "$AHK_CUSTOM_EXE"; c=$REPLY
    if [[ ! -f $c ]]; then
        ENGINE_WHY="AHK_CUSTOM_EXE=$AHK_CUSTOM_EXE does not exist"
    elif is_fork "$c"; then
        ENGINE=$c
    else
        ENGINE_WHY="AHK_CUSTOM_EXE=$AHK_CUSTOM_EXE is not a fork engine ($REPLY); the hooks refuse it and this harness never runs it"
    fi
else
    for c in "$REPO/bin/AutoHotkey64Console.exe" "$REPO/bin/AutoHotkey64.exe"; do
        [[ -f $c ]] || continue
        if is_fork "$c"; then ENGINE=$c; break; fi
        ENGINE_NOTE+="${ENGINE_NOTE:+; }bin/${c##*/} is not a fork engine ($REPLY), so it is never run"
    done
    if [[ -z $ENGINE ]]; then
        ENGINE_WHY="${ENGINE_NOTE:-no bin/AutoHotkey64Console.exe or bin/AutoHotkey64.exe} (the engines in bin/ (bin/*.exe) are not in git; build one per BUILD.md, or set AHK_CUSTOM_EXE)"
        ENGINE_NOTE=
    fi
fi
if [[ -n $ENGINE ]] && (( ! ON_WINDOWS )); then
    ENGINE_WHY="the engine is a Windows program and this bash has no cygpath (use Git Bash)"; ENGINE=
fi
if [[ -n $ENGINE ]]; then
    ENGINE_VER=$("${RUNNER[@]}" "$ENGINE" --version 2>/dev/null); ENGINE_VER=${ENGINE_VER//$'\r'/}; ENGINE_VER=${ENGINE_VER%%$'\n'*}
fi
# The engine SessionStart reports for the real repository (AHK_CUSTOM_EXE
# unset), by the same rule; REPO_REJECTED lists bin/ exes that fail is_fork.
REPO_ENGINE= REPO_REJECTED=
for c in "$REPO/bin/AutoHotkey64Console.exe" "$REPO/bin/AutoHotkey64.exe"; do
    [[ -f $c ]] || continue
    if is_fork "$c"; then REPO_ENGINE=$c; break; fi
    REPO_REJECTED+="${REPO_REJECTED:+ }${c##*/}"
done

echo "${C_HEAD}Hook contract tests${C_OFF}"
echo "  bash $BASH_VERSION, $( (( ON_WINDOWS )) && echo 'Windows (cygpath present)' || echo 'POSIX (no cygpath)'), scratch $WORK"
if [[ -n $ENGINE ]]; then
    echo "  fork engine: $ENGINE (${ENGINE_VER:-version unknown})"
    [[ -z $ENGINE_NOTE ]] || echo "  ${C_SKIP}note: $ENGINE_NOTE${C_OFF}"
else
    echo "  ${C_SKIP}WARNING: no usable fork engine: $ENGINE_WHY${C_OFF}"
    echo "  ${C_SKIP}WARNING: the real-engine cases will be SKIPPED${C_OFF}"
fi

# =================================================================================
section "Registration and hook files"
# =================================================================================
SETTINGS=$REPO/.claude/settings.json
EXPECTED_REG=(
    $'PostToolUse\tEdit|Write|MultiEdit|mcp__ahk__AHK_File_Edit|mcp__ahk__AHK_File_Create\tahk-post-edit.sh'
    $'PostToolUse\tmcp__ahk__AHK_Debug_DBGp\tpost-capture-guidance.sh'
    $'PostToolUseFailure\tmcp__ahk__AHK_Debug_DBGp\tpost-capture-guidance.sh'
    $'PreToolUse\tmcp__ahk__AHK_Debug_DBGp\tcheck-ahk-connection.sh'
    $'SessionStart\t\tahk-debug-context.sh'
)
REGISTERED=()
t_begin "settings.json registers exactly the specified hooks"
if [[ ! -f $SETTINGS ]]; then
    bad "$SETTINGS is missing"
elif ! json_parse "$(<"$SETTINGS")"; then
    bad ".claude/settings.json is not valid JSON"
else
    cmd_re='^bash "\$CLAUDE_PROJECT_DIR/\.claude/hooks/([A-Za-z0-9._-]+\.sh)"$'
    path_re='^R\.hooks\.([A-Za-z]+)\[([0-9]+)\]\.hooks\[([0-9]+)\]\.command$'
    got=()
    for k in "${!JV[@]}"; do
        [[ $k =~ $path_re ]] || continue
        ev=${BASH_REMATCH[1]} gi=${BASH_REMATCH[2]} hi=${BASH_REMATCH[3]}
        [[ ${JV[R.hooks.$ev[$gi].hooks[$hi].type]:-} == command ]] || bad "$ev hook $gi/$hi is not type command"
        if [[ ${JV[$k]} =~ $cmd_re ]]; then
            got+=("$ev"$'\t'"${JV[R.hooks.$ev[$gi].matcher]:-}"$'\t'"${BASH_REMATCH[1]}")
            REGISTERED+=("${BASH_REMATCH[1]}")
        else
            bad "$ev command is not bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/<name>.sh\": ${JV[$k]}"
        fi
    done
    have=$(printf '%s\n' "${got[@]}" | LC_ALL=C sort)
    want=$(printf '%s\n' "${EXPECTED_REG[@]}" | LC_ALL=C sort)
    if [[ $have != "$want" ]]; then
        while IFS= read -r l; do [[ -n $l && $'\n'$have$'\n' != *$'\n'$l$'\n'* ]] && bad "missing registration: ${l//$'\t'/ | }"; done <<< "$want"
        while IFS= read -r l; do [[ -n $l && $'\n'$want$'\n' != *$'\n'$l$'\n'* ]] && bad "unexpected registration: ${l//$'\t'/ | }"; done <<< "$have"
    fi
fi
t_end

t_begin "every hook script is registered and every registered script exists"
for f in "$HOOKS_DIR"/*.sh; do
    b=${f##*/}
    [[ $b == test-hooks.sh ]] && continue
    [[ " ${REGISTERED[*]} " == *" $b "* ]] || bad "$b is in .claude/hooks but not registered (remove it or register it)"
done
for b in "${REGISTERED[@]}"; do
    [[ -f $HOOKS_DIR/$b ]] || bad "registered hook $b does not exist"
done
t_end

t_begin "hook scripts are LF-only ASCII"
for f in "$HOOKS_DIR"/*.sh; do
    LC_ALL=C grep -q $'\r' "$f" && bad "${f##*/} has CRLF line endings"
    n=$(LC_ALL=C tr -d '\t\n -~' < "$f" | wc -c)
    (( n == 0 )) || bad "${f##*/} has $((n)) non-ASCII bytes"
done
t_end

t_begin "hooks call no python, jq, WSL or cmd.exe"
for b in ahk-debug-context.sh ahk-post-edit.sh check-ahk-connection.sh post-capture-guidance.sh; do
    [[ -f $HOOKS_DIR/$b ]] || continue
    hit=$(grep -nvE '^[[:space:]]*#' "$HOOKS_DIR/$b" | grep -E '(^|[^A-Za-z0-9_])(python3?|jq|wsl|wslpath|cmd\.exe)([^A-Za-z0-9_]|$)|/mnt/' | head -n 1)
    [[ -z $hit ]] || bad "$b: $hit"
done
t_end

t_begin "settings.local.json does not register the hooks a second time"
if [[ -f $REPO/.claude/settings.local.json ]] && grep -q '\.claude/hooks/' "$REPO/.claude/settings.local.json"; then
    bad ".claude/settings.local.json also references .claude/hooks/ (keep them only in .claude/settings.json: Claude Code drops an exact duplicate, but a differently written copy runs twice)"
fi
t_end

t_begin "README.md documents every registered hook"
if [[ -f $HOOKS_DIR/README.md ]]; then
    for b in "${REGISTERED[@]}"; do grep -qF "$b" "$HOOKS_DIR/README.md" || bad "README.md does not mention $b"; done
else
    bad "README.md is missing"
fi
t_end

# =================================================================================
section "ahk-debug-context.sh (SessionStart)"
# =================================================================================
SS_REQUIRED=(mcp__ahk-mcp__check AHK_Debug_DBGp enable_toolset --diag=json //Debug 9001
             capture_error analyze_error apply_fix MsgBox InputBox "Script file not found"
             "#EnableEval" Print Inspect ProcessPipe TSParse _ScriptGetLines SyntaxError
             PowerShell "Git Bash")
SS_STALE=(AHK_Lint AHK_Diagnostics wslpath /mnt/ alpha.30 "suppress all dialogs" debug_run watch_add
          use_api ANTHROPIC_API_KEY autohotkey-debug tool_output)
ss_common() {
    want_rc 0; want_no_err; want_ascii; want_fast 3000
    count_lines "$OUT"; (( REPLY <= 50 )) || bad "stdout has $REPLY lines, want at most 50"
    want_has out "${SS_REQUIRED[@]}"
    want_lacks out "${SS_STALE[@]}"
}
ss_payload='{"session_id":"hooktest-0001","transcript_path":"C:\\Users\\tester\\.claude\\projects\\hooktest\\0001.jsonl","cwd":"'$J_CWD'","hook_event_name":"SessionStart","source":"startup"}'

to_win "$REPO"; H_PROJECT=$REPLY; H_CUSTOM=-
t_begin "this repository: exit 0, ASCII, < 3 s, current tool names, no stale tokens"
run ahk-debug-context.sh "$ss_payload"
ss_common
if [[ -n $REPO_ENGINE ]]; then          # passed is_fork, so it is safe to run
    want_has out "Engine (hooks and examples): ./bin/${REPO_ENGINE##*/}"
    v=$("${RUNNER[@]}" "$REPO_ENGINE" --version 2>/dev/null); v=${v//$'\r'/}; v=${v%%$'\n'*}
    [[ -z $v ]] || want_has out "$v"
else
    want_has out BUILD.md; want_hasi out "disabled" "not found"
fi
for b in $REPO_REJECTED; do want_has out "./bin/$b is not this fork's engine"; done
t_end

to_win "$WORK/noengine"; H_PROJECT=$REPLY
t_begin "no engine: says so, says the gate is disabled, points at BUILD.md"
run ahk-debug-context.sh "$ss_payload"
ss_common
want_has out BUILD.md; want_hasi out "not found" "disabled"
t_end

to_win "$REPO"; H_PROJECT=$REPLY; H_CUSTOM=$WORK/missing/AutoHotkey64Console.exe
t_begin "AHK_CUSTOM_EXE names a missing file: engine unavailable, gate disabled"
run ahk-debug-context.sh "$ss_payload"
ss_common
want_has out AHK_CUSTOM_EXE
want_hasi out "disabled"
t_end

make_engine "$WORK/fakeproj/bin/AutoHotkey64Console.exe" 0 ''
to_win "$WORK/fakeproj"; H_PROJECT=$REPLY; H_CUSTOM=-
t_begin "engine detected at run time: path and first --version line"
run ahk-debug-context.sh "$ss_payload"
ss_common
want_has out "./bin/AutoHotkey64Console.exe" "AutoHotkey v9.9.9-fake+Console"
t_end

# =================================================================================
section "ahk-post-edit.sh: payloads and paths (fake engine)"
# =================================================================================
# The flag engine reports an error for any file, so a case passes only if the
# hook really ran it (blocked) or really skipped it (silent, engine not run).
H_PROJECT=$P_WIN H_CUSTOM=$FLAG_WIN

gate_case() {    # gate_case LABEL PAYLOAD REL ENGINE_FILE_ARG
    t_begin "$1"
    calls_reset; run ahk-post-edit.sh "$2"
    want_blocked "$3"
    want_has err 'Missing ")"'
    want_called /flag/ "$4"
    t_end
}
skip_case() {    # skip_case LABEL PAYLOAD: silent, engine not run
    t_begin "$1"
    calls_reset; run ahk-post-edit.sh "$2"
    want_silent
    want_not_called
    t_end
}

if (( ON_WINDOWS )); then D_NATIVE='C:\ path (JSON-escaped backslashes)' D_MIXED='C:/ path'; else D_NATIVE='absolute path' D_MIXED='absolute path'; fi
edit_payload Edit "$BAD_WIN";                      gate_case "Edit, $D_NATIVE" "$REPLY" bad.ahk "$BAD_WIN"
edit_payload Write "$P_MIX/bad.ahk";               gate_case "Write, $D_MIXED" "$REPLY" bad.ahk "$BAD_WIN"
edit_payload MultiEdit "$BAD_WIN";                 gate_case "MultiEdit, file_path" "$REPLY" bad.ahk "$BAD_WIN"
edit_payload NotebookEdit "$BAD_WIN";              gate_case "NotebookEdit, notebook_path" "$REPLY" bad.ahk "$BAD_WIN"
edit_payload mcp__ahk__AHK_File_Edit "$BAD_WIN";   gate_case "AHK_File_Edit, filePath" "$REPLY" bad.ahk "$BAD_WIN"
edit_payload mcp__ahk__AHK_File_Create "$BAD_WIN"; gate_case "AHK_File_Create, filePath" "$REPLY" bad.ahk "$BAD_WIN"

text_blocks "**Edit Successful**"$'\n\n'"**File:** $BAD_WIN"$'\n'"**Operation:** Replaced 1 occurrence"$'\n'
envelope PostToolUse mcp__ahk__AHK_File_Edit '{"action":"replace","search":"x := 1","newContent":"x := Abs("}' "\"tool_response\":$REPLY"
gate_case "AHK_File_Edit without filePath: path from its result text" "$REPLY" bad.ahk "$BAD_WIN"

jesc "$BAD_WIN"
text_blocks "AutoHotkey file created successfully." "{"$'\n'"  \"filePath\": \"$REPLY\","$'\n'"  \"originalRequestPath\": \"bad.ahk\","$'\n'"  \"dryRun\": false"$'\n'"}"
envelope PostToolUse mcp__ahk__AHK_File_Create '{"filePath":"bad.ahk","content":"x := Abs(\n"}' "\"tool_response\":$REPLY"
gate_case "AHK_File_Create, relative filePath: absolute path from its result" "$REPLY" bad.ahk "$BAD_WIN"

pn UPPER.AHK; f=$REPLY;                 edit_payload Edit "$f"; gate_case "upper-case .AHK extension" "$REPLY" UPPER.AHK "$f"
pn deep/nested/bad.ahk; f=$REPLY;       edit_payload Edit "$f"; gate_case "nested file: report names the project-relative path" "$REPLY" deep/nested/bad.ahk "$f"
pn my_test_parse_error.ahk; f=$REPLY;   edit_payload Edit "$f"; gate_case "near-miss fixture name is still checked" "$REPLY" my_test_parse_error.ahk "$f"

t_begin "space and non-ASCII in the path: checked, report stays ASCII"
pn "sub dir/$NONASCII"; f=$REPLY
calls_reset; edit_payload Edit "$f"; run ahk-post-edit.sh "$REPLY"
want_rc 2; want_no_out; want_ascii
[[ ${ERR%%$'\n'*} == "AHK syntax check failed (exit 13) for sub dir/caf"*" bad.ahk:" ]] || bad "unexpected first stderr line"
want_called /flag/ "$f"
t_end

if (( ON_WINDOWS )); then
    lower=${BAD_WIN,,}
    edit_payload Edit "$lower";                    gate_case "path in a different letter case (Windows paths are case-insensitive)" "$REPLY" bad.ahk "$lower"
    to_unix "$P/bad.ahk"
    edit_payload Edit "$REPLY";                    gate_case "MSYS-style /... path" "$REPLY" bad.ahk "$BAD_WIN"
fi

big=$(head -c 300000 /dev/zero | tr '\0' a)
jesc "$BAD_WIN"
envelope PostToolUse Write "{\"file_path\":\"$REPLY\",\"content\":\"$big\"}" "\"tool_response\":{\"type\":\"update\",\"filePath\":\"$REPLY\",\"content\":\"$big\",\"structuredPatch\":[]}"
t_begin "600 KB Write payload: checked well inside the 30 s hook timeout"
calls_reset; run ahk-post-edit.sh "$REPLY"
want_blocked bad.ahk; want_called /flag/ "$BAD_WIN"; want_fast 10000
t_end
unset big

# CLAUDE_PROJECT_DIR in each form Claude Code or a user may give it.
edit_payload Edit "$BAD_WIN"; pl=$REPLY
for form in "$P_MIX" "$P_WIN$SEP" "$P"; do
    H_PROJECT=$form
    gate_case "CLAUDE_PROJECT_DIR=$form" "$pl" bad.ahk "$BAD_WIN"
done
if (( ON_WINDOWS )); then
    H_PROJECT=${P_WIN^^}
    gate_case "CLAUDE_PROJECT_DIR in upper case" "$pl" bad.ahk "$BAD_WIN"
fi
H_PROJECT=$P_WIN

# Skipped: nothing runs, nothing printed, exit 0.
skip_case "empty stdin" ""
skip_case "malformed payload: not JSON" "not json at all bad.ahk"
skip_case "malformed payload: lone brace" "{"
skip_case "malformed payload: cut off after tool_input" '{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":'
jesc "$BAD_WIN"
skip_case "malformed payload: cut off inside the path" "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${REPLY:0:${#REPLY}-3}"
skip_case "malformed payload: file_path is a number" '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":42,"content":"x.ahk"}}'
pn notes.txt;   edit_payload Edit "$REPLY";   skip_case "not .ahk: notes.txt" "$REPLY"
pn bad.ahk.bak; edit_payload Edit "$REPLY";   skip_case "not .ahk: bad.ahk.bak" "$REPLY"
to_win "$WORK/outside/bad.ahk"; edit_payload Edit "$REPLY"; skip_case "file outside the project" "$REPLY"
to_win "$WORK/projx/bad.ahk";   edit_payload Edit "$REPLY"; skip_case "sibling directory whose name starts with the project's" "$REPLY"
if (( ON_WINDOWS )); then
    edit_payload Edit "$P_WIN\\..\\outside\\bad.ahk"; skip_case "..\\ path that leaves the project" "$REPLY"
fi
pn missing.ahk;                  edit_payload Edit "$REPLY"; skip_case "file does not exist" "$REPLY"
pn test_parse_error_demo.ahk;    edit_payload Edit "$REPLY"; skip_case "fixture test_parse_error*.ahk" "$REPLY"
pn test_crashlog_parse_demo.ahk; edit_payload Edit "$REPLY"; skip_case "fixture test_crashlog_parse*.ahk" "$REPLY"
pn deep/test_parse_error_2.ahk;  edit_payload Edit "$REPLY"; skip_case "fixture in a subdirectory" "$REPLY"
jesc "$BAD_WIN"; p=$REPLY
envelope PreToolUse Edit "{\"file_path\":\"$p\",\"old_string\":\"a\",\"new_string\":\"b\"}"
skip_case "PreToolUse event (exit 2 there would block the edit)" "$REPLY"
envelope PostToolUse mcp__ahk__AHK_File_Edit "{\"action\":\"replace\",\"search\":\"a\",\"newContent\":\"b\",\"filePath\":\"$p\",\"dryRun\":true}" '"tool_response":[{"type":"text","text":"[DRY RUN] preview"}]'
skip_case "AHK_File_Edit dryRun (nothing written)" "$REPLY"
envelope PostToolUse mcp__ahk__AHK_File_Edit '{"action":"replace","search":"a","newContent":"b","filePath":"bad.ahk"}' '"tool_response":[{"type":"text","text":"done"}]'
skip_case "relative path with no absolute path in the result" "$REPLY"
jesc "{\"file_path\":\"$p\"}"; decoy=$REPLY
pn notes.txt; jesc "$REPLY"
envelope PostToolUse Write "{\"content\":\"$decoy\",\"file_path\":\"$REPLY\"}"
skip_case "a file_path key inside written content is not the path" "$REPLY"

# =================================================================================
section "ahk-post-edit.sh: engine choice and verdicts (fake engines)"
# =================================================================================
R=$WORK/resolve
mkdir -p "$R"; printf 'x := 1\n' > "$R/target.ahk"
make_engine "$R/bin/AutoHotkey64Console.exe" 13 '@FILE@ (1) : ==> console engine'
make_engine "$R/bin/AutoHotkey64.exe" 13 '@FILE@ (1) : ==> gui engine'
make_engine "$WORK/custom/AutoHotkey64Console.exe" 13 '@FILE@ (1) : ==> custom engine'
to_win "$R"; H_PROJECT=$REPLY
to_win "$R/target.ahk"; TARGET_WIN=$REPLY
edit_payload Edit "$TARGET_WIN"; pl=$REPLY

H_CUSTOM=-
t_begin "no AHK_CUSTOM_EXE: bin/AutoHotkey64Console.exe first"
calls_reset; run ahk-post-edit.sh "$pl"; want_blocked target.ahk; want_called /resolve/bin/AutoHotkey64Console.exe "$TARGET_WIN"
t_end
rm -f "$R/bin/AutoHotkey64Console.exe"
t_begin "no AHK_CUSTOM_EXE, no console build: bin/AutoHotkey64.exe"
calls_reset; run ahk-post-edit.sh "$pl"; want_blocked target.ahk; want_called /resolve/bin/AutoHotkey64.exe "$TARGET_WIN"
t_end
rm -f "$R/bin/AutoHotkey64.exe"
t_begin "no engine at all: gate off, silent"
calls_reset; run ahk-post-edit.sh "$pl"; want_silent; want_not_called
t_end
make_engine "$R/bin/AutoHotkey64Console.exe" 13 '@FILE@ (1) : ==> console engine'
H_CUSTOM=$WORK/missing/AutoHotkey64Console.exe
t_begin "AHK_CUSTOM_EXE missing: gate off even though bin/ has an engine"
calls_reset; run ahk-post-edit.sh "$pl"; want_silent; want_not_called
t_end
H_CUSTOM=$WORK/custom/AutoHotkey64Console.exe
t_begin "AHK_CUSTOM_EXE set: only that engine runs"
calls_reset; run ahk-post-edit.sh "$pl"; want_blocked target.ahk; want_called /custom/ "$TARGET_WIN"; want_has err "custom engine"
t_end
if (( ON_WINDOWS )); then
    to_win "$WORK/custom/AutoHotkey64Console.exe"; H_CUSTOM=$REPLY
    t_begin "AHK_CUSTOM_EXE as a C:\\ path"
    calls_reset; run ahk-post-edit.sh "$pl"; want_blocked target.ahk; want_called /custom/ "$TARGET_WIN"
    t_end
fi

V=$WORK/verdict/AutoHotkey64Console.exe
H_CUSTOM=$V
verdict() {    # verdict RC OUTPUT: point the verdict engine at RC/OUTPUT and run the gate
    make_engine "$V" "$1" "$2"
    calls_reset; run ahk-post-edit.sh "$pl"
}
t_begin "engine exit 0 with a warning: not blocking, silent"
verdict 0 '@FILE@ (3) : ==> Warning: This local variable appears to never be assigned a value.'
want_silent; want_called /verdict/ "$TARGET_WIN"
t_end
t_begin "engine exit 12 (parse/load error): blocked"
verdict 12 '@FILE@ (2) : ==> Unexpected "}"'
want_blocked target.ahk 12; want_has err 'Unexpected "}"'
t_end
t_begin "engine exit 13 \"Script file not found\": one-line note, exit 1, not blocked"
verdict 13 '@FILE@ (0) : ==> Script file not found.'
want_note
t_end
t_begin "engine exit 10 (no verdict): one-line note, exit 1"
verdict 10 'Error: something unexpected'
want_note
t_end
t_begin "engine exit 11 with no output: one-line note, exit 1"
verdict 11 ''
want_note
t_end
long=; for i in $(seq -w 1 100); do long+="engine line $i"$'\n'; done
t_begin "long engine output is capped near 40 lines"
verdict 13 "${long%$'\n'}"
want_blocked target.ahk
count_lines "$ERR"; (( REPLY <= 45 )) || bad "stderr has $REPLY lines, want at most 45"
want_has err "engine line 001"; want_lacks err "engine line 100"
t_end
t_begin "non-ASCII, CR and tab in engine output: stderr stays ASCII"
verdict 13 $'@FILE@ (1) : ==> caf\xc3\xa9 \xe2\x80\x9cquoted\xe2\x80\x9d\r\n\tSpecifically: x\r'
want_blocked target.ahk
t_end

# Project directory from BASH_SOURCE when CLAUDE_PROJECT_DIR is unset.
make_engine "$WORK/custom/AutoHotkey64Console.exe" 0 ''
H_PROJECT=- H_CUSTOM=$WORK/custom/AutoHotkey64Console.exe
to_win "$HOOKS_DIR/test-hooks-gui.ahk"; gui_win=$REPLY
edit_payload Edit "$gui_win"
t_begin "CLAUDE_PROJECT_DIR unset: project found from the hook's own path"
calls_reset; run ahk-post-edit.sh "$REPLY"; want_silent; want_called /custom/ "$gui_win"
t_end
edit_payload Edit "$BAD_WIN"
t_begin "CLAUDE_PROJECT_DIR unset: files outside this repository are skipped"
calls_reset; run ahk-post-edit.sh "$REPLY"; want_silent; want_not_called
t_end

# =================================================================================
section "Wrappers in stock install folders are never run (fake #! engines)"
# =================================================================================
# "#!" wrappers in stock install folders (machine-wide and per-user) that log
# every call to $CALLS and answer like a stock engine given an unknown script.
# This is is_fork's path rule for scripts it cannot inspect; real stock exes are
# refused by content (next section). Each hook must refuse one named by
# AHK_CUSTOM_EXE: never run it, never fall back to bin/ (the R project still
# has a bin/ fake that would log too), and never give it as a command.
# SessionStart says why; the gate is silent.
# want_no_command STREAM PATH: STREAM never offers PATH as a command (in / or
# \ form, any case, quoted or not, followed by check, /Debug or //Debug).
want_no_command() {
    local s p v
    _stream "$1"
    s=${S_TEXT,,}; s=${s//\"/}; s=${s//\'/}
    to_mixed "$2"; local pm=${REPLY,,}
    to_win "$2"; local pw=${REPLY,,}
    for p in "$pm" "$pw"; do
        for v in " check" " /debug" " //debug"; do
            [[ $s == *"$p$v"* ]] && bad "$S_NAME gives the stock engine as a command (...${p: -40}$v)"
        done
    done
    return 0
}
STOCKS=("Program Files"$'\t'"$WORK/stock/Program Files/AutoHotkey/v2/AutoHotkey64.exe"
        "AppData\\Local\\Programs"$'\t'"$WORK/stock/AppData/Local/Programs/AutoHotkey/v2/AutoHotkey64.exe")
to_win "$R"; H_PROJECT=$REPLY
to_win "$R/target.ahk"; edit_payload Edit "$REPLY"; pl=$REPLY
for s in "${STOCKS[@]}"; do
    where=${s%%$'\t'*} stock=${s#*$'\t'}
    make_engine "$stock" 2 '@FILE@ (0) : ==> Script file not found.'
    to_win "$stock"; H_CUSTOM=$REPLY

    t_begin "SessionStart, stock engine under $where: not run, says so, gate disabled"
    is_stock_path "$stock" || bad "harness: is_stock_path does not recognise $stock"
    calls_reset; run ahk-debug-context.sh "$ss_payload"
    ss_common
    want_not_called
    want_has out AHK_CUSTOM_EXE; want_hasi out stock disabled
    want_no_command out "$stock"
    t_end

    t_begin "post-edit gate, stock engine under $where: not run, no bin/ fallback, silent"
    calls_reset; run ahk-post-edit.sh "$pl"
    want_silent; want_not_called
    t_end

    if (( ON_WINDOWS )); then
        H_CUSTOM=${H_CUSTOM^^}
        t_begin "post-edit gate, stock engine under $where, upper-case path: not run, silent"
        calls_reset; run ahk-post-edit.sh "$pl"
        want_silent; want_not_called
        t_end
        to_win "$stock"; H_CUSTOM=$REPLY
    fi

    t_begin "PreToolUse run, stock engine under $where: launch commands do not name it"
    calls_reset; dbgp PreToolUse run; run check-ahk-connection.sh "$REPLY"
    want_rc 0; want_no_err; want_ascii; want_hso PreToolUse
    want_has ctx /Debug //Debug AutoHotkey64Console.exe "AHK_CUSTOM_EXE=" "is not this fork's engine" "fix or unset"
    want_lacks ctx BUILD.md
    want_no_command ctx "$stock"
    want_not_called
    t_end
done

# =================================================================================
section "Windows exes without the fork marker are never run (fake MZ files)"
# =================================================================================
# A real stock AutoHotkey is a Windows exe and can live anywhere (a portable
# copy, scoop, a bin/ copy under the fork's file name). is_fork accepts an MZ
# file only if it contains the fork's UTF-16 "CHECK PASS" text, whatever its
# path. These lookalikes have an MZ header and the ASCII (not UTF-16) text
# "CHECK PASS", and are not runnable: a hook that executed one would report
# "no check verdict" (gate) or an unknown --version (SessionStart). Nothing in
# this section may run a "#!" fake either ($CALLS stays empty) unless stated.
make_mz() {    # make_mz PATH: a non-executable stand-in for a stock AutoHotkey exe
    mkdir -p "${1%/*}"
    {
        printf 'MZ\x90\x00\x03\x00\x00\x00\x04\x00\x00\x00\xff\xff\x00\x00'
        printf '\xb8\x00\x00\x00\x00\x00\x00\x00\x40\x00\x00\x00\x00\x00\x00\x00'
        printf 'This program cannot be run in DOS mode. AutoHotkey v2.0.19 stock lookalike, CHECK PASS in ASCII only.\n'
    } > "$1"
}
want_mz_refused_ss() {    # SessionStart output for a refused MZ engine
    want_has out "is not this fork's engine (a Windows exe without the fork's check verb"
    want_lacks out "Engine (hooks and examples)"
    want_hasi out disabled
}
MZ_PORTABLE="$WORK/w/Portable AHK/AutoHotkey64.exe"
MZ_STOCK="$WORK/w/Program Files/AutoHotkey/v2/AutoHotkey64.exe"
make_mz "$MZ_PORTABLE"; make_mz "$MZ_STOCK"
for s in "portable path"$'\t'"$MZ_PORTABLE" "stock install path"$'\t'"$MZ_STOCK"; do
    where=${s%%$'\t'*} mz=${s#*$'\t'}
    to_win "$R"; H_PROJECT=$REPLY
    to_win "$mz"; H_CUSTOM=$REPLY

    t_begin "harness: is_fork refuses the MZ lookalike at a $where"
    is_fork "$mz" && bad "is_fork accepts $mz"
    t_end

    t_begin "SessionStart, MZ without the fork marker at a $where in AHK_CUSTOM_EXE: refused, gate disabled"
    calls_reset; run ahk-debug-context.sh "$ss_payload"
    ss_common; want_mz_refused_ss
    want_has out "AHK_CUSTOM_EXE=" "Point AHK_CUSTOM_EXE at a fork build or unset it"
    want_no_command out "$mz"; want_not_called
    t_end

    t_begin "post-edit gate, MZ without the fork marker at a $where in AHK_CUSTOM_EXE: silent, no bin/ fallback"
    calls_reset; run ahk-post-edit.sh "$pl"
    want_silent; want_not_called
    t_end

    t_begin "PreToolUse run, MZ without the fork marker at a $where: not named, AHK_CUSTOM_EXE blamed"
    calls_reset; dbgp PreToolUse run; run check-ahk-connection.sh "$REPLY"
    want_rc 0; want_no_err; want_ascii; want_hso PreToolUse
    want_has ctx "AHK_CUSTOM_EXE=" "is not this fork's engine" "fix or unset"
    want_lacks ctx BUILD.md
    want_no_command ctx "$mz"; want_not_called
    t_end
done

# A stock exe copied into bin/ under the console engine's name: skipped, so
# the hooks fall back to bin/AutoHotkey64.exe (a logging "#!" fake here).
M=$WORK/mzproj
mkdir -p "$M"; printf 'x := Abs(\n' > "$M/target.ahk"
printf '{"mcpServers":{"ahk-mcp":{"command":"./bin/AutoHotkey64Console.exe","args":["mcp"]}}}\n' > "$M/.mcp.json"
make_mz "$M/bin/AutoHotkey64Console.exe"
make_engine "$M/bin/AutoHotkey64.exe" 13 '@FILE@ (1) : ==> gui engine'
to_win "$M"; H_PROJECT=$REPLY H_CUSTOM=-
to_win "$M/target.ahk"; M_TARGET=$REPLY
edit_payload Edit "$M_TARGET"; mpl=$REPLY

t_begin "post-edit gate, non-fork bin/AutoHotkey64Console.exe: skipped, bin/AutoHotkey64.exe runs"
calls_reset; run ahk-post-edit.sh "$mpl"
want_blocked target.ahk; want_has err "gui engine"; want_called /mzproj/bin/AutoHotkey64.exe "$M_TARGET"
t_end

t_begin "SessionStart, non-fork bin/AutoHotkey64Console.exe: Skipped line, GUI fallback with piped PowerShell form"
calls_reset; run ahk-debug-context.sh "$ss_payload"
ss_common
want_has out "Skipped: ./bin/AutoHotkey64Console.exe is not this fork's engine" \
    "Engine (hooks and examples): ./bin/AutoHotkey64.exe" "This is the GUI build" \
    '& .\bin\AutoHotkey64.exe check /Diag=json file.ahk 2>&1 | Out-String' 'read $LASTEXITCODE'
want_lacks out "Out-Null" '$LASTEXITCODE is the exit code'
want_has out "./bin/AutoHotkey64Console.exe mcp): that is not this fork's engine"
# --version and --capabilities went to the "#!" GUI fake only
while IFS='|' read -r c0 c1 c2; do
    [[ $c0 == */mzproj/bin/AutoHotkey64.exe ]] || bad "ran $c0"
    [[ $c1 == --version || $c1 == --capabilities ]] || bad "ran the engine with $c1"
done < "$CALLS"
t_end

t_begin "PreToolUse run, non-fork bin/AutoHotkey64Console.exe: launch commands name bin/AutoHotkey64.exe"
calls_reset; dbgp PreToolUse run; run check-ahk-connection.sh "$REPLY"
want_rc 0; want_no_err; want_ascii; want_hso PreToolUse
want_has ctx './bin/AutoHotkey64.exe //Debug script.ahk' '& .\bin\AutoHotkey64.exe /Debug script.ahk'
want_lacks ctx "AutoHotkey64Console.exe //Debug" BUILD.md
want_not_called
t_end

rm -f "$M/bin/AutoHotkey64.exe"
t_begin "post-edit gate, only a non-fork bin/AutoHotkey64Console.exe: gate off, silent"
calls_reset; run ahk-post-edit.sh "$mpl"; want_silent; want_not_called
t_end
t_begin "SessionStart, only a non-fork bin/AutoHotkey64Console.exe: NOT FOUND, names it, gate disabled"
calls_reset; run ahk-debug-context.sh "$ss_payload"
ss_common; want_mz_refused_ss
want_has out "Engine: NOT FOUND. ./bin/AutoHotkey64Console.exe is not this fork's engine" BUILD.md
want_not_called
t_end
t_begin "PreToolUse run, only a non-fork bin/AutoHotkey64Console.exe: build per BUILD.md"
calls_reset; dbgp PreToolUse run; run check-ahk-connection.sh "$REPLY"
want_rc 0; want_no_err; want_ascii; want_hso PreToolUse
want_has ctx "build one per BUILD.md"; want_lacks ctx "AHK_CUSTOM_EXE"
t_end

to_win "$REPO"; H_PROJECT=$REPLY; H_CUSTOM=$WORK/missing/AutoHotkey64Console.exe
t_begin "PreToolUse run, AHK_CUSTOM_EXE missing: blames AHK_CUSTOM_EXE, not BUILD.md"
dbgp PreToolUse run; run check-ahk-connection.sh "$REPLY"
want_rc 0; want_no_err; want_ascii; want_hso PreToolUse
want_has ctx "AHK_CUSTOM_EXE=" "does not exist" "fix or unset" ./bin/AutoHotkey64Console.exe
want_lacks ctx BUILD.md
t_end

# Acceptance by content: a copy of the real fork engine under a stock-looking
# path (Program Files\AutoHotkey\v2\AutoHotkey64.exe) is a fork engine.
FORK_COPY="$WORK/w2/Program Files/AutoHotkey/v2/AutoHotkey64.exe"
fork_copy_cases=("fork engine copied under a Program Files\\AutoHotkey path: gate runs it"
                 "fork engine copied under a Program Files\\AutoHotkey path: SessionStart accepts it")
read -r -n 2 magic < "${ENGINE:-/dev/null}" 2>/dev/null
if [[ -z $ENGINE ]]; then
    for c in "${fork_copy_cases[@]}"; do skip "$c" "no fork engine: $ENGINE_WHY"; ENGINE_SKIPS=$((ENGINE_SKIPS + 1)); done
elif [[ $magic != MZ ]] || ! { mkdir -p "${FORK_COPY%/*}" && cp "$ENGINE" "$FORK_COPY"; }; then
    for c in "${fork_copy_cases[@]}"; do skip "$c" "the engine $ENGINE is not a Windows exe, or copying it failed"; ENGINE_SKIPS=$((ENGINE_SKIPS + 1)); done
else
    to_win "$FORK_COPY"; H_CUSTOM=$REPLY; H_PROJECT=$P_WIN
    to_mixed "$FORK_COPY"; copy_m=$REPLY
    t_begin "${fork_copy_cases[0]}"
    is_fork "$FORK_COPY" || bad "harness: is_fork refuses the copy ($REPLY)"
    edit_payload Write "$BAD_WIN"; run ahk-post-edit.sh "$REPLY"
    want_blocked bad.ahk; want_has err 'Missing ")"' "\"$copy_m\" check"
    t_end
    t_begin "${fork_copy_cases[1]}"
    run ahk-debug-context.sh "$ss_payload"
    ss_common
    want_has out "Engine (hooks and examples): $copy_m = ${ENGINE_VER:-}" "enabled (engine:"
    want_lacks out "is not this fork's engine"
    if [[ ${ENGINE##*/} == *Console* ]]; then    # GUI or console comes from the PE header, not the name
        want_lacks out "This is the GUI build" "2>&1 | Out-String"
    fi
    t_end
    rm -rf "$WORK/w2"
fi

# =================================================================================
section "ahk-post-edit.sh: real fork engine"
# =================================================================================
real_cases=("valid file: silent" "syntax error: blocked with the engine message"
            "warnings only: not blocking" "missing #Include: blocked"
            "space and non-ASCII path through the engine" "default engine checks test-hooks-gui.ahk")
if [[ -z $ENGINE ]]; then
    for c in "${real_cases[@]}"; do skip "$c" "no fork engine: $ENGINE_WHY"; ENGINE_SKIPS=$((ENGINE_SKIPS + 1)); done
else
    H_PROJECT=$P_WIN H_CUSTOM=$ENGINE
    if [[ ${ENGINE##*/} == *Console* ]]; then
        printf '#Warn\nf() {\n    return z\n}\n' > "$P/warn.ahk"
    else
        printf '#Warn All, StdOut\nf() {\n    return z\n}\n' > "$P/warn.ahk"    # never a dialog
    fi

    t_begin "${real_cases[0]}"
    pn good.ahk; edit_payload Edit "$REPLY"; run ahk-post-edit.sh "$REPLY"; want_silent
    t_end
    t_begin "${real_cases[1]}"
    edit_payload Write "$BAD_WIN"; run ahk-post-edit.sh "$REPLY"
    want_blocked bad.ahk; want_has err 'Missing ")"' "(1) : ==>"
    t_end
    t_begin "${real_cases[2]}"
    pn warn.ahk; edit_payload Edit "$REPLY"; run ahk-post-edit.sh "$REPLY"; want_silent
    t_end
    t_begin "${real_cases[3]}"
    pn badinclude.ahk; edit_payload Edit "$REPLY"; run ahk-post-edit.sh "$REPLY"
    want_blocked badinclude.ahk; want_has err does-not-exist.ahk
    t_end
    t_begin "${real_cases[4]}"
    pn "sub dir/$NONASCII"; edit_payload Edit "$REPLY"; run ahk-post-edit.sh "$REPLY"
    want_rc 2; want_no_out; want_ascii; want_has err 'Missing ")"'
    [[ ${ERR%%$'\n'*} == "AHK syntax check failed (exit 13) for sub dir/caf"*" bad.ahk:" ]] || bad "unexpected first stderr line"
    t_end
    if [[ -n $REPO_ENGINE ]]; then
        to_win "$REPO"; H_PROJECT=$REPLY; H_CUSTOM=-
        t_begin "${real_cases[5]}"
        edit_payload Edit "$gui_win"; run ahk-post-edit.sh "$REPLY"; want_silent
        t_end
    else
        skip "${real_cases[5]}" "no engine in bin/ (AHK_CUSTOM_EXE supplied the one above)"; ENGINE_SKIPS=$((ENGINE_SKIPS + 1))
    fi
fi

# =================================================================================
section "check-ahk-connection.sh (PreToolUse)"
# =================================================================================
to_win "$REPO"; H_PROJECT=$REPLY; H_CUSTOM=-
for a in capture_error run step_into step_over step_out variables_get evaluate stack_trace \
         breakpoint_set breakpoint_remove breakpoint_list; do
    t_begin "action $a: launch and port reminder"
    dbgp PreToolUse "$a"; run check-ahk-connection.sh "$REPLY"
    want_rc 0; want_no_err; want_ascii; want_hso PreToolUse
    want_has ctx start /Debug
    if [[ $a == run || $a == capture_error ]]; then
        want_has ctx "//Debug" "AutoHotkey64Console.exe" 9000 9001 status PowerShell "Git Bash" "VS Code"
    fi
    t_end
done
for a in start stop status analyze_error apply_fix get_source list_errors clear_errors no_such_action; do
    t_begin "action $a: no output"
    dbgp PreToolUse "$a"; run check-ahk-connection.sh "$REPLY"; want_silent
    t_end
done
t_begin "other tools are ignored even with an action field"
for tool in Bash mcp__ahk__AHK_Run mcp__ahk__AHK_Debug_DBGpX; do
    envelope PreToolUse "$tool" '{"action":"run","command":"ls"}'; run check-ahk-connection.sh "$REPLY"
    [[ $RC == 0 && -z $OUT && -z $ERR ]] || bad "$tool: exit $RC, output not empty"
done
t_end
t_begin "PostToolUse event: no output"
dbgp PostToolUse run '"tool_response":[{"type":"text","text":"Running"}]'; run check-ahk-connection.sh "$REPLY"; want_silent
t_end
t_begin "an \"action\" key inside a string value is not the action"
envelope PreToolUse mcp__ahk__AHK_Debug_DBGp '{"expression":"{\"action\":\"run\"}","action":"status"}'
run check-ahk-connection.sh "$REPLY"; want_silent
t_end
t_begin "the real action after a decoy string still counts"
envelope PreToolUse mcp__ahk__AHK_Debug_DBGp '{"expression":"{\"action\":\"start\"}","action":"evaluate"}'
run check-ahk-connection.sh "$REPLY"; want_rc 0; want_hso PreToolUse
t_end
for pl in "" "not json" "{" '{"hook_event_name":"PreToolUse","tool_name":"mcp__ahk__AHK_Debug_DBGp"}'; do
    t_begin "malformed or partial payload: ${pl:-<empty>}"
    run check-ahk-connection.sh "$pl"; want_silent
    t_end
done

# =================================================================================
section "post-capture-guidance.sh (PostToolUse, PostToolUseFailure)"
# =================================================================================
# tool_response in each shape an MCP result can take.
shapes() {    # shapes TEXT -> SHAPES (array of "name<TAB>field")
    local t; jesc "$1"; t=$REPLY
    SHAPES=("content array"$'\t'"\"tool_response\":[{\"type\":\"text\",\"text\":\"$t\"}]"
            "plain string"$'\t'"\"tool_response\":\"$t\""
            "content object"$'\t'"\"tool_response\":{\"content\":[{\"type\":\"text\",\"text\":\"$t\"}],\"isError\":false}")
}
guidance() {    # guidance LABEL EVENT ACTION FIELD
    t_begin "$1"
    dbgp "$2" "$3" "$4"; run post-capture-guidance.sh "$REPLY"
    want_rc 0; want_no_err; want_ascii; want_hso "$2"
}
quiet() {       # quiet LABEL PAYLOAD
    t_begin "$1"
    run post-capture-guidance.sh "$2"; want_silent
    t_end
}

shapes '{"captured":false,"reason":"timeout"}'
for s in "${SHAPES[@]}"; do
    guidance "capture_error captured:false (${s%%$'\t'*}): timeout guidance" PostToolUse capture_error "${s#*$'\t'}"
    want_hasi ctx "timed out"; want_has ctx /Debug status port
    t_end
done
captured=$'{\n  "captured": true,\n  "error": {\n    "error_type": "Error",\n    "message": "Call to nonexistent function.",\n    "file": "C:\\\\Scripts\\\\demo.ahk",\n    "line": 3\n  }\n}'
shapes "$captured"
for s in "${SHAPES[@]}"; do
    guidance "capture_error captured:true (${s%%$'\t'*}): analyze, diagnose, apply_fix" PostToolUse capture_error "${s#*$'\t'}"
    want_has ctx analyze_error Markdown apply_fix original; want_hasi ctx diagnosis
    want_lacksi ctx "timed out"
    t_end
done
shapes $'{\n  "captured": true,\n  "error": {\n    "message": "saw {\\"captured\\":false} in a variable"\n  }\n}'
guidance "captured:true whose error text mentions captured:false" PostToolUse capture_error "${SHAPES[0]#*$'\t'}"
want_has ctx analyze_error; want_lacksi ctx "timed out"
t_end
shapes $'Fix applied at C:\\Scripts\\demo.ahk:3\n- Old: x := Abs(\n+ New: x := Abs(1)'
for s in "${SHAPES[@]}"; do
    guidance "apply_fix \"Fix applied\" (${s%%$'\t'*}): ask for a /Debug re-run" PostToolUse apply_fix "${s#*$'\t'}"
    want_hasi ctx "re-run"; want_has ctx /Debug CRLF LF
    t_end
done
shapes $'Error: Line mismatch at 3.\nExpected: "x := Abs("\nFound: "y := 2"'
guidance "apply_fix \"Error: Line mismatch\" as PostToolUse: re-read and retry" PostToolUse apply_fix "${SHAPES[0]#*$'\t'}"
want_has ctx get_source Read; want_hasi ctx exact retry
t_end
jesc $'Error: Line mismatch at 3.\nExpected: "x := Abs("\nFound: "y := 2"'
guidance "PostToolUseFailure apply_fix (Line mismatch): re-read and retry" PostToolUseFailure apply_fix "\"error\":\"$REPLY\",\"is_interrupt\":false"
want_has ctx get_source Read; want_hasi ctx exact retry
t_end
guidance "PostToolUseFailure apply_fix (other failure): re-read and retry" PostToolUseFailure apply_fix '"error":"Error: Failed to apply fix: Error: EBUSY","is_interrupt":false'
want_has ctx get_source Read
t_end
jesc $'Fix applied at C:\\Scripts\\caf\xc3\xa9.ahk:3'
guidance "non-ASCII in the result: output stays ASCII" PostToolUse apply_fix "\"tool_response\":[{\"type\":\"text\",\"text\":\"$REPLY\"}]"
t_end

text_blocks $'## AutoHotkey Error Analysis\n\nAnalyze this error.'
dbgp PostToolUse analyze_error "\"tool_response\":$REPLY"; quiet "analyze_error result: no output" "$REPLY"
text_blocks $'{\n  "connected": false,\n  "port": 9001,\n  "errors_queued": 0\n}'
dbgp PostToolUse status "\"tool_response\":$REPLY"; quiet "status result: no output" "$REPLY"
text_blocks $'DBGp listener started on port 9000.'
dbgp PostToolUse start "\"tool_response\":$REPLY"; quiet "start result: no output" "$REPLY"
text_blocks 'Breakpoint set'
dbgp PostToolUse capture_error "\"tool_response\":$REPLY"; quiet "capture_error without a captured field: no output" "$REPLY"
dbgp PostToolUseFailure capture_error '"error":"Error: Not connected to AutoHotkey debugger","is_interrupt":false'
quiet "PostToolUseFailure capture_error: no output" "$REPLY"
dbgp PostToolUseFailure analyze_error '"error":"Error: No error provided for analysis","is_interrupt":false'
quiet "PostToolUseFailure analyze_error: no output" "$REPLY"
dbgp PreToolUse capture_error; quiet "PreToolUse event: no output" "$REPLY"
envelope PostToolUse mcp__ahk__AHK_Run '{"action":"capture_error"}' '"tool_response":[{"type":"text","text":"{\"captured\":false}"}]'
quiet "another tool: no output" "$REPLY"
for pl in "" "not json" "{"; do quiet "malformed payload: ${pl:-<empty>}" "$pl"; done

# =================================================================================
section "Summary"
# =================================================================================
printf 'RESULT: %d passed, %d failed, %d skipped\n' "$PASSED" "$FAILED" "$SKIPPED"
if (( ENGINE_SKIPS > 0 )); then
    printf '%sWARNING: %d real-engine case(s) were SKIPPED; see the SKIP lines above.%s\n' "$C_SKIP" "$ENGINE_SKIPS" "$C_OFF"
    [[ -z $ENGINE ]] && printf '%sWARNING: the syntax gate was not run against a real engine: %s%s\n' "$C_SKIP" "$ENGINE_WHY" "$C_OFF"
fi
if (( FAILED > 0 )); then
    printf '%sFAILED%s\n' "$C_FAIL" "$C_OFF"
else
    printf '%sOK%s\n' "$C_PASS" "$C_OFF"
fi
exit $(( FAILED > 254 ? 254 : FAILED ))
