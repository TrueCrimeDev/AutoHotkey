#Requires AutoHotkey v2.1-alpha.31
; test_alpha31.ahk -- pins the behaviour changes that arrived with the upstream
; v2.1-alpha.31 merge (commit c73ae823, 2026-09-08). Every fact below was
; verified against 2.1-alpha.31+Console on 2026-09-08, and each section was
; also run on the pre-merge 2.1-alpha.30+Console engine; the "OLD:" note on a
; section records what that engine did, so an assert that only passes here is
; genuinely pinning the change. Sections marked "protects" pass on both engines
; and exist to guard a fix that alpha.31 made and could regress.
;
; Load-time behaviour (rejected syntax, class-declaration errors) is probed in
; a child process via RunSnippet so a failed parse is an assertable exit code,
; not something that kills this test. Runtime semantics are asserted in-process.
#Include ..\Assert.ahk
#Include ..\Harness.ahk

; ============================================================================
; In-file modules backing the export/import sections. Nothing here uses the
; removed `export` keyword: every name defined in a #Module is exported
; implicitly (upstream 95c73587 / 5721379c).
; ============================================================================

#Module QaImplied
global QaG := 7
QaFn(x) => x * 2
class QaK {
    static Tag := "k"
}

; Facade A imports its core privately (plain #Import): the importer's callers
; must not see QaGreetA.
#Module QaCoreA
QaGreetA(name) => "hi " name
#Module QaFacadeA
#Import QaCoreA {*}
QaShoutA(name) => StrUpper(QaGreetA(name))

; Facade B re-exports its core with `#Import Export`.
#Module QaCoreB
QaGreetB(name) => "hi " name
#Module QaFacadeB
#Import Export QaCoreB {*}
QaShoutB(name) => StrUpper(QaGreetB(name))

; Two-level import of a declared-but-unset global (upstream 1a5f7c47).
#Module QaBase
global QaCfg
#Module QaMid
#Import Export QaBase {QaCfg}

#Module __Main
#Import QaImplied {*}
#Import QaImplied
#Import QaFacadeA {*}
#Import QaFacadeB {*}
#Import QaMid {QaCfg}

; ============================================================================
; 1. The `export` keyword is gone from function, global and class declarations
;    (upstream reverts 52caabbc / 10c1da5a / d7b9469a).
; OLD: all three snippets loaded and printed "loaded" (exit 0).
; ============================================================================

; `export Fn() {` now parses `export` as a bare variable read, so it loads
; (with a #Warn) and dies at runtime on the unset name.
r := RunSnippet("export Foo() {`n    return 1`n}`nPrint(`"loaded`")")
Assert.eq(r.code, 10, "export Fn() {: runtime error (exit 10)")
Assert.truthy(InStr(r.out, "This global variable has not been assigned a value."),
    "export Fn() {: unset-variable error")
; Anchored on the error line: the load-time #Warn line also says
; "Specifically: export", so a bare InStr would not prove the runtime error names it.
Assert.truthy(RegExMatch(r.out, "m)^.*==> This global variable has not been assigned a value\.\R\s+Specifically: export"),
    "export Fn() {: the unset name is 'export'")
Assert.falsy(InStr(r.out, "loaded"), "export Fn() {: script body never runs")

; `export global X := 1` is a load error: `global` is now a variable name here.
r := RunSnippet("export global X := 1`nPrint(`"loaded`")")
Assert.eq(r.code, 12, "export global: load error (exit 12)")
Assert.truthy(InStr(r.out, "reserved word must not be used as a variable name"),
    "export global: reserved-word diagnostic")
Assert.truthy(InStr(r.out, '"global"'), "export global: names 'global' as the offender")

; `export class K {` is a load error at the brace.
r := RunSnippet("export class K {`n}`nPrint(`"loaded`")")
Assert.eq(r.code, 12, "export class: load error (exit 12)")
Assert.truthy(InStr(r.out, 'Unexpected "{"'), "export class: unexpected-brace diagnostic")

; ============================================================================
; 2. Export is implied for names defined inside a #Module.
; OLD: only the `#Import QaImplied {*}` names were private -- exit 10,
;      "This global variable has not been assigned a value. Specifically:
;      QaFn" (QaG and QaK likewise). Module-namespace access (`QaImplied.QaFn`,
;      `QaImplied.QaG`) already reached un-exported names on alpha.30, so the
;      two namespace asserts only "protect".
; ============================================================================
Assert.eq(QaFn(3), 6, "implied export: module function callable after #Import {*}")
Assert.eq(QaG, 7, "implied export: module global visible after #Import {*}")
Assert.eq(QaK.Tag, "k", "implied export: module class visible after #Import {*}")
Assert.eq(QaImplied.QaFn(4), 8, "module namespace: function reachable (protects)")
Assert.eq(QaImplied.QaG, 7, "module namespace: global reachable (protects)")

; ============================================================================
; 3. Imported names stay private to the importer unless `#Import Export`.
; OLD: the plain-import snippet exited 10 for a different reason (nothing was
;      exported without the keyword, so even QaShout was unset); with an
;      explicit `export` the visibility rules were the same -> "protects".
; ============================================================================
Assert.eq(QaShoutA("bob"), "HI BOB", "facade can use its private import")
Assert.falsy(IsSet(QaGreetA), "plain #Import is not re-exported to the facade's importers")
Assert.eq(QaShoutB("bob"), "HI BOB", "re-exporting facade can use its import")
Assert.eq(QaGreetB("ann"), "hi ann", "#Import Export re-exports the imported name")

; Calling the non-re-exported name from the top module is a runtime unset error.
; OLD: exit 10 as well, but at Shout (nothing was exported), so the exit code
;      alone does not separate the engines; "Shout itself was exported" and
;      "facade call still ran" do. The Greet check is anchored on the error line
;      because the load-time #Warn line also says "Specifically: Greet".
r := RunSnippet("#Module Core`nGreet(n) => `"hi `" n`n#Module Facade`n#Import Core {*}`n"
    . "Shout(n) => StrUpper(Greet(n))`n#Module __Main`n#Import Facade {*}`n"
    . "Print(Shout(`"bob`"))`nPrint(Greet(`"ann`"))")
Assert.eq(r.code, 10, "calling a non-re-exported import: exit 10")
Assert.falsy(InStr(r.out, "Specifically: Shout"), "calling a non-re-exported import: Shout itself was exported")
Assert.truthy(InStr(r.out, "HI BOB"), "calling a non-re-exported import: facade call still ran")
Assert.truthy(RegExMatch(r.out, "m)^.*==> This global variable has not been assigned a value\.\R\s+Specifically: Greet"),
    "calling a non-re-exported import: the runtime error names Greet")

; ============================================================================
; 4. Props(v) retains the value of v instead of aliasing the variable
;    (upstream ba1a99e3). Observable once String.Prototype has a dynamic
;    property, because the getter's `this` is the enumerator's captured value.
;    String.Prototype has no DefineProp of its own; borrow Object's.
; OLD: cases A and B enumerated "changed"; case C threw "This parameter has
;      not been assigned a value. Specifically: this" (dangling local).
; ============================================================================
Object.Prototype.DefineProp.Call(String.Prototype, "QaSelf", {get: (this) => this})

PropVals(e) {
    m := Map()
    for name, val in e
        m[name] := val
    return m
}

; A: plain variable argument, reassigned before enumeration.
v := "b"
e := Props(v)
v := "changed"
Assert.eq(PropVals(e)["QaSelf"], "b", "Props(v): enumerator keeps v's value after v is reassigned")

; B: the assignment-expression form from the upstream commit message.
e2 := Props(a := "b")
a := "changed"
Assert.eq(PropVals(e2)["QaSelf"], "b", "Props(a:=`"b`"): enumerator keeps the assigned value")

; C: the captured variable is a local that has gone out of scope.
QaLocalProps() {
    x := "loc"
    return Props(x)
}
e3 := QaLocalProps()
acc := {vals: ""}
Assert.noThrow(() => acc.vals := PropVals(e3), "Props(local): enumerating after the frame is gone does not throw")
Assert.eq(acc.vals ? acc.vals["QaSelf"] : "<threw>", "loc", "Props(local): value survives the frame")

; ============================================================================
; 5. Variant output parameters are "made blank" ("") rather than left unset
;    when the function has nothing to report. Upstream 7dbdf233 added
;    `else if (value.symbol == SYM_MISSING) result = var->AssignString();` to
;    the assign block (MdFunc.cpp:536); 9a8b1514 then moved the check into the
;    Variant branch as `if (value.symbol == SYM_MISSING) value.SetValue(_T(""), 0);`
;    (MdFunc.cpp:494 after the merge), which is the code that is live.
;    PixelSearch's FoundX/FoundY are ResultToken (Variant) outputs; an
;    off-screen region never matches, so the not-found path is deterministic.
;    Needs a desktop: PixelSearch returns FR_E_WIN32 (an OSError here) when
;    GetDC(NULL) fails (source/lib/pixel.cpp), so a session-0 / no-desktop run
;    would throw instead of reporting not-found. Deliberately not guarded: a
;    try/skip would also hide a real regression on the desktop runner in use.
; OLD: IsSet(px) = 0 (both outputs left unset).
; ============================================================================
found := PixelSearch(&px, &py, -100000, -100000, -100000, -100000, 0x123456)
Assert.eq(found, 0, "PixelSearch off-screen: not found")
Assert.truthy(IsSet(px), "PixelSearch not found: FoundX is set (made blank)")
Assert.truthy(IsSet(py), "PixelSearch not found: FoundY is set (made blank)")
Assert.eq(px, "", "PixelSearch not found: FoundX is the empty string")
Assert.eq(py, "", "PixelSearch not found: FoundY is the empty string")

; ============================================================================
; 6. RegExMatch's OutputVar is unset (not "") on no match in v2.1 mode.
;    The alpha.31 output-parameter change briefly broke this (9a8b1514 is the
;    fix); alpha.30 never had the bug -> "protects".
; ============================================================================
RegExMatch("hello", "x", &miss)
RegExMatch("hello", "l+", &hit)
Assert.falsy(IsSet(miss), "RegExMatch no match: OutputVar stays unset (protects 9a8b1514)")
Assert.eq(hit[0], "ll", "RegExMatch match: OutputVar is the match object")

; ============================================================================
; 7. A multi-level import of an unset global stays unset (upstream 1a5f7c47).
; OLD: IsSet(QaCfg) = 0 but `QaCfg ?? "<unset>"` evaluated to "" -- the
;      double alias turned unset into an empty string on read.
; ============================================================================
Assert.falsy(IsSet(QaCfg), "multi-level import: IsSet is false for an unset global")
Assert.eq(QaCfg ?? "<unset>", "<unset>", "multi-level import: ?? sees unset, not `"`"")

; ============================================================================
; 8. The unset-return error's Extra has no trailing character when the
;    callee name was built from a %deref% plus literal text (upstream d8e29658).
; OLD: `f.%'C'%all()` reported Extra "l()" (the last literal char leaked in);
;      the other three forms were already as pinned here.
; ============================================================================
QaUnsetFn() => unset

QaCatch(fn) {
    try
        fn()
    catch as e
        return e
    return ""
}

n := "QaUnsetFn"
e := QaCatch(() => %n%())
Assert.eq(Type(e), "UnsetError", "unset return: %name%() throws UnsetError")
Assert.eq(e.Message, "No value was returned.", "unset return: %name%() message")
Assert.eq(e.Extra, "()", "unset return: %name%() Extra is '()'")

e := QaCatch(() => QaUnsetFn.%'C'%all())
Assert.eq(e.Extra, "()", "unset return: f.%'C'%all() Extra is '()' (no trailing 'l')")
Assert.eq(e.Message, "No value was returned.", "unset return: f.%'C'%all() message")

e := QaCatch(() => QaUnsetFn.%'Call'%())
Assert.eq(e.Extra, "%()", "unset return: f.%'Call'%() Extra is '%()' (protects)")

e := QaCatch(() => QaUnsetFn())
Assert.eq(e.Extra, "QaUnsetFn()", "unset return: direct call Extra is the full call (protects)")

; ============================================================================
; 9. A setter may be declared after a separate getter of the same property
;    (upstream e6afdabc). The reverse order was already permitted.
; OLD: getter-then-setter failed to load -- "Duplicate declaration.
;      Specifically: Level" (exit 12); setter-then-getter loaded ("protects").
; ============================================================================
r := RunSnippet("class Cfg {`n    Level {`n        get => 42`n    }`n    Level {`n"
    . "        set => this._log := `"set `" value`n    }`n}`n"
    . "c := Cfg()`nc.Level := 7`nPrint(`"{} / {}`", c.Level, c._log)")
Assert.eq(r.code, 0, "setter after getter: loads and runs")
Assert.eq(r.out, "42 / set 7`n", "setter after getter: both halves work")

r := RunSnippet("class Cfg {`n    Level {`n        set => this._log := `"set `" value`n    }`n"
    . "    Level {`n        get => 42`n    }`n}`n"
    . "c := Cfg()`nc.Level := 7`nPrint(`"{} / {}`", c.Level, c._log)")
Assert.eq(r.code, 0, "getter after setter: still loads (protects)")
Assert.eq(r.out, "42 / set 7`n", "getter after setter: both halves work (protects)")

; ============================================================================
; 10. A class cannot extend itself, directly or through a forward reference
;     (upstream 69434cf3 adds the check in DefineClass). alpha.30 already
;     rejected both shapes from its unresolved-class pass -> "protects".
; ============================================================================
r := RunSnippet("class Self extends Self {`n}`nPrint(`"loaded`")")
Assert.eq(r.code, 12, "class X extends X: load error (protects)")
Assert.truthy(InStr(r.out, "Invalid base class."), "class X extends X: 'Invalid base class.' (protects)")
Assert.truthy(InStr(r.out, "Specifically: Self"), "class X extends X: names the class (protects)")

; B is first created as A's unresolved base, then defined as its own base.
r := RunSnippet("class A extends B {`n}`nclass B extends B {`n}`nPrint(`"loaded`")")
Assert.eq(r.code, 12, "forward-ref self-extend: load error (protects)")
Assert.truthy(InStr(r.out, "Invalid base class."), "forward-ref self-extend: 'Invalid base class.' (protects)")

; ============================================================================
; 11. `a := b` where b is a virtual reference (a ByRef parameter bound to an
;     object with __Value) no longer fails (upstream da73eb39: UpdateVirtualObj
;     clears VAR_ATTRIB_UNINITIALIZED so PerformAssign's fast path proceeds).
; OLD: "This parameter has not been assigned a value. Specifically: src"
;      thrown at the `a := src` line (exit 10).
; Note: on alpha.31 the fast path copies the referenced *object* (Type(a) is
;      "QaCell", not Integer), while `src + 0`, `(src ?? 0)` and Print(src) all
;      read __Value. Var::Assign(Var&) documents a VAR_NORMAL precondition that
;      a VAR_VIRTUAL_OBJ source violates, so that value is not pinned here.
; ============================================================================
class QaCell {
    __New(v) => this._v := v
    __Value {
        get => this._v
        set => this._v := value
    }
}

QaCopyOut(&src) {
    a := src            ; the simple-assignment fast path (not an expression)
    return IsSet(a)
}
QaReadWrite(&src) {
    before := src + 0   ; expression path: reads __Value
    src := 99           ; assignment through the virtual reference
    return before
}

cell := QaCell(42)
Assert.noThrow(() => QaCopyOut(cell), "a := src (virtual reference): no unset-parameter error")
Assert.truthy(QaCopyOut(cell), "a := src (virtual reference): a is set afterwards")
Assert.eq(QaReadWrite(cell), 42, "virtual reference: expression read sees __Value")
Assert.eq(cell._v, 99, "virtual reference: assignment writes through __Value")

; ============================================================================
; 12. Destructing a boxed pointer whose struct holds a nested Struct.Array of
;     structs no longer crashes (upstream dde94cb0: ~Object skips nested items
;     whose vftbl was never initialised by the sparse-init path). The test
;     process surviving the release IS the assertion; run.ahk reports CRASH if
;     it does not. Kept last so a crash cannot mask the sections above. The
;     two `Assert.truthy(true, ...)` lines after each release are counters that
;     name the survival point in the summary, not checks -- they cannot fail.
; OLD: "Invalid memory read/write." at the `p := ""` line (exit 11) for both
;      shapes below.
; ============================================================================
Struct QaInner {
    a: Int32
}
Struct QaOuter {
    items: QaInner[3]
    b: Int32
}
buf := Buffer(64, 0)

; Struct.At() view: touching .items sparse-inits the array object but not its
; three elements; releasing the view destructs all of them.
p := QaOuter.At(buf.Ptr)
Assert.eq(p.items.Length, 3, "boxed pointer: nested Struct.Array is reachable")
p := ""
Assert.truthy(true, "boxed pointer (At): released without crashing")

; Same through a .Ptr box dereferenced with __Value, and with one element
; touched so constructed and unconstructed items coexist.
q := QaOuter.Ptr()
NumPut("ptr", buf.Ptr, q.Ptr)
view := q.__Value
view.items[2].a := 5
Assert.eq(view.items[2].a, 5, "boxed pointer (.Ptr/__Value): element write round-trips")
view := ""
q := ""
Assert.truthy(true, "boxed pointer (.Ptr/__Value): released without crashing")

Assert.Summary()
