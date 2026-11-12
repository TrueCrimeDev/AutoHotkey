#Requires AutoHotkey v2.1-alpha.38
; test_alpha38.ahk -- pins behaviour from the upstream v2.1-alpha.38 merge
; (2026-11-12, tag v2.1-alpha.38 = afde2333, released 2026-11-07). Every fact
; below was verified against 2.1-alpha.38+Console (c47c4c8b); the "OLD:" note
; on a section records what 2.1-alpha.37+Console (a911f73d) did, so an assert
; that only passes here is genuinely pinning the change.
;
; Anything that took the old engine down (ObjCreateWithDataPtr on a Buffer),
; failed at class initialization (the mutually referencing structs) or needs
; module directives runs in a child process via RunSnippet.
#Include ..\Assert.ahk
#Include ..\Harness.ahk

Lines(parts*) {
    out := ""
    for p in parts
        out .= p "`n"
    return out
}

; 1. ObjCreateWithDataPtr and StructClass.At accept an object with a Ptr
;    property, such as a Buffer, and keep it alive (802c49c9).
; OLD (alpha.37): QaPt38.At(buf) threw "Parameter #1 of Struct.At is invalid."
;      and ObjCreateWithDataPtr(QaPt38, buf) took the object as the address
;      and exited 11 "Invalid memory read/write." on the first field read.
struct QaPt38 {
    x : Int32
    y : Int32
}
buf := Buffer(8, 0)
NumPut("Int", 5, "Int", 6, buf)
v := QaPt38.At(buf)
Assert.eq(v.x " " v.y, "5 6", "StructClass.At(Buffer) reads the buffer")
Assert.eq(v.Ptr, buf.Ptr, "StructClass.At(Buffer) views the buffer's Ptr")
Assert.eq(QaPt38.At({Ptr: buf.Ptr}).y, 6, "StructClass.At accepts any object with a Ptr property")
Assert.throws(() => QaPt38.At({}), "StructClass.At(object without Ptr) throws", "no property named " '"Ptr"')
QaViewOfLocal38() {
    local b := Buffer(8, 0)
    NumPut("Int", 42, b)
    return QaPt38.At(b)
}
Assert.eq(QaViewOfLocal38().x, 42, "StructClass.At keeps the Buffer alive after its last variable is gone")
r := RunSnippet(Lines(
    "struct P {",
    "    x : Int32",
    "    y : Int32",
    "}",
    "b := Buffer(8, 0)",
    "NumPut('Int', 7, 'Int', 8, b)",
    "w := ObjCreateWithDataPtr(P, b)",
    "Print(w.x ' ' w.y)"))
Assert.eq(r.code " " r.out, "0 7 8`n", "ObjCreateWithDataPtr(struct, Buffer) reads the buffer")

; 2. StructClass.At permits addresses below 65536, as ObjCreateWithDataPtr
;    already did for 0 (2042a5e7). The view is not dereferenced until a field
;    is read.
; OLD (alpha.37): At(0) and At(100) threw "Parameter #1 of Struct.At is
;      invalid."; ObjCreateWithDataPtr(QaPt38, 100) threw "Parameter #2 of
;      ObjCreateWithDataPtr is invalid."
Assert.eq(QaPt38.At(0).Ptr, 0, "StructClass.At(0) is accepted")
Assert.eq(QaPt38.At(100).Ptr, 100, "StructClass.At(100) is accepted")
Assert.eq(UInt16.At(32516).Ptr, 32516, "UInt16.At(32516) (IDI_INFORMATION) is accepted")
Assert.eq(Type(ObjCreateWithDataPtr(QaPt38, 100)), "QaPt38", "ObjCreateWithDataPtr(struct, 100) is accepted")

