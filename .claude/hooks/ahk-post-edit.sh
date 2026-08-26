#!/bin/bash
# Post-edit hook for AutoHotkey v2 scripts
# Validates syntax after edits using the custom engine's check command
# with structured JSON diagnostics. Blocks on syntax errors.
# JSON parsing uses python3 — jq is NOT installed in this WSL.

# Custom engine with check/diag support; fall back to stock
CUSTOM_AHK="/mnt/c/Users/uphol/Documents/Design/Coding/AutoHotkey/bin/AutoHotkey64.exe"
STOCK_AHK="/mnt/c/Program Files/AutoHotkey/v2/AutoHotkey64.exe"

if [[ -f "$CUSTOM_AHK" ]]; then
    AHK_EXE="$CUSTOM_AHK"
    HAS_CHECK=true
else
    AHK_EXE="$STOCK_AHK"
    HAS_CHECK=false
fi

PROJECT_DIR="/mnt/c/Users/uphol/Documents/AHK"
MAIN_SCRIPT="_.ahk"

# Parse JSON from stdin to get the edited file path
input=$(cat)
file_path=$(printf '%s' "$input" | python3 -c "
import json,sys
try: print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))
except Exception: pass
" 2>/dev/null)

# Only process .ahk files
if [[ ! "$file_path" == *.ahk ]]; then
    exit 0
fi

filename=$(basename "$file_path")

# Skip validation for intentional parse-error test fixtures
if [[ "$filename" == test_crashlog_parse*.ahk || "$filename" == test_parse_error*.ahk ]]; then
    exit 0
fi

# Convert WSL path to Windows path for the AHK engine
if [[ "$file_path" == /mnt/* ]]; then
    win_path=$(wslpath -w "$file_path" 2>/dev/null)
else
    win_path="$file_path"
fi

# Helper: build a safe JSON block response
block_response() {
    python3 -c "
import json,sys
print(json.dumps({'decision':'block','reason':sys.argv[1],'additionalContext':sys.argv[2]}))
" "$1" "$2"
}

# Helper: pull one key out of a (possibly non-JSON) diagnostics blob
diag_field() {
    printf '%s' "$1" | python3 -c "
import json,sys
try: print(json.load(sys.stdin).get(sys.argv[1],''))
except Exception: pass
" "$2" 2>/dev/null
}

# --- Step 1: Validate the edited file ---

if [[ "$HAS_CHECK" == true ]]; then
    # Use custom engine: check command + JSON diagnostics
    validation_output=$("$AHK_EXE" check /Diag=json /ErrorStdOut "$win_path" 2>&1)
    validation_exit=$?

    if [[ $validation_exit -eq 13 || $validation_exit -eq 12 ]]; then
        diag_msg=$(diag_field "$validation_output" message)
        diag_line=$(diag_field "$validation_output" line)

        if [[ -n "$diag_msg" ]]; then
            error_detail="Line $diag_line: $diag_msg"
        else
            error_detail="$validation_output"
        fi

        block_response \
            "AHK v2 syntax error in $filename: $error_detail" \
            "Fix the syntax error and retry. The check command (exit $validation_exit) found an error at line $diag_line. Use get_source_context to see surrounding code if needed."
        exit 1
    elif [[ $validation_exit -ne 0 ]]; then
        block_response \
            "AHK validation returned exit code $validation_exit for $filename: $validation_output" \
            "Exit codes: 0=ok, 10=runtime, 11=internal, 12=parse/load, 13=check fail, 14=test fail, 64=CLI error."
        exit 1
    fi
else
    # Stock engine: /ErrorStdOut /validate
    validation_output=$("$AHK_EXE" /ErrorStdOut /validate "$win_path" 2>&1)
    validation_exit=$?

    if [[ $validation_exit -ne 0 ]]; then
        block_response \
            "AHK v2 Syntax Error in $filename: $validation_output" \
            "Fix the syntax error and retry."
        exit 1
    fi
fi

# --- Step 2: If main script dependency was edited, validate main script too ---

is_dependency=false

case "$filename" in
    "_.ahk"|"__Menu.ahk"|"_UHQ_Snipping.ahk"|"_UHQ_Bambu.ahk")
        is_dependency=true
        ;;
esac

if [[ "$file_path" == *"/Lib/"* ]]; then
    is_dependency=true
fi

if [[ "$is_dependency" == true ]]; then
    main_win_path=$(wslpath -w "$PROJECT_DIR/$MAIN_SCRIPT" 2>/dev/null)

    if [[ "$HAS_CHECK" == true ]]; then
        main_output=$("$AHK_EXE" check /Diag=json /ErrorStdOut "$main_win_path" 2>&1)
        main_exit=$?
    else
        main_output=$("$AHK_EXE" /ErrorStdOut /validate "$main_win_path" 2>&1)
        main_exit=$?
    fi

    if [[ $main_exit -ne 0 ]]; then
        diag_msg=$(diag_field "$main_output" message)
        diag_line=$(diag_field "$main_output" line)

        if [[ -n "$diag_msg" ]]; then
            error_detail="Line $diag_line: $diag_msg"
        else
            error_detail="$main_output"
        fi

        block_response \
            "Main script ($MAIN_SCRIPT) validation failed after editing $filename: $error_detail" \
            "The edit to $filename broke the main script. Check #Include directives and shared dependencies."
        exit 1
    fi
fi

# Success — no output needed, hook passes silently
exit 0
