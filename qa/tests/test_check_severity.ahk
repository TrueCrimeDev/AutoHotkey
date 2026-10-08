#Requires AutoHotkey v2.1-alpha.31
#Include ..\Assert.ahk
; test_check_severity.ahk -- Check(Source) reports the error, not a warning
; that the check child printed before it.
;
; A VarUnset warning comes from PreparseVarRefs, which runs before
; PreparseCommands, so the child prints it ahead of a PreparseCommands error
; such as a missing Goto label or a Break outside a loop. Check() used to build
; its single diagnostic from the first "kind":"diagnostic" record of any
; severity, so it returned the warning (Severity "warning", Code 0) for a
; source that fails to load. It now takes the first error record and falls
; back to the first record only when none exists (source/console_check.cpp,
; CheckFindDiagRecord).

nl := "`n"

; --- a warning, then a "Label not found" error ---
r := Check("x := neverAssigned" nl "Goto NoSuchLabel" nl)
Assert.truthy(InStr(r.Raw, '"severity":"warning"') && InStr(r.Raw, '"severity":"warning"') < InStr(r.Raw, '"severity":"error"'),
    "goto: premise - the child prints the warning before the error")
Assert.eq(r.Ok, 0, "goto: Ok=0")
Assert.eq(r.Diagnostics.Length, 1, "goto: one diagnostic")
d := r.Diagnostics.Length ? r.Diagnostics[1] : {Severity: "", Type: "", Code: "", Message: "", Extra: "", Line: ""}
Assert.eq(d.Severity, "error", "goto: Severity is error, not the warning's")
Assert.eq(d.Type, "Error", "goto: Type")
Assert.eq(d.Code, 13, "goto: Code is the validate exit code, not the warning's 0")
Assert.eq(d.Message, "Label not found in current scope.", "goto: Message is the error's")
Assert.eq(d.Extra, "NoSuchLabel", "goto: Extra")
Assert.eq(d.Line, 2, "goto: Line of the error")

; --- two warnings, then a Break outside a loop ---
r := Check("x := neverAssigned" nl "y := alsoNever" nl "break" nl)
Assert.eq(r.Ok, 0, "break: Ok=0")
Assert.eq(r.Diagnostics.Length, 1, "break: one diagnostic")
d := r.Diagnostics.Length ? r.Diagnostics[1] : {Severity: "", Message: "", Line: ""}
Assert.eq(d.Severity, "error", "break: Severity is error after two warnings")
Assert.eq(d.Message, "Break/Continue must be enclosed by a Loop.", "break: Message is the error's")
Assert.eq(d.Line, 3, "break: Line of the error")

; --- warning-only valid source: still Ok with no diagnostics ---
r := Check("x := neverAssigned" nl)
Assert.truthy(InStr(r.Raw, '"severity":"warning"'), "warning only: premise - the child printed a warning")
Assert.eq(r.Ok, 1, "warning only: Ok=1")
Assert.eq(r.Diagnostics.Length, 0, "warning only: no diagnostics")

; --- control: an error with no warning before it ---
r := Check("x := (1 +" nl)
Assert.eq(r.Ok, 0, "error only: Ok=0")
Assert.eq(r.Diagnostics.Length, 1, "error only: one diagnostic")
d := r.Diagnostics.Length ? r.Diagnostics[1] : {Severity: "", Code: "", Line: ""}
Assert.eq(d.Severity, "error", "error only: Severity")
Assert.eq(d.Code, 13, "error only: Code")
Assert.eq(d.Line, 1, "error only: Line")

Assert.Summary()