; 3. ObjGetDataPtr returns unset instead of throwing when the object has no
;    data pointer (d7353438). A non-object still throws TypeError.
; OLD (alpha.37): Error "Failed" for {}, [], Map() and a Prototype.
p := QaPt38()
Assert.eq(ObjGetDataPtr(p), p.Ptr, "ObjGetDataPtr(struct) is its Ptr")
Assert.falsy(IsSet(ObjGetDataPtr({})), "ObjGetDataPtr({}) returns unset")
Assert.falsy(IsSet(ObjGetDataPtr([])), "ObjGetDataPtr([]) returns unset")
Assert.falsy(IsSet(ObjGetDataPtr(Map())), "ObjGetDataPtr(Map()) returns unset")
Assert.eq(ObjGetDataPtr({}) ?? "none", "none", "ObjGetDataPtr({}) ?? default")
Assert.throws(() => ObjGetDataPtr(5), "ObjGetDataPtr(non-object) still throws", "requires an Object")

; 4. Open structures (ad5cfae6, afde2333): a structure stays open, its offsets
;    and size not yet calculated, until an instance, a containing or derived
;    structure, ObjGetDataSize or a DllCall/CallbackCreate type needs them.
;    Two structs can now reference each other in either order.
; OLD (alpha.37): initializing S1 initialized S2, whose P2 : S1 needed S1's
;      unfinished size: "Parameter #3 invalid." at class init (exit 10).
s2size := A_PtrSize = 8 ? 16 : 8
for order in [["S1", "S2"], ["S2", "S1"]] {
    defs := Map(
        "S1", "struct S1 {`n    P1 : S2.Ptr`n}",
        "S2", "struct S2 {`n    P2 : S1`n    P3 : Int32`n}")
    r := RunSnippet(Lines(
        defs[order[1]],
        defs[order[2]],
        "s := S2()",
        "s.P3 := 7",
        "Print(ObjGetDataSize(S1.Prototype) ' ' ObjGetDataSize(S2.Prototype) ' ' s.P3 ' ' Object.Prototype.GetOwnPropDesc.Call(S2.Prototype, 'P3').Offset)"))
    Assert.eq(r.code " " r.out, "0 " A_PtrSize " " s2size " 7 " A_PtrSize "`n"
        , "mutually referencing structs, " order[1] " defined first: sizes, field and offset")
}
; ObjGetDataSize on a Prototype closes the structure and includes the trailing
; padding. OLD (alpha.37): 5 before any instance existed, 8 after.
struct QaPad38 {
    a : Int32
    b : Int8
}
Assert.eq(ObjGetDataSize(QaPad38.Prototype), 8, "ObjGetDataSize(Prototype) before any instance includes the padding")
Assert.eq(QaPad38().Size, 8, "the instance size agrees")
; A closed structure takes no new typed properties.
; OLD (alpha.37): DefineProp after ObjGetDataSize was accepted silently.
QaClosed38 := Class(Struct)
DefineProp(QaClosed38.Prototype, "a", {Type: Int8})
ObjGetDataSize(QaClosed38.Prototype)
Assert.throws(() => DefineProp(QaClosed38.Prototype, "b", {Type: Int8}), "DefineProp on a closed structure throws", "Cannot add typed property.")

; 5. GetOwnPropDesc for typed properties (ad5cfae6): Pack appears when a
;    non-zero value was defined; while the structure is open, Offset appears
;    only if one was requested, as requested (a property name stays a name).
;    DefineProp rejects a Pack other than 0, 1, 2, 4 or 8.
; OLD (alpha.37): Offset was always calculated at once (0, 1, 0 below), Pack
;      was never reported, and Pack: 3 was accepted.
QaDesc38 := Class(Struct)
DefineProp(QaDesc38.Prototype, "a", {Type: Int8})
DefineProp(QaDesc38.Prototype, "b", {Type: Int32, Pack: 1})
DefineProp(QaDesc38.Prototype, "c", {Type: Int16, Offset: "a"})
Desc38(name) {
    d := Object.Prototype.GetOwnPropDesc.Call(QaDesc38.Prototype, name)
    return (d.HasOwnProp("Offset") ? d.Offset : "-") " " (d.HasOwnProp("Pack") ? d.Pack : "-")
}
Assert.eq(Desc38("a") "|" Desc38("b") "|" Desc38("c"), "- -|- 1|a -", "GetOwnPropDesc while open: Offset only as requested, Pack when set")
Assert.eq(ObjGetDataSize(QaDesc38.Prototype), 6, "closing the structure: a@0, b@1 (Pack 1), c@0, aligned to 2")
Assert.eq(Desc38("a") "|" Desc38("b") "|" Desc38("c"), "0 -|1 1|0 -", "GetOwnPropDesc once closed: calculated offsets")
QaPack38 := Class(Struct)
Assert.throws(() => DefineProp(QaPack38.Prototype, "x", {Type: Int8, Pack: 3}), "DefineProp Pack: 3 throws", "Parameter #3 invalid.")

