#Requires AutoHotkey v2.1-alpha.29
; Deliberately crashes via DllCall. NOT part of automated tests.
; Use to verify the SEH filter writes a [FATAL] record.
; NOTE: AHK intercepts access violations from DllCall internally and converts them
; to [ERROR] script exceptions. The SetUnhandledExceptionFilter only fires for
; exceptions that escape AHK's own internal handling (i.e., crashes in the C++
; interpreter itself, not in user scripts via DllCall).
DllCall("RtlMoveMemory", "Ptr", 0, "Ptr", 0, "Ptr", 4096)
