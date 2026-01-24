; AHK Error-to-StdErr Handler
; Captures runtime errors and outputs to stderr for CLI/shell capture
;
; Usage:
;   AutoHotkey.exe /ErrorStdOut /include error-to-stderr.ahk your_script.ahk 2>&1
;
; Or capture separately:
;   AutoHotkey.exe /ErrorStdOut /include error-to-stderr.ahk your_script.ahk 2>errors.txt

#Requires AutoHotkey v2.0

; Send warnings to stderr instead of dialog
#Warn All, StdOut

; Register error handler (runs last, after any user handlers)
OnError(_ErrorToStdErr, -1)

_ErrorToStdErr(err, mode) {
    ; Format error for stderr (similar to /ErrorStdOut format for load-time errors)
    output := Format("{1} ({2}) : ==> {3}: {4}`n",
        err.File,
        err.Line,
        Type(err),
        err.Message
    )

    ; Add extra info if available
    if err.Extra != ""
        output .= Format("     Specifically: {1}`n", err.Extra)

    ; Add stack trace
    if err.Stack != ""
        output .= Format("     Stack:`n{1}`n", _IndentStack(err.Stack))

    ; Add thread status
    output .= Format("     {1}`n",
        (mode == "ExitApp" ? "Script will exit." :
         mode == "Exit" ? "Thread will exit." :
         "Thread will continue.")
    )

    ; Write to stderr
    FileAppend(output, "**")

    ; Return -1 to suppress error dialog and continue if possible
    return -1
}

_IndentStack(stack) {
    result := ""
    for line in StrSplit(stack, "`n")
        if line != ""
            result .= "       " line "`n"
    return RTrim(result, "`n")
}

; Override MsgBox to output to stdout (for headless execution)
MsgBox(Text?, Title?, Options?) {
    out := IsSet(Text) ? Text : ""
    FileAppend(out "`n", "*")
    return "OK"
}