; 6. A user-defined Ptr subclass is constructed, so its __Value runs when a
;    field of that type is read (8b47614d). Subclassing Ptr requires
;    Class(X.Ptr) for now.
; OLD (alpha.37): the field read returned the pointed-to QaPt38 instance.
QaMyPtr38 := Class(QaPt38.Ptr)
DefineProp(QaMyPtr38.Prototype, "__Value", {Get: (this) => "custom"})
QaHolder38 := Class(Struct)
DefineProp(QaHolder38.Prototype, "p", {Type: QaMyPtr38})
h := QaHolder38()
h.p := QaPt38()
Assert.eq(h.p, "custom", "a field of a Ptr subclass type reads through the subclass __Value")
Assert.truthy(QaMyPtr38() is QaPt38.Ptr, "a Ptr subclass instance is a QaPt38.Ptr")

; 7. Modules (9ff3606b, c4d4137f, 41c751bc). Modules run at startup in
;    reverse order of creation, so MB's body runs before MA's and its first
;    reference to MA runs MA early.
; OLD (alpha.37): v := X in MB threw "This global variable has not been
;      assigned a value." (exit 10); MA run from g() saw A_ThisFunc "g"; Z in
;      f() resolved to MB's Z when the global #Import followed f().
r := RunSnippet(Lines(
    "#Module MA",
    "global X := 'A'",
    "#Module MB",
    "#Import MA {X}",
    "v := X",
    "Print('v=' v)",
    "#Module __Main"))
Assert.eq(r.code " " r.out, "0 v=A`n", "v := imported runs the imported module first")
r := RunSnippet(Lines(
    "#Module MA",
    "Print('MA in [' A_ThisFunc ']')",
    "global X := 'A'",
    "#Module MB",
    "#Import MA {X}",
    "g() => X",
    "g()",
    "#Module __Main"))
Assert.eq(r.code " " r.out, "0 MA in []`n", "a module run from inside a function does not run in that function's context")
wildcard := ["#Module MA", "global Z := 'A'", "#Module MB", "global Z := 'B'", "#Module __Main"]
r := RunSnippet(Lines(wildcard*) Lines(
    "f() {",
    "    #Import MA {*}",
    "    return Z",
    "}",
    "#Import MB {*}",
    "Print(f())"))
Assert.eq(r.code " " r.out, "0 A`n", "a function's wildcard import wins over a later global one")
r := RunSnippet(Lines(wildcard*) Lines(
    "f() {",
    "    g() {",
    "        return Z",
    "    }",
    "    #Import MA {*}",
    "    return g()",
    "}",
    "#Import MB {*}",
    "Print(f())"))
Assert.eq(r.code " " r.out, "0 A`n", "a nested function sees the outer function's wildcard import before the global one")
r := RunSnippet(Lines(wildcard*) Lines(
    "#Import MB {*}",
    "f() {",
    "    #Import MA {*}",
    "    return Z",
    "}",
    "Print(f())"))
Assert.eq(r.code " " r.out, "0 A`n", "a function's wildcard import still wins over an earlier global one")

; 8. Upstream's own fixes for two regressions the fork had fixed in a911f73d
;    (test_alpha37.ahk section 9): a.b() with a getter that throws reports
;    that error once (1e55d515), and CallbackCreate accepts a struct class
;    whose fields are all inherited (51547074).
r := RunSnippet(Lines(
    "class C {",
    "    b {",
    "        get {",
    "            throw ValueError('original')",
    "        }",
    "    }",
    "}",
    "C().b()"))
