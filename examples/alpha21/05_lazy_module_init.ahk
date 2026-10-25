; ============================================================
; alpha.21: module initialization order and forward references
; ============================================================
; The alpha.21 notes called module init lazy. It is not: every
; module still runs at startup, in reverse order of creation,
; before __Main's auto-execute section, even a module nothing
; imports (upstream design: Script::AutoExecSection in
; source/script.cpp runs them all). What alpha.21 (c0ab7108)
; added is that a first reference to a module's name runs that
; module early, if it has not run yet.
;   - Forward references work: #Import resolves a name
;     regardless of where the exporting module is declared.
;   - Import order no longer matters for name resolution.
;   - Startup is not faster: unused modules still run.
; ============================================================

; Define modules that reference each other's names.
; Logger imports from Formatter, which is declared after it.

#Module Logger

Log(msg)
{
    ; Uses FormatTimestamp from Formatter (forward reference)
    OutputDebug "[" FormatTimestamp() "] " msg
    return "[" FormatTimestamp() "] " msg
}

; Import from Formatter — which is defined AFTER Logger
#Import Formatter {FormatTimestamp}


#Module Formatter

FormatTimestamp()
{
    return FormatTime(, "yyyy-MM-dd HH:mm:ss")
}

FormatNumber(n, decimals := 2)
{
    return Format("{:." decimals "f}", n)
}


; --- Main ---
#Module __Main

#Import Logger {Log}
#Import Formatter {FormatNumber}

; Logger and Formatter have already run by now: modules run at
; startup in reverse order of creation (NeverUsed, Formatter,
; Logger), then __Main, so calling Log() runs no module code.
msg := Log("Application started")
MsgBox msg

MsgBox "Formatted: " FormatNumber(3.14159, 4)

; A module nothing imports.
; It still runs at startup, and first of all (it was created last), so this
; MsgBox appears before __Main's. That is upstream's design, not a fork bug
; (rechecked on alpha.33). Do not rely on "unused" modules staying inert.
#Module NeverUsed

MsgBox "NeverUsed initialized (nothing imports this module)"
global SideEffect := "This was set by NeverUsed"
