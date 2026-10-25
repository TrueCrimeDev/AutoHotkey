#Requires AutoHotkey v2.1-alpha.33
; test_alpha33.ahk -- pins behaviour from the upstream v2.1-alpha.32/.33 merge
; (commit b44b48e3, 2026-10-08) and the fork fixes layered on it. Every fact
; below was verified against 2.1-alpha.33+Console, and each section was also run
; on the engine before its fix; the "OLD:" note on a section records what that
; engine did, so an assert that only passes here is genuinely pinning the change.
;
; Process-exit behaviour is probed in a child process via RunSnippet so a crash
; in cleanup is an assertable exit code, not something that kills this test.
; Runtime semantics are asserted in-process.
#Include ..\Assert.ahk
#Include ..\Harness.ahk

; In-file module backing the &Module.Var sections. Both globals are exported
; implicitly (alpha.31 rules), and __Main imports the module as a namespace
; without importing either name.
#Module QaRefMod
global QaCount := 1
global QaName := "init"

#Module __Main
#Import QaRefMod

; 1. `&Module.Var` (alpha.33 `Module.__Ref`) returns a reference that outlives
;    the expression that took it. Upstream's `ScriptModule::__Ref` handed back
;    `Var::GetRef()`'s uncounted VarRef without an AddRef, so the evaluator's
;    Release of the method result freed it while the module variable still
;    aliased it. Reading and writing through %ref% already worked on that
;    engine; everything after the reference was released did not.
; OLD: `ref2 := ""` below released the VarRef's only count: `%ref%` on the next
;      line threw "This global variable has not been assigned a value.
;      Specifically: QaCount" and the process exited 0xC0000374 (this file then
;      had no summary line, i.e. CRASH).
ref := &QaRefMod.QaCount
Assert.eq(Type(ref), "VarRef", "&Module.Var: the result is a VarRef")
Assert.eq(%ref%, 1, "&Module.Var: %ref% reads the module variable")
%ref% := 5
Assert.eq(QaRefMod.QaCount, 5, "&Module.Var: a write through %ref% reaches the module variable")
QaRefMod.QaCount := 6
Assert.eq(%ref%, 6, "&Module.Var: a later module write is seen through %ref%")

; A second `&` on the same variable yields the same VarRef (the variable is
; already an alias of it), so two live references must both be releasable.
ref2 := &QaRefMod.QaCount
Assert.eq(ObjPtr(ref2), ObjPtr(ref), "&Module.Var: a second reference is the same VarRef")
ref2 := ""
Assert.eq(%ref%, 6, "&Module.Var: the first reference still reads after the second is released")
ref := ""
Assert.truthy(true, "&Module.Var: both references released without crashing")
Assert.eq(QaRefMod.QaCount, 6, "&Module.Var: the module variable keeps its value after its references are gone")
QaRefMod.QaCount := 7
Assert.eq(QaRefMod.QaCount, 7, "&Module.Var: the module variable is still writable afterwards")

; 2. `&Module.Var` passed to a ByRef parameter or a built-in output parameter
;    writes through to the module variable, which stays set afterwards.
; OLD: the callee ran, then the engine's Release of the `__Ref` result freed the
;      VarRef the module variable aliased: `QaRefMod.QaCount` read as unset
;      (UnsetError, "<UnsetError>" below) and the process died with 0xC0000374
;      at exit.
QaBump(&v) {
    v += 10
}

; Reads the module variable without letting an UnsetError abort the test.
QaReadCount() {
    try
        return QaRefMod.QaCount
    catch as e
        return "<" Type(e) ">"
}

QaBump(&QaRefMod.QaCount)
Assert.eq(QaReadCount(), 17, "ByRef &Module.Var: the callee's write reaches the module variable")
QaBump(&QaRefMod.QaCount)
Assert.eq(QaReadCount(), 27, "ByRef &Module.Var: a second ByRef pass still finds a live variable")
QaRefMod.QaCount := 8
Assert.eq(QaReadCount(), 8, "ByRef &Module.Var: a plain module write still works afterwards")

SplitPath("C:\dir\file.txt", &QaRefMod.QaName)
Assert.eq(QaRefMod.QaName, "file.txt", "built-in output parameter: &Module.Var receives the output")

; 3. The process exits cleanly whether the reference is released first or is
;    still held at exit. The old failure was a heap corruption in cleanup after
;    the script had run to its end, so only a child's exit code can pin it.
; OLD: exit 0xC0000374 (3221226356 from GetExitCodeProcess) for both: the held
;      case printed "done" first; the ByRef case reported an UnsetError at its
;      first Print and the error exit's cleanup still died the same way.
r := RunSnippet("#Module Mod`nglobal X := 1`n#Module __Main`n#Import Mod`n"
    . "ref := &Mod.X`n%ref% := %ref% + 1`nPrint(Mod.X)`nPrint(`"done`")")
Assert.eq(r.code, 0, "held &Module.Var at exit: exit 0")
Assert.eq(r.out, "2`ndone`n", "held &Module.Var at exit: ran to the end")

r := RunSnippet("#Module Mod`nglobal X := 1`n#Module __Main`n#Import Mod`n"
    . "Bump(&v) => v += 10`nBump(&Mod.X)`nPrint(Mod.X)`nref := &Mod.X`nref := `"`"`n"
    . "Print(Mod.X)`nPrint(`"done`")")
Assert.eq(r.code, 0, "ByRef then released &Module.Var: exit 0")
Assert.eq(r.out, "11`n11`ndone`n", "ByRef then released &Module.Var: the variable stays set")

Assert.Summary()