Assert.eq(r.code, 10, "a.b() with a throwing getter: uncaught error exit")
Assert.truthy(InStr(r.out, "original") && !InStr(r.out, "No value was returned"), "a.b() with a throwing getter reports only the getter's error")
struct QaBase38 {
    x : Int32
    y : Int32
}
struct QaDerived38 extends QaBase38 {
}
cb := CallbackCreate((s) => s.x * 10 + s.y, , [QaDerived38, Int32])
d := QaDerived38(4, 2)
Assert.eq(DllCall(cb, QaDerived38, d, Int32), 42, "a struct with only inherited fields passes by value through a callback")
CallbackFree(cb)

; 9. Fork fixes to alpha.38 regressions found by Copilot on fork PR #35, each
;    reproduced on the unfixed merge build (c47c4c8b) and compared with
;    alpha.37 (a911f73d) first; the report is
;    docs/upstream/alpha38-regressions.md. The import fix is upstream's own
;    post-tag c727bdf0, cherry-picked.
; OLD (c47c4c8b): a nested function inside an import-free function did not see
;      a global wildcard import (41c751bc); a struct containing itself by
;      value, directly, mutually, through an array or through its base, was
;      accepted and corrupted the heap when constructed (exit 127/139;
;      alpha.37 rejected it in DefineProp); {Type: ComValue(3, 0)} exited 11
;      (alpha.37: ValueError); a Class(Int32) field dropped its class, so its
;      __Value never ran (alpha.37 read through it); GetOwnPropDesc lost an
;      Offset naming a field that sorts after the one being described.
;      From Copilot's second review: a module's wildcard re-export was looked
;      up with the calling function's imports, and a struct derived from an
;      invalid one kept a nonzero size (b2885254 made Bad invalid but
;      Derived still sized 4, so CallbackCreate accepted it). From the third:
;      an array class accepted typed fields while its layout was pending.
;      From the fifth: NumGet accepted a Class(Int32) subclass until closed.
r := RunSnippet(Lines(wildcard*) Lines(
    "#Import MB {*}",
    "f() {",
    "    g() {",
    "        return Z",
    "    }",
    "    return g()",
    "}",
    "Print(f())"))
Assert.eq(r.code " " r.out, "0 B`n", "a function nested in an import-free function sees the global wildcard import")
; A module's wildcard re-export (#Import Export C {*}) is resolved with that
; module's own imports, not the calling function's (41c751bc gave "D").
r := RunSnippet(Lines(
    "#Module C",
    "global X := 'C'",
    "#Module D",
    "global X := 'D'",
    "#Module B",
    "#Import Export C {*}",
    "#Module __Main",
    "f() {",
    "    #Import D {*}",
    "    #Import B {*}",
    "    return X",
    "}",
    "Print(f())"))
Assert.eq(r.code " " r.out, "0 C`n", "a wildcard re-export is looked up in the re-exporting module's own imports")
cycles := Map(
    "direct", "struct S {`n    a : Int32`n    x : S`n}",
    "mutual", "struct S {`n    b : B`n}`nstruct B {`n    a : S`n}",
    "array",  "struct S {`n    x : S[2]`n}",
    "base",   "struct T {`n    s : S`n}`nstruct S extends T {`n}",
    "dynamic", "S := Class(Struct)`nDefineProp(S.Prototype, 'a', {Type: Int32})`nDefineProp(S.Prototype, 'x', {Type: S})")
for shape, src in cycles {
    r := RunSnippet(Lines(src,
        "try S()",
        "catch Error as e",
        "    Print(Type(e) ': ' e.Message)",
        "try S.At(Buffer(64, 0))",
        "catch Error as e",
        "    Print(Type(e) ': ' e.Message)",
        "Print('size ' ObjGetDataSize(S.Prototype))"))
    Assert.eq(r.code " " r.out, "0 TypeError: Invalid struct.`nTypeError: Invalid struct.`nsize 0`n", "a struct that contains itself by value (" shape ") is an invalid struct")
}
; A struct derived from an invalid one is invalid with size 0, so DllCall and
; CallbackCreate (which test the size) reject it too.
r := RunSnippet(Lines(
    "struct Bad {",
    "    self : Bad",
    "}",
    "struct Derived extends Bad {",
    "    x : Int32",
    "}",
    "Print(ObjGetDataSize(Derived.Prototype))",
    "try CallbackCreate((s) => 0, , [Derived, 'Void'])",
    "catch Error as e",
    "    Print(Type(e))"))
