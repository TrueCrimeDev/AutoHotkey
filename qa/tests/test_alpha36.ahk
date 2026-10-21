#Requires AutoHotkey v2.1-alpha.36
; test_alpha36.ahk -- pins behaviour from the upstream v2.1-alpha.36 merge
; (2026-10-21) and the fork's fix to ObjCreateWithDataPtr on that engine. Every
; fact below was verified against 2.1-alpha.36+Console; the "OLD:" note on a
; section records what 2.1-alpha.35+Console (56f57edb) or the official upstream
; AutoHotkey_2.1-alpha.36.zip did, so an assert that only passes here is
; genuinely pinning the change.
;
; Load-time behaviour (#Import, AhkLibPath) and anything that could take the
; process down (the data-pointer case) run in a child process via RunSnippet.
#Include ..\Assert.ahk
#Include ..\Harness.ahk

; 1. ObjCreateWithDataPtr (7aa2e0ea) on struct classes: the object is a view of
;    the memory at Address, like StructClass.At, but Address 0 is accepted and
;    an address below 65536 is not.
; OLD (alpha.35): ObjCreateWithDataPtr did not exist.
buf := Buffer(16, 0)
NumPut("Int", 42, buf)
v := ObjCreateWithDataPtr(Int32, buf.Ptr)
Assert.eq(Type(v), "Int32", "ObjCreateWithDataPtr(Int32): type")
Assert.eq(v.__Value, 42, "ObjCreateWithDataPtr(Int32): reads the buffer")
v.__Value := 7
Assert.eq(NumGet(buf, "Int"), 7, "ObjCreateWithDataPtr(Int32): writes the buffer")
struct QaPt36 {
    x : Int32
    y : Int32
}
NumPut("Int", 3, "Int", 4, buf)
pt := ObjCreateWithDataPtr(QaPt36, buf.Ptr)
Assert.eq(pt.x " " pt.y, "3 4", "ObjCreateWithDataPtr(struct): reads the fields")
pt.y := 9
Assert.eq(NumGet(buf, 4, "Int"), 9, "ObjCreateWithDataPtr(struct): writes a field")
Assert.eq(Type(ObjCreateWithDataPtr(QaPt36, 0)), "QaPt36", "ObjCreateWithDataPtr(struct, 0) is accepted")
Assert.throws(() => QaPt36.At(0), "StructClass.At(0) still throws", "Parameter #1 of Struct.At is invalid")
Assert.throws(() => ObjCreateWithDataPtr(QaPt36, 100), "ObjCreateWithDataPtr(struct, 100) throws", "Parameter #2 of ObjCreateWithDataPtr is invalid")
Assert.throws(() => ObjCreateWithDataPtr(42, 0), "ObjCreateWithDataPtr(non-class) throws", "Invalid class")
Assert.throws(() => ObjCreateWithDataPtr(RegExMatchInfo, 0), "ObjCreateWithDataPtr(RegExMatchInfo) throws", "Invalid class")

; 2. ObjCreateWithDataPtr on an ordinary class skips __Init and __New (instance
;    variable initializers do not run) but calls __Delete on release, unlike
;    StructClass.At. Typed properties read the memory at Address.
class QaView36 {
    static log := ""
    iv := "set"
    v : Int32
    __New() => QaView36.log .= "new,"
    __Delete() => QaView36.log .= "delete,"
}
NumPut("Int", 55, buf)
o := ObjCreateWithDataPtr(QaView36, buf.Ptr)
Assert.eq(o.v, 55, "ObjCreateWithDataPtr(class): typed property reads Address")
Assert.falsy(o.HasOwnProp("iv"), "ObjCreateWithDataPtr(class): instance initializer did not run")
Assert.eq(ObjGetDataPtr(o), buf.Ptr, "ObjCreateWithDataPtr(class): ObjGetDataPtr returns Address")
o := ""
Assert.eq(QaView36.log, "delete,", "ObjCreateWithDataPtr(class): __New skipped, __Delete called")

; 3. Fork fix: ObjCreateWithDataPtr on a native class larger than Object
;    (Map, Array, Buffer, ProcessPipe, JSON.Object). Object::CreateStructPtr
;    stored the pointer at sizeof(Object) while ObjGetDataPtr, ObjSetDataPtr and
;    typed properties read it at the class's object_size.
; OLD (official alpha.36): ObjGetDataPtr returned unrelated memory (garbage for
;      Address 0), the pointer overwrote the Map's own fields, and releasing it
;      ended the process with exit code 127.
r := RunSnippet(
    "buf := Buffer(16, 0)`n"
    . "for cls in [Map, Array, Buffer, ProcessPipe, JSON] {`n"
    . "    o := ObjCreateWithDataPtr(cls, buf.Ptr)`n"
    . "    a := ObjGetDataPtr(o) = buf.Ptr`n"
    . "    ObjSetDataPtr(o, buf.Ptr + 8)`n"
    . "    Print(`"{} {} {}`", Type(o), a, ObjGetDataPtr(o) = buf.Ptr + 8)`n"
    . "    o := `"`"`n"
    . "}`n"
    . "z := ObjCreateWithDataPtr(Map, 0)`n"
    . "Print(`"zero {}`", ObjGetDataPtr(z))`n"
    . "m := ObjCreateWithDataPtr(Map, buf.Ptr)`n"
    . "m[`"k`"] := 1, m[2] := `"v`"`n"
    . "Print(`"map {} {} {}`", m.Count, m[`"k`"], m[2])`n"
    . "class MM36 extends Map {`n    x : Int32`n}`n"
    . "NumPut(`"Int`", 77, buf)`n"
    . "t := ObjCreateWithDataPtr(MM36, buf.Ptr)`n"
    . "t[`"z`"] := 5, x := t.x, t.x := 78`n"
    . "Print(`"typed {} {} {}`", x, t.Count, NumGet(buf, `"Int`"))`n"
    . "m := `"`", t := `"`", z := `"`"`n"
    . "Print(`"released`")`n")
Assert.eq(r.code, 0, "native-class data pointer: child exits 0")
Assert.eq(r.out, "Map 1 1`nArray 1 1`nBuffer 1 1`nProcessPipe 1 1`nJSON.Object 1 1`n"
    . "zero 0`nmap 2 1 v`ntyped 77 1 78`nreleased`n",
    "native-class data pointer: ObjGetDataPtr/ObjSetDataPtr round-trip, the Map works, a typed property on a Map subclass reads and writes Address")

; 4. Invalid constructor calls (65189b9c): a native class prototype without a
;    factory of its own no longer inherits Object's, so calling the class
;    directly or through Object.Call throws instead of building a plain Object
;    on the native prototype.
; OLD (alpha.35): each call returned an object that reported the class as its
;      Type; a native method on it would read past its end.
oc := Object.Call
for cls in [RegExMatchInfo, File, Func, BoundFunc, Closure, Enumerator] {
    name := cls.Prototype.__Class
    Assert.throws(((c) => c()).Bind(cls), name "() throws", "Invalid base")
    Assert.throws(((c) => oc(c)).Bind(cls), "(Object.Call)(" name ") throws", "Invalid base")
}
; The fork's classes keep their own behaviour.
Assert.throws(() => JSON(), "JSON() keeps the fork's TypeError", "JSON cannot be constructed")
Assert.throws(() => oc(JSON), "(Object.Call)(JSON) still throws", "Invalid base")
Assert.eq(Type(SyntaxError("x")), "SyntaxError", "SyntaxError() still constructs")
Assert.eq(Type(JSONError("x")), "JSONError", "JSONError() still constructs")
Assert.eq(Type(oc(Error)), "Error", "(Object.Call)(Error) still constructs")
class QaMap36 extends Map {
}
Assert.eq(Type(QaMap36()), "QaMap36", "a script subclass of Map still constructs")

; 5. #Import inside a function raises a load error when a non-static local, a
;    parameter or an alias target of the same name exists (0b8e6fa3), whether
;    the local is declared before or after the #Import.
; OLD (alpha.35): the local or parameter silently shadowed the import, so F()
;      returned 5.
mod := "`n#Module M`nX := 1`n"
r := RunSnippet("F() {`n    #Import M {X}`n    return X`n}`nPrint(F())" mod)
Assert.eq(r.code " " r.out, "0 1`n", "#Import in a function with no conflict: imports X")
for name, src in Map(
    "local before", "F() {`n    local X := 5`n    #Import M {X}`n    return X`n}`nPrint(F())",
    "local after", "F() {`n    #Import M {X}`n    local X := 5`n    return X`n}`nPrint(F())",
    "alias target", "F() {`n    local Y := 5`n    #Import M {X as Y}`n    return Y`n}`nPrint(F())") {
    r := RunSnippet(src mod)
    Assert.eq(r.code, 12, "#Import conflicting " name ": load error, exit 12")
    Assert.truthy(InStr(r.out, "This import declaration conflicts with an existing local variable."),
        "#Import conflicting " name ": reports the conflict")
}
r := RunSnippet("F(X := 5) {`n    #Import M {X}`n    return X`n}`nPrint(F())" mod)
Assert.eq(r.code, 12, "#Import conflicting parameter: load error, exit 12")
Assert.truthy(InStr(r.out, "This import declaration conflicts with an existing parameter."),
    "#Import conflicting parameter: reports the conflict")

; 6. AhkLibPath keeps a directory listed after one that does not exist
;    (abe3ff20, the same fix the fork made in 57bb8dcc).
; OLD (official alpha.35): everything after the missing entry was dropped and
;      #Include <A> failed with "Script library not found."
libDir := A_Temp "\qa_lib36_" ProcessExist() "_" A_TickCount
DirCreate(libDir)
FileAppend("global QaLib36 := `"found`"`n", libDir "\A.ahk", "UTF-8")
EnvSet("AhkLibPath", libDir "\missing;" libDir)
try {
    r := RunSnippet("#Requires AutoHotkey v2.1-alpha.36`n#Include <A>`nPrint(QaLib36)")
    Assert.eq(r.code " " r.out, "0 found`n", "AhkLibPath: an entry after a missing directory is searched")
} finally {
    EnvSet("AhkLibPath", "")
    try DirDelete(libDir, true)
}

Assert.Summary()
