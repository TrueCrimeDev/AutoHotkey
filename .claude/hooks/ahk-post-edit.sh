#!/usr/bin/env bash
# PostToolUse syntax gate for AutoHotkey v2 files.
#
# Registered in .claude/settings.json for
#   Edit|Write|MultiEdit|mcp__ahk__AHK_File_Edit|mcp__ahk__AHK_File_Create
# After such a tool writes a *.ahk file inside this project, run the fork
# engine's load-only `check` verb on it:
#   exit 0  check passed (warnings never block), or the file was skipped
#   exit 2  check failed (engine exit 12/13): stderr is shown to Claude
#   exit 1  the engine gave no verdict (non-blocking notice to the user)
#
# Runs under Git Bash on Windows (Claude Code's hook shell) or any bash 4+.
# No python/jq: fields are read from the raw stdin JSON with bash regexes.
# Every byte printed is ASCII. `check` performs #DllLoad, so only files
# under the project directory are checked.
#
# Engine: $AHK_CUSTOM_EXE when set (if that file is missing or not this
# fork's engine, the gate is off), else bin/AutoHotkey64Console.exe, else
# bin/AutoHotkey64.exe, skipping one that is not a fork engine. Never a stock
# AutoHotkey, wherever it is installed: it would take "check" as a script name
# and show a modal "Script file not found" dialog (see is_fork).

payload=$(cat 2>/dev/null)
[[ -n $payload ]] || exit 0
shopt -s nocasematch
[[ $payload == *.ahk* ]] || exit 0         # cheap pre-filter

