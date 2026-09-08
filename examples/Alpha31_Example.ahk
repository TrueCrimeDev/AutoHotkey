/*
Alpha31_Example.ahk -- AutoHotkey v2.1-alpha.31 feature showcase

This file targets upstream tag v2.1-alpha.31 (28 Aug 2026), merged into the
fork on 2026-09-08. Run with the fork's bin\AutoHotkey64.exe rebuilt after
the merge (identifies as 2.1-alpha.31+Console). Every section prints what
the engine actually does; comments record what alpha.30 did instead.

What's new since Alpha30_Example.ahk:

  Changed:
    1. 'export' is implied for every name defined inside a #Module. The
       'export' keyword itself is gone: 'export global' / 'export class'
       fail to load and 'export Foo() {' dies at runtime (see section 2).

  Unchanged, clarified by the release note:
    2. Imported names are "still not exported by default"; '#Import Export'
       re-exports them. alpha.30 behaves identically (same IsSet output in
       section 2) -- the note only spells out the rule.

  Fixed:
    3. Some output parameters became unset when they should be "made blank"
       (PixelSearch / ImageSearch X,Y on no match).
    4. RegExMatch's &Match stays unset on no match in v2.1 mode (a mid-cycle
       regression of #3, repaired before the release).
    5. Props(v) retains the value of v instead of aliasing v.
    6. Multi-level import turned unset into "".
    7. Trailing character in the "No value was returned" Extra text for a
       dynamic call.
    8. Crash when destructing a boxed pointer to a struct array.
    9. Simple 'a := b' where b is a virtual reference (a ByRef parameter
       bound to an object with __Value) threw "not been assigned a value".

  Merged from the v2.0 line (shown with the fork-only Check() BIF):
   10. A class cannot extend itself (Check Ok=0) -- already rejected by the
       fork's alpha.30 build, so no behaviour change here.
   11. A setter block may follow a separate getter block (Check Ok=1;
       alpha.30: "Duplicate declaration").

  Not demonstrated (needs a GUI or the built-in AHK module):
    - GuiCtrl.OnMessage threads honour #MaxThreads and Thread Priority > 0
    - '#Import' inside '#Module AHK'
    - Send "{Click X Y Count}", ListView header ContextMenu Item, ComObjQuery leak

Print() and Check() are fork-only BIFs (see updates.md): Print(Fmt, Values*)
formats and writes to stdout; Check(Source) spawns this exe in check mode
and returns { Ok, Diagnostics, Raw }. Everything else is upstream syntax.

Run: bin\AutoHotkey64.exe examples\Alpha31_Example.ahk
*/
#Requires AutoHotkey v2.1-alpha.31

; ─────────────────────────────────────────────────────
; Modules used by sections 1, 2 and 6. In-file modules start with
; '#Module Name' and end at the next '#Module'; '#Module __Main' returns
; to the default module (source/script_module.cpp: FindDirectiveModule).
; ─────────────────────────────────────────────────────

#Module Geometry
; No 'export' anywhere: every name defined here is exported implicitly.
global PI := 3.14159265358979
Area(r) => PI * r ** 2
class Circle {
    __New(r) => this.r := r
    Area => Area(this.r)
}
counter := 0
Bump() {
    global counter
    return ++counter
}
; Names starting with '_' are the one exception: wildcard imports skip them.
_Hidden() => "only reachable as Geometry._Hidden()"

#Module Base
Greet() => "hello from Base"

#Module Base2
Wave() => "wave from Base2"

#Module Relay
; Plain import: Greet is usable here but is NOT re-exported.
#Import Base {*}
RelayGreet() => Greet()

#Module ReExport
; '#Import Export' re-exports what it imports (pre-existing syntax).
#Import Export Base2 {*}

#Module Leaf
Later := unset            ; declared, deliberately unset
Marker := "Leaf ran"

#Module Middle
; Explicit re-import creates a two-level alias chain __Main -> Middle -> Leaf.
#Import Leaf {Later as Later2, Marker as Marker2}

#Module __Main
#Import Geometry            ; the module object itself
#Import Geometry {*}        ; ...and every exported name
#Import Relay {*}
#Import ReExport {*}
#Import Middle {Later2, Marker2}

