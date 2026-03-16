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

; Define modules that reference each other's exports.
; In alpha.20, this required careful ordering.
; In alpha.21, it "just works" because modules init lazily.

#Module Logger

export Log(msg)
{
    ; Uses FormatTimestamp from Formatter (forward reference)
    OutputDebug "[" FormatTimestamp() "] " msg
    return "[" FormatTimestamp() "] " msg
}

; Import from Formatter — which is defined AFTER Logger
#Import {FormatTimestamp} from Formatter


#Module Formatter

export FormatTimestamp()
{
    return FormatTime(, "yyyy-MM-dd HH:mm:ss")
}

export FormatNumber(n, decimals := 2)
{
    return Format("{:." decimals "f}", n)
}


; --- Main ---
#Module __Main

#Import {Log} from Logger
#Import {FormatNumber} from Formatter

; Logger module initializes only when Log() is first called.
; At that point, Formatter is also initialized (because Logger imports from it).
msg := Log("Application started")
MsgBox msg

MsgBox "Formatted: " FormatNumber(3.14159, 4)

; Demonstrate that unused modules don't run
#Module NeverUsed

; This code never executes because nothing imports from NeverUsed
MsgBox "You should never see this!"
global SideEffect := "This was set by NeverUsed"
