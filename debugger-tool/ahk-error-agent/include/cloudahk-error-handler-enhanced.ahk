; CloudAHK Enhanced Error Handler for AHK v2
; Works with _ScriptGetLines (requires linecontext branch build)
;
; To build AHK with _ScriptGetLines:
;   git clone https://github.com/AutoHotkey/AutoHotkey.git
;   cd AutoHotkey
;   git checkout linecontext
;   # Build with Visual Studio
;
; Usage:
;   AutoHotkey.exe /include cloudahk-error-handler-enhanced.ahk script.ahk

#Requires AutoHotkey v2.0

; Register error handler at lowest priority
OnError(CloudAHK_ErrorHandler, -1)

; Suppress warning dialogs
#Warn All, StdOut

; ============================================================================
; Error Handler - Enhanced Version with _ScriptGetLines
; ============================================================================

CloudAHK_ErrorHandler(err, mode) {
    ; Try to get context lines if _ScriptGetLines is available
    contextLines := ""
    try {
        if IsSet(_ScriptGetLines) {
            lines := _ScriptGetLines(err.File, err.Line, 2)
            for i, line in lines {
                if (line.File != err.File)
                    continue

                ; Format: marker + line number + text (truncated)
                marker := (line.Number == err.Line) ? "> " : "  "
                text := RegExReplace(line.Text, "s)^.{50}\K.+", "...")
                text := StrReplace(text, "`n", "``n")
                text := StrReplace(text, "`r", "``r")

                contextLines .= Format("{1}{2:03}: {3}`n", marker, line.Number, text)
            }
        }
    }

    ; Build error output (AI-readable format)
    output := Format("
    (LTrim
    ## Runtime Error

    **Type:** {1}
    **Message:** {2}
    **File:** {3}
    **Line:** {4}
    **What:** {5}

    ### Source Context
    ```
    {6}```

    ### Stack Trace
    {7}

    ### Status
    {8}
    )",
        Type(err),
        err.Message,
        err.File,
        err.Line,
        err.What,
        contextLines != "" ? contextLines : "(context unavailable - build with linecontext branch)",
        FormatStack(err.Stack),
        (mode == "ExitApp" ? "Script" : "Thread") " will " (mode == "Return" ? "continue" : "exit")
    )

    ; Output to stderr
    FileAppend(output "`n", "**")

    ; Return -1 to continue if possible
    return -1
}

; Format stack trace for readability
FormatStack(stack) {
    if (stack == "")
        return "(empty)"

    result := ""
    for line in StrSplit(stack, "`n") {
        if (line != "")
            result .= "  " line "`n"
    }
    return RTrim(result, "`n")
}

; ============================================================================
; MsgBox Override - Redirect to stdout
; ============================================================================

MsgBox(Text?, Title?, Options?) {
    out := ""
    if IsSet(Title) && Title != ""
        out .= "[" Title "] "
    if IsSet(Text)
        out .= Text

    FileAppend(out "`n", "*")
    return "OK"
}

; ============================================================================
; InputBox Override
; ============================================================================

InputBox(Prompt?, Title?, Options?, Default?) {
    return {Value: IsSet(Default) ? Default : "", Result: "Cancel"}
}

; ============================================================================
; JSON Output Mode (for AI agent consumption)
; ============================================================================

CloudAHK_ErrorToJSON(err, mode) {
    ; Escape JSON strings
    escape := (s) => StrReplace(StrReplace(StrReplace(StrReplace(s,
        "\", "\\"), '"', '\"'), "`n", "\n"), "`r", "\r")

    json := Format('
    (LTrim
    {{
      "type": "{1}",
      "message": "{2}",
      "file": "{3}",
      "line": {4},
      "what": "{5}",
      "stack": "{6}",
      "mode": "{7}",
      "timestamp": "{8}"
    }}
    )',
        Type(err),
        escape(err.Message),
        escape(err.File),
        err.Line,
        escape(err.What),
        escape(err.Stack),
        mode,
        A_Now
    )

    return json
}
