; ============================================================
; alpha.21 Feature: Lazy module initialization
; ============================================================
; Modules now execute on first reference, not at load time.
; This means:
;   - Faster startup (unused modules don't run)
;   - Forward references work (module A can import from B
;     even if B imports from A, as long as they don't create
;     a circular dependency at init time)
;   - Import order no longer matters for name resolution
; ============================================================

; Define modules that reference each other's names.
; In alpha.20, this required careful ordering.
; In alpha.21, it "just works" because modules init lazily.

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

; Logger module initializes only when Log() is first called.
; At that point, Formatter is also initialized (because Logger imports from it).
msg := Log("Application started")
MsgBox msg

MsgBox "Formatted: " FormatNumber(3.14159, 4)

; A module nothing imports.
; alpha.21 documented that such a module never initializes. Observed on the
; alpha.31 engine: it DOES run, and before __Main's auto-execute section, so
; this MsgBox appears first. Do not rely on "unused" modules staying inert.
#Module NeverUsed

MsgBox "NeverUsed initialized (nothing imports this module)"
global SideEffect := "This was set by NeverUsed"