Print("=== AutoHotkey v2.1-alpha.31 Feature Showcase ===")
Print("Version: {}", A_AhkVersion)
Print("")

; ─────────────────────────────────────────────────────
; 1. Changed: export is implied inside a #Module
; ─────────────────────────────────────────────────────
Print("── 1. Implied export: '#Import Geometry {*}' sees everything ──")

; alpha.30 needed 'export global PI', 'export Area()', 'export class Circle'
; for a wildcard import to see them; without the keyword this section died
; with "This global variable has not been assigned a value. Specifically: PI".
; Note: '#Import Geometry' alone binds only the module object (Geometry.PI);
; use '{*}' or '{PI, Area}' to bring names into scope.

Print("  PI = {}", PI)
Print("  Area(2) = {:.4f}", Area(2))
Print("  Circle(3).Area = {:.4f}", Circle(3).Area)
before := counter           ; plain-variable args are read after Bump() runs
Print("  counter = {}, Bump() = {}, counter = {}", before, Bump(), counter)
Print("  Geometry.PI via module object = {}", Geometry.PI)
Print("  IsSet(_Hidden) after wildcard import = {}", IsSet(%'_Hidden'%))
Print("  Geometry._Hidden() = '{}'", Geometry._Hidden())
Print("")

; ─────────────────────────────────────────────────────
; 2. Unchanged: imports are private unless '#Import Export'
; ─────────────────────────────────────────────────────
Print("── 2. Imports are not re-exported unless '#Import Export' (same as alpha.30) ──")

; __Main wildcard-imports both Relay (which imported Base privately) and
; ReExport (which re-exported Base2). Only Base2's name comes through.
; A direct 'Greet()' here would be a load-time "never assigned" warning, so
; the private case is probed dynamically. alpha.30 prints the same two
; IsSet values: '#Import Export' predates this release and the note merely
; restates that imported names are not exported by default.

Print("  IsSet(Greet) via Relay {{}*{}}      = {}  (private import, not visible)", IsSet(%'Greet'%))
Print("  IsSet(Wave) via ReExport {{}*{}}    = {}  (re-exported, visible)", IsSet(%'Wave'%))
Print("  Wave() = '{}'", Wave())
Print("  RelayGreet() = '{}'  (Relay itself can still use Greet)", RelayGreet())

; The removed 'export' keyword, as observed on this engine (via Check()):
;   #Module M
;   export Foo() {         ; loads with a warning, dies at runtime with
;   }                      ; "This global variable has not been assigned a
;                          ;  value. Specifically: export" (exit 10)
;   export global X := 1   ; The following reserved word must not be used as
;                          ; a variable name: "global"  (exit 12)
;   export class K {       ; Unexpected "{"  (exit 12)
;   }

; Check() is fork-only: it spawns this exe in check mode and returns
; { Ok, Diagnostics, Raw }. alpha.30 accepted all three forms (Ok=1).
; Diagnostics holds errors only; load-time warnings stay in Raw, which is
; NDJSON (one object per line), so the 'export Foo() {' case reads Ok=1
; unless the warning is pulled out with JSON.ParseAt.
FirstDiag(c) => c.Diagnostics.Length ? StrReplace(c.Diagnostics[1].Message, "`n", " ") : "(no diagnostics)"
FirstWarning(c) {
    pos := 1
    while (pos <= StrLen(c.Raw)) {
        d := JSON.ParseAt(c.Raw, &pos)
        if (d["kind"] = "diagnostic" && d["severity"] = "warning")
            return StrReplace(d["message"], "`n", " ") ' -- "' d["extra"] '"'
    }
    return "(no warnings)"
}

c := Check("#Module M`nexport Foo() {`n}")
Print("  Check('export Foo() {{}')      Ok={} -> warning: {}", c.Ok, FirstWarning(c))
c := Check("#Module M`nexport global X := 1")
Print("  Check('export global X := 1') Ok={} -> {}", c.Ok, FirstDiag(c))
c := Check("#Module M`nexport class K {`n}")
Print("  Check('export class K {{}')     Ok={} -> {}", c.Ok, FirstDiag(c))
Print("")

