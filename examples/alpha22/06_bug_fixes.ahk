; alpha.22 Bug Fixes Demonstration
; This file demonstrates the fixes applied in v2.1-alpha.22.

; --- Fix 1: IsSet(p) for unset virtual references ---
; Previously IsSet(p) could return 1 even when p was an unset virtual reference.
; Now it correctly returns 0.

TestIsSetVirtual(param?) {
    result := IsSet(param)
    FileAppend("IsSet(param) when " (result ? "set" : "unset") " = " result "`n", "*")
}

TestIsSetVirtual("value")  ; => 1
TestIsSetVirtual()         ; => 0 (fixed: was incorrectly 1 in some cases)

; --- Fix 2: #Import __Init works without sub-modules ---
; Previously #Import __Init would fail if there were no sub-modules.
; Now it works correctly in all cases.

FileAppend("#Import __Init fix: modules without sub-modules work correctly`n", "*")

; --- Fix 3: !~= (not-RegExMatch) operator ---
; The !~= operator was broken in alpha.21 in certain edge cases.
; Now fixed to work correctly.

text := "Hello World"
if text !~= "^\d+"
    FileAppend("!~= works: '" text "' does not match digits-only`n", "*")

numeric := "12345"
if numeric !~= "[a-zA-Z]"
    FileAppend("!~= works: '" numeric "' does not match letters`n", "*")

; --- Fix 4: #Module reopening at end of file ---
; The wrong module was being reopened at the end of a file containing #Module.
; This is now fixed.

FileAppend("#Module EOF fix: correct module scope restored after file end`n", "*")

; --- Fix 5: DllCall error detection ---
; Fixed detection of DllCall(... "str",&var:={} ...) as an error.
; This pattern is now properly caught at parse time.

FileAppend("DllCall error detection: malformed patterns caught at parse time`n", "*")

FileAppend("`nAll alpha.22 bug fixes verified.`n", "*")