Assert.eq(r.code " " r.out, "0 0`nValueError`n", "a struct with an invalid base has size 0 and is not a CallbackCreate type")
; An array class takes no typed fields of its own: its layout is its elements.
; afde2333 left it open until first use, so an extra Int32 made Int32[2] 12
; bytes and moved element 2 to offset 6 (alpha.37: "Cannot add typed
; property.", as now).
QaArr38 := Int32[2]
Assert.throws(() => DefineProp(QaArr38.Prototype, "extra", {Type: Int32}), "an array class refuses an extra typed field", "Cannot add typed property.")
arr := QaArr38()
arr[2] := 22
Assert.eq(arr.Size " " NumGet(arr.Ptr, 4, "Int"), "8 22", "Int32[2] keeps its 8-byte layout, element 2 at offset 4")
; NumGet/NumPut close the class first, as DllCall does, so a Class(Int32)
; subclass (a plain struct once closed) is rejected whether or not it has been
; used yet. c47c4c8b accepted it as Int32 until it was closed; alpha.37 until
; it was instantiated.
QaNumOpen38 := Class(Int32)
b4 := Buffer(4, 0)
Assert.throws(() => NumGet(b4, QaNumOpen38), "NumGet rejects an unused Class(Int32) subclass", "Invalid parameter(s).")
Assert.eq(NumGet(b4, Int32), 0, "NumGet still accepts Int32 itself")
struct QaNode38 {
    next  : QaNode38.Ptr
    value : Int32
}
n1 := QaNode38(), n2 := QaNode38()
n2.value := 7
n1.next := n2
Assert.eq(n1.next.value, 7, "a struct that points to itself through a Ptr field still works")
r := RunSnippet(Lines(
    "S := Class(Struct)",
    "try DefineProp(S.Prototype, 'x', {Type: ComValue(3, 0)})",
    "catch Error as e",
    "    Print(Type(e) ': ' e.Message)"))
Assert.eq(r.code " " r.out, "0 ValueError: Parameter #3 invalid.`n", "DefineProp with a COM wrapper as the field type throws")
; Child process: on c47c4c8b the field read returns unset (the class was
; dropped for its native type, which is Void for a subclass), and
; GetOwnPropDesc indexes sPrimitiveClass[-1].
r := RunSnippet(Lines(
    "N := Class(Int32)",
    "DefineProp(N.Prototype, '__Value', {Get: (this) => 'custom ' NumGet(this.Ptr, 'Int')})",
    "H := Class(Struct)",
    "DefineProp(H.Prototype, 'n', {Type: N})",
    "rec := H()",
    "NumPut('Int', 5, rec.Ptr)",
    "Print(rec.n ?? 'unset')",
    "Print(Object.Prototype.GetOwnPropDesc.Call(H.Prototype, 'n').Type = N)"))
Assert.eq(r.code " " r.out, "0 custom 5`n1`n", "a Class(Int32) field reads through the subclass __Value, and GetOwnPropDesc reports that class")
QaNumPlain38 := Class(Int32)
v := QaNumPlain38()
v.__Value := 5
Assert.eq(v.__Value " " v.Size, "5 4", "a Class(Int32) subclass instance still holds an Int32")
QaFwd38 := Class(Struct)
DefineProp(QaFwd38.Prototype, "m", {Type: Int32})
DefineProp(QaFwd38.Prototype, "a", {Type: Int16, Offset: "m"})
DefineProp(QaFwd38.Prototype, "z", {Type: Int16, Offset: "m"})
Assert.eq(Desc38Of(QaFwd38, "a") "|" Desc38Of(QaFwd38, "z"), "m|m", "GetOwnPropDesc keeps an Offset naming a field that sorts after or before it")
Desc38Of(cls, name) {
    d := Object.Prototype.GetOwnPropDesc.Call(cls.Prototype, name)
    return d.HasOwnProp("Offset") ? d.Offset : "-"
}

Assert.Summary()