; ─────────────────────────────────────────────────────
; 3. Fix: output parameters "made blank" instead of unset
; ─────────────────────────────────────────────────────
Print("── 3. PixelSearch/ImageSearch X,Y are blank (not unset) on no match ──")

; Output parameters that a function does not explicitly write are now made
; blank ("") like they always were in v2.0. In alpha.30 they were left
; unset, so 'px' below did not exist after a failed search.
; Candidates tried: MouseGetPos Win/Control and CaretGetPos already blank
; their outputs explicitly (no change); PixelSearch and ImageSearch relied
; on the default and are the ones that changed.

px := "not touched"
try {
    actual := PixelGetColor(0, 0)
    wanted := actual = 0x123456 ? 0x654321 : 0x123456     ; guaranteed miss
    found := PixelSearch(&px, &py, 0, 0, 0, 0, wanted)    ; 1x1 area at (0,0)
    Print("  PixelSearch found={}  IsSet(px)={}  px='{}'", found, IsSet(px), px ?? "<unset>")
} catch as e
    Print("  PixelSearch unavailable here: {}", e.Message)
ix := "not touched"
try {
    ; a 16x16 icon can never fit a 1x1 region, so this is a guaranteed miss
    found := ImageSearch(&ix, &iy, 0, 0, 0, 0, "*Icon1 " A_WinDir "\System32\shell32.dll")
    Print("  ImageSearch found={}  IsSet(ix)={}  ix='{}'", found, IsSet(ix), ix ?? "<unset>")
} catch as e
    Print("  ImageSearch unavailable here: {}", e.Message)
Print("  (alpha.30: IsSet(px)=0 and IsSet(ix)=0, both <unset>)")
Print("")

; ─────────────────────────────────────────────────────
; 4. Fix: RegExMatch &m still unset on no match (v2.1 mode)
; ─────────────────────────────────────────────────────
Print("── 4. RegExMatch leaves &m unset when nothing matches ──")

; The "made blank" fix (section 3) briefly turned RegExMatch's Match output
; into "" as well; the release restores unset for v2.1 scripts. Same result
; as alpha.30 -- shown because the release notes call it out.

pos := RegExMatch("abc", "z", &m)
Print("  RegExMatch('abc', 'z', &m) = {}  IsSet(m) = {}", pos, IsSet(m))
Print("")

; ─────────────────────────────────────────────────────
; 5. Fix: Props(v) retains the value of v
; ─────────────────────────────────────────────────────
Print("── 5. Props(v) snapshots v instead of aliasing the variable ──")

; The enumerator used to keep a reference to the *variable*, so reassigning
; v before iterating changed the 'this' seen by property getters. Needs a
; property on a primitive to observe: String.Prototype has no DefineProp
; of its own, so borrow Object.Prototype's and pass the prototype as this.

Object.Prototype.DefineProp.Call(String.Prototype, "Tagged", {get: (this) => "tag:" this})

v := "first"
e := Props(v)
v := "second"
for name, val in e
    Print("  {} = {}   (alpha.30 printed tag:second)", name, val)
Print("")

; ─────────────────────────────────────────────────────
; 6. Fix: multi-level import keeps unset as unset
; ─────────────────────────────────────────────────────
Print("── 6. Unset survives a two-level import chain ──")

; Leaf.Later is unset; Middle re-imports it as Later2; __Main imports
; Later2 from Middle. Reading through the two-level alias used to yield ""
; (IsSet was already right; the read itself was wrong).

Print("  Marker2 = '{}'  (Leaf executed)", Marker2)
Print("  IsSet(Later2) = {}", IsSet(Later2))
Print("  Later2 ?? '<unset>' = '{}'   (alpha.30: '')", Later2 ?? "<unset>")
Print("")

; ─────────────────────────────────────────────────────
; 7. Fix: trailing character in the unset-return error
; ─────────────────────────────────────────────────────
Print("── 7. 'No value was returned' Extra no longer swallows a character ──")

; When a dynamic member name is followed by literal characters, the error
; marker started one character too early. Compare the Extra text.

NoValue() {
}
try
    r := NoValue.%'C'%all()