# Only [[ =~ ]] is used on the payload: pattern-removal expansions such as
# ${x#*pat} are quadratic in bash and take seconds on a large Write payload.
# A key that sits inside a JSON string value is always escaped (\"key\"), so
# the first unescaped "key": match is a real key; tool_input precedes
# tool_response in Claude Code's payload.
#
# JSON string value of key $1 in text $2 -> REPLY (still JSON-escaped).
json_raw() {
    local re='"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
    REPLY=
    [[ $2 =~ $re ]] || return 1
    REPLY=${BASH_REMATCH[1]}
}
# Code point $1 -> REPLY: its UTF-8 bytes, built with printf \x escapes so the
# result does not depend on the locale. A backslash becomes the \001
# placeholder json_unescape restores last (so it is never decoded twice);
# control characters and lone surrogates, never valid in a path, become '?'.
utf8() {
    local c=$1 f
    if (( c == 0x5C )); then REPLY=$'\001'; return; fi
    if (( c < 0x20 || (c >= 0xD800 && c <= 0xDFFF) )); then REPLY='?'; return; fi
    if (( c < 0x80 )); then
        printf -v f '\\x%02x' "$c"
    elif (( c < 0x800 )); then
        printf -v f '\\x%02x\\x%02x' $((0xC0 | c >> 6)) $((0x80 | (c & 0x3F)))
    elif (( c < 0x10000 )); then
        printf -v f '\\x%02x\\x%02x\\x%02x' $((0xE0 | c >> 12)) $((0x80 | (c >> 6 & 0x3F))) $((0x80 | (c & 0x3F)))
    else
        printf -v f '\\x%02x\\x%02x\\x%02x\\x%02x' $((0xF0 | c >> 18)) $((0x80 | (c >> 12 & 0x3F))) \
            $((0x80 | (c >> 6 & 0x3F))) $((0x80 | (c & 0x3F)))
    fi
    printf -v REPLY "$f"
}
# Undo one level of JSON string escaping in $1 -> REPLY: \\ \" \/ and \uXXXX
# (surrogate pairs included). \n \t \b \f \r cannot occur in a path.
json_unescape() {
    local s=$1 hi lo
    local pair_re='\\u([dD][89aAbB][0-9A-Fa-f]{2})\\u([dD][c-fC-F][0-9A-Fa-f]{2})'
    local u_re='\\u([0-9A-Fa-f]{4})'
    s=${s//\\\\/$'\001'}
    s=${s//\\\"/\"}
    s=${s//\\\//\/}
    while [[ $s =~ $pair_re ]]; do
        hi=$((16#${BASH_REMATCH[1]})); lo=$((16#${BASH_REMATCH[2]}))
        utf8 $(( 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00) ))
        s=${s/"${BASH_REMATCH[0]}"/"$REPLY"}
    done
    while [[ $s =~ $u_re ]]; do
        utf8 $((16#${BASH_REMATCH[1]}))
        s=${s/"${BASH_REMATCH[0]}"/"$REPLY"}
    done
    REPLY=${s//$'\001'/\\}
}
abs_re='^([A-Za-z]:[\\/]|/|\\\\)'

# Exit 2 from a PreToolUse hook would block the edit; act only after it ran.
if json_raw hook_event_name "$payload" && [[ $REPLY != PostToolUse ]]; then
    exit 0
fi

# --- path from tool_input ---------------------------------------------------
ti_re='"tool_input"[[:space:]]*:'
[[ $payload =~ $ti_re ]] || exit 0

dryrun_re='"dryRun"[[:space:]]*:[[:space:]]*true'
[[ $payload =~ $dryrun_re ]] && exit 0     # AHK_File_Edit/Create preview

file=
for key in file_path filePath notebook_path; do
    if json_raw "$key" "$payload" && [[ -n $REPLY ]]; then
        json_unescape "$REPLY"; file=$REPLY
        break
    fi
done

# AHK_File_Edit may omit filePath (it edits the ahk server's active file) and
# AHK_File_Create resolves a relative filePath against the server's own cwd.
# Both report the absolute path they wrote in their tool_response text, which
# arrives JSON-escaped once (Edit's "**File:** <path>") or twice (Create's
# JSON result block).
if [[ -z $file || ! $file =~ $abs_re ]]; then
    file=
    edit_re='\*\*File:\*\* (([^"\\]|\\\\)+)'
    create_re='\\"filePath\\"[[:space:]]*:[[:space:]]*\\"(([^"\\]|\\\\\\\\)+)\\"'
    if [[ $payload =~ $edit_re ]]; then
        json_unescape "${BASH_REMATCH[1]}"; file=$REPLY
    elif [[ $payload =~ $create_re ]]; then
        json_unescape "${BASH_REMATCH[1]}"; json_unescape "$REPLY"; file=$REPLY
    fi
fi
[[ -n $file && $file =~ $abs_re ]] || exit 0

# --- filters ----------------------------------------------------------------
[[ $file == *.ahk ]] || exit 0
case ${file##*[\\/]} in
    test_crashlog_parse*.ahk|test_parse_error*.ahk) exit 0 ;;  # intentional parse-error fixtures
esac

project=${CLAUDE_PROJECT_DIR:-}
if [[ -z $project ]]; then
    project=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd) || exit 0
fi
custom=${AHK_CUSTOM_EXE:-}

if command -v cygpath >/dev/null 2>&1; then
    # One call: project, file and (optionally) the custom engine -> C:/... form.
    mixed=$(cygpath -m "$project" "$file" ${custom:+"$custom"} 2>/dev/null) || exit 0
    project=${mixed%%$'\n'*}; mixed=${mixed#*$'\n'}
    file=${mixed%%$'\n'*};    mixed=${mixed#*$'\n'}
    [[ -n $custom ]] && custom=$mixed
    win_file=${file//\//\\}
else
    project=${project//\\//}
    file=${file//\\//}
    custom=${custom//\\//}
    win_file=$file
fi
project=${project%/}
[[ -n $project && -n $file ]] || exit 0
[[ $file == */../* ]] && exit 0             # unnormalized (only possible without cygpath)
[[ $file == "$project"/* ]] || exit 0       # inside the project (case-insensitive)
rel=${file:${#project}+1}
[[ -f $file ]] || exit 0

# --- engine -----------------------------------------------------------------
# is_fork EXE: status 0 when EXE may run as this fork's engine. A stock
# AutoHotkey can live anywhere (Program Files, the per-user
# %LOCALAPPDATA%\Programs\AutoHotkey, a portable copy), so a Windows exe (MZ
# header) qualifies only if it contains the UTF-16 text "CHECK PASS" that the
# fork's check verb prints; stock builds have no check verb (about 20 ms, path
# ignored). A "#!" wrapper script cannot be inspected: it is trusted unless it
# sits in a stock install folder. Anything else is refused.
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
if [[ -n ${AHK_CUSTOM_EXE:-} ]]; then
    is_fork "$custom" && engine=$custom
else
    for cand in "$project/bin/AutoHotkey64Console.exe" "$project/bin/AutoHotkey64.exe"; do
        if is_fork "$cand"; then engine=$cand; break; fi
    done
fi
[[ -n $engine ]] || exit 0                  # no usable fork engine: gate disabled

engine_shown=$engine
[[ $engine == "$project"/* ]] && engine_shown=./${engine:${#project}+1}
[[ $engine_shown == *" "* ]] && engine_shown="\"$engine_shown\""

# --- check ------------------------------------------------------------------
runner=()
tpath=$(command -v timeout 2>/dev/null)
[[ $tpath == /usr/bin/* || $tpath == /bin/* ]] && runner=(timeout 25)
output=$("${runner[@]}" "$engine" check "$win_file" 2>&1)
rc=$?
[[ $rc -eq 0 ]] && exit 0                   # pass; warnings do not block

output=${output//$'\r'/}
ascii() { LC_ALL=C tr -c '\n -~' '?'; }

if [[ ($rc -eq 12 || $rc -eq 13) && $output != *"Script file not found"* ]]; then
    mapfile -t lines <<< "$output"
    max=40
    {
        printf 'AHK syntax check failed (exit %s) for %s:\n' "$rc" "$rel"
        printf '%s\n' "${lines[@]:0:max}"
        (( ${#lines[@]} > max )) && printf '... (%d more lines)\n' $(( ${#lines[@]} - max ))
        printf 'Fix the reported problem, then re-check from the project root: %s check "%s" (or mcp__ahk-mcp__check).\n' \
            "$engine_shown" "$rel"
    } | ascii >&2
    exit 2
fi

first=${output%%$'\n'*}
printf 'ahk-post-edit: no check verdict for %s (%s exit %s): %s\n' \
    "$rel" "$engine_shown" "$rc" "${first:-no output}" | ascii >&2
exit 1
