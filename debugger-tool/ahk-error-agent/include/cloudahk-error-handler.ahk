; CloudAHK-style Error Handler for AHK v2
; Uses OnError to capture runtime errors and format them for AI/API consumption
; Works with standard AHK v2 - no special build required
;
; For use with _ScriptGetLines (if available), see the alternate version below

#Requires AutoHotkey v2.0

; Register error handler at lowest priority (runs last)
OnError(CloudAHK_ErrorHandler, -1)

; Suppress warning dialogs - output to stderr instead
#Warn All, StdOut

; ============================================================================
; Error Handler - Standard Version (no _ScriptGetLines)
; ============================================================================

CloudAHK_ErrorHandler(err, mode) {
    ; Build error output
    output := Format("
    (LTrim
    {1}: {2}

    File: {3}
    Line: {4}
    What: {5}

    Stack:
    {6}

    {7}
    )",
        Type(err),
        err.Message,
        err.File,
        err.Line,
        err.What,
        err.Stack,
        (mode == "ExitApp" ? "Script" : "Thread") " will " (mode == "Return" ? "continue" : "exit")
    )

    ; Output to stderr
    FileAppend(output "`n", "**")

    ; Return -1 to continue thread execution (if possible)
    return -1
}

; ============================================================================
; MsgBox Override - Redirect to stdout for headless execution
; ============================================================================

MsgBox(Text?, Title?, Options?) {
    ; Format output
    out := ""
    if IsSet(Title) && Title != ""
        out .= "[" Title "] "
    if IsSet(Text)
        out .= Text

    ; Write to stdout
    FileAppend(out "`n", "*")

    ; Return "OK" as if user clicked OK
    return "OK"
}

; ============================================================================
; InputBox Override - Return empty for headless execution
; ============================================================================

InputBox(Prompt?, Title?, Options?, Default?) {
    return {Value: IsSet(Default) ? Default : "", Result: "Cancel"}
}
