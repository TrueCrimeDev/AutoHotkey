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

; 4. Generic Object methods refuse a Struct (a020f5b0): calling
;    Object.Prototype.DefineProp on one, or ObjSetCapacity, throws TypeError
;    instead of treating its typed storage as an ordinary property table.
struct QaPt33 {
    x : Int32
    y : Int32
}
QaErr(f) {
    try {
        f()
        return "no error"
    } catch as e
        return Type(e) ": " e.Message
}
pt := QaPt33()
Assert.eq(QaErr(() => Object.Prototype.DefineProp.Call(pt, "z", {Value: 1})),
    "TypeError: Expected an Object but got a QaPt33.", "Object DefineProp on a Struct: TypeError")
Assert.eq(QaErr(() => ObjSetCapacity(pt, 10)),
    "TypeError: Expected an Object but got a QaPt33.", "ObjSetCapacity on a Struct: TypeError")

; 5. Indexing a property whose getter returns nothing throws UnsetError
;    (alpha.32): a.b[1] with b => unset.
qaUnset := {}
qaUnset.DefineProp("b", {Get: (*) => unset})
Assert.eq(QaErr(() => qaUnset.b[1]), "UnsetError: No value was returned.", "a.b[1] with an unset getter: UnsetError")

; 6. NumPut and NumGet take a struct class as the type (alpha.32).
qaBuf := Buffer(8, 0)
NumPut(Int32, -5, qaBuf)
Assert.eq(NumGet(qaBuf, Int32) " " NumGet(qaBuf, "UInt"), "-5 4294967291", "NumPut/NumGet with Int32 as the type")

; 7. #Import inside a function (alpha.32) imports for that function only.
r := RunSnippet(Lines33("F() {", "    #Import QaM {Hello}", "    return Hello()", "}",
    "Print(F())", "#Module QaM", "Hello() => `"hi`""))
Assert.eq(r.code " " r.out, "0 hi`n", "#Import inside a function")

; 8. A #Requires in an #Include file applies to that file's own code but not
;    to the module (47eabd41): the included function runs in v2.1 mode (a
;    no-value return throws UnsetError) while the main file's lines stay in
;    v2.0 mode (the same call returns "").
qaInc := A_Temp "\qa_alpha33_inc_" ProcessExist() ".ahk"
try FileDelete(qaInc)
FileAppend("#Requires AutoHotkey v2.1-alpha.33`nIncLines() => _ScriptGetLines(A_LineFile, 9999)`n", qaInc)
r := RunSnippet(Lines33("#Include " qaInc,
    "v := _ScriptGetLines(A_LineFile, 9999)", "Print(`"main: `" Type(v))",
    "try IncLines()", "catch as e", "    Print(`"include: `" Type(e))"))
FileDelete(qaInc)
Assert.eq(r.code " " r.out, "0 main: String`ninclude: UnsetError`n", "#Requires in an #Include: the file's code only")

; 9. Every module's body runs at startup, in reverse order of creation, and
;    __Main (created first) runs last; an #Import does not reorder them.
;    Upstream design since alpha.21 (Script::AutoExecSection), not lazy.
r := RunSnippet(Lines33("Print(`"main`")", "#Module Alpha", "Print(`"Alpha`")",
    "#Module Beta", "Print(`"Beta`")", "#Module Gamma", "#Import Alpha", "Print(`"Gamma`")"))
Assert.eq(r.code " " r.out, "0 Gamma`nBeta`nAlpha`nmain`n", "module bodies run in reverse order of creation")

Lines33(parts*) {
    out := ""
    for p in parts
        out .= p "`n"
    return out
}

Assert.Summary()