catch as e
    Print("  NoValue.%'C'%all()  -> Message='{}' Extra='{}'   (alpha.30 Extra: 'l()')", e.Message, e.Extra)
try
    r := NoValue.%'Call'%()
catch as e
    Print("  NoValue.%'Call'%()  -> Extra='{}'   (unchanged, intended)", e.Extra)
Print("")

; ─────────────────────────────────────────────────────
; 8. Fix: destructing a boxed pointer to a struct array
; ─────────────────────────────────────────────────────
Print("── 8. Boxed pointer to a struct array destructs cleanly ──")

; 'Outer[2].Ptr()' is an 8-byte pointer box; '.__Value' boxes the target as
; an Outer[2] view whose items are constructed lazily. Releasing that view
; used to destruct the never-constructed items -> "Invalid memory
; read/write" (exit 11) in alpha.30. Any struct item type triggers it; the
; nested Inner just matches the release note.

Struct Inner {
    a: Int32
}
Struct Outer {
    i: Inner
}
arr := Outer[2]()
arr[2].i.a := 9
pa := Outer[2].Ptr()
NumPut("ptr", arr.Ptr, pa.Ptr)              ; aim the box at arr
view := pa.__Value
Print("  Type(view) = {}  view[2].i.a = {}", Type(view), view[2].i.a)
view := ""
pa := ""
Print("  released view and box -> no crash")
Print("")

; ─────────────────────────────────────────────────────
; 9. Fix: simple a := b where b is a virtual reference
; ─────────────────────────────────────────────────────
Print("── 9. 'a := p' with p bound to an object that has __Value ──")

; Passing an object with a __Value property where a ByRef (&p) parameter
; is expected binds p as a *virtual reference*: reads call __Value.get,
; writes call __Value.set. The load-time fast path for 'a := p' still saw
; the parameter as uninitialised and threw
; "This parameter has not been assigned a value." in alpha.30.

class Boxed {
    __Value {
        get => "via __Value"
        set => (this.stored := value)
    }
}
CopyParam(&p) {
    a := p                  ; the simple-assignment fast path
    return a
}
ConcatParam(&p) {
    return p . ""           ; the expression path
}
try {
    a := CopyParam(Boxed())
    Print("  a := p       -> Type(a) = {}   (alpha.30: threw)", Type(a))
} catch as e
    Print("  a := p       -> threw: {}", e.Message)
Print("  a := p . ''  -> '{}'", ConcatParam(Boxed()))
; Observation: the fast path copies the bound object itself rather than
; calling __Value.get, so Type(a) is 'Boxed', not 'String'. Use the
; expression form when you want the dereferenced value.
Print("")

; ─────────────────────────────────────────────────────
; 10/11. v2.0-line class fixes, shown with the fork-only Check() BIF
; ─────────────────────────────────────────────────────
Print("── 10/11. Class declarations via Check() ──")

c := Check("class K extends K {`n}")
Print("  class K extends K            -> Ok={} ({})", c.Ok, FirstDiag(c))
c := Check("class A extends B {`n}`nclass B extends A {`n}")
Print("  class A extends B / B extends A -> Ok={} ({})", c.Ok, FirstDiag(c))
c := Check("class C {`n    prop {`n        get => 42`n    }`n    prop {`n        set => 0`n    }`n}")
Print("  setter block after getter block -> Ok={}   (alpha.30: Ok=0, Duplicate declaration)", c.Ok)
Print("")

; ─────────────────────────────────────────────────────
; Summary
; ─────────────────────────────────────────────────────
Print("═══════════════════════════════════════════════")
Print("alpha.31 finishes the module story and fixes a round of alpha bugs:")
Print("  • Changed: export is implied inside #Module; 'export' keyword removed")
Print("  • Unchanged: imports stay private unless '#Import Export' (note only clarifies)")
Print("  • Fixed: output params made blank, RegExMatch unset, Props(v) copy,")
Print("           multi-level unset, unset-return Extra, boxed-pointer crash,")
Print("           a := virtual-ref")
Print("  • v2.0 merge: self-subclass rejected, setter-after-getter allowed")
Print("═══════════════════════════════════════════════")
