#Requires AutoHotkey v2.1-alpha.35
; test_alpha35.ahk -- pins behaviour from the upstream v2.1-alpha.34/.35 merge
; (2026-10-12) and the fork's Print built-in on that engine. Every fact below was
; verified against 2.1-alpha.35+Console; the "OLD:" note on a section records
; what 2.1-alpha.33+Console (f14d7427) did, so an assert that only passes here
; is genuinely pinning the change.
;
; This file's top-level #Requires puts it in v2.1 mode, which is where the Map
; and Array type checks apply. v2.0-mode behaviour is probed in a child process
; via RunSnippet, as is everything that happens at load time (#Include).
#Include ..\Assert.ahk
#Include ..\Harness.ahk

; 1. Map rejects Float keys in v2.1 mode (alpha.35). Strings and Integers are
;    unaffected.
; OLD: m[1.5] := "x" was accepted and stored under the Float key.
m := Map()
Assert.throws(() => m[1.5] := "x", "Map Float key: throws", "Expected an Integer but got a Float")
try
    m[1.5] := "x"
catch Error as e
    Assert.eq(Type(e), "TypeError", "Map Float key: TypeError")
m["1.5"] := "s", m[2] := "i"
Assert.eq(m["1.5"] . m[2], "si", "Map String and Integer keys still work")
Assert.eq(m.Count, 2, "Map Float key: nothing was stored")

; 2. Array rejects bad index types in v2.1 mode (alpha.35): a Float index and
;    an empty string throw TypeError. A numeric string still converts.
; OLD: arr[1.0] returned arr[1]; arr[""] threw IndexError.
arr := [10, 20, 30]
Assert.throws(() => arr[1.0], "Array Float index: throws", "Invalid index")
try
    arr[1.0]
catch Error as e
    Assert.eq(Type(e), "TypeError", "Array Float index: TypeError")
try
    arr[""]
catch Error as e
    Assert.eq(Type(e), "TypeError", "Array empty index: TypeError")
Assert.eq(arr["1"], 10, "Array numeric-string index still converts")
Assert.eq(arr[" 2"], 20, "Array numeric-string index with leading space still converts")

; 3. v2.0 mode keeps the old behaviour (child process, no v2.1 #Requires).
r := RunSnippet("#Requires AutoHotkey v2.0`nm := Map(), m[1.5] := `"f`"`n"
    . "arr := [10, 20]`nPrint(`"{} {}`", m[1.5], arr[1.0])")
Assert.eq(r.code, 0, "v2.0 mode: Float Map key and Float Array index: exit 0")
Assert.eq(r.out, "f 10`n", "v2.0 mode: Float Map key and Float Array index accepted")

; 4. DefineProp's Enumerable: false (alpha.34) hides the property from Props()
;    but not from OwnProps(), HasOwnProp or ObjOwnPropCount; it reads normally.
; OLD: Enumerable was rejected as an unknown descriptor key (ValueError
;      "Parameter #2 of Object.Prototype.DefineProp is invalid.").
o := {}
o.DefineProp("shown", {Value: 1})
o.DefineProp("hidden", {Value: 2, Enumerable: false})
props := "", own := ""
for name in o.Props()
    props .= name ","
for name in o.OwnProps()
    own .= name ","
Assert.eq(props, "shown,", "Enumerable false: Props() skips the property")
Assert.eq(own, "hidden,shown,", "Enumerable false: OwnProps() still lists it")
Assert.truthy(o.HasOwnProp("hidden"), "Enumerable false: HasOwnProp is true")
Assert.eq(ObjOwnPropCount(o), 2, "Enumerable false: ObjOwnPropCount counts it")
Assert.eq(o.hidden, 2, "Enumerable false: the value reads normally")
o.hidden := 3
Assert.eq(o.hidden, 3, "Enumerable false: the value writes normally")

; 5. DefineProp descriptor validation (alpha.34): an unknown key, and Value
;    combined with an accessor, throw ValueError.
Assert.throws(() => o.DefineProp("bad", {Bogus: 1}), "DefineProp unknown descriptor key: throws", "DefineProp")
Assert.throws(() => o.DefineProp("bad2", {Value: 1, Get: (*) => 2}), "DefineProp Value plus Get: throws", "DefineProp")
Assert.falsy(o.HasOwnProp("bad") || o.HasOwnProp("bad2"), "DefineProp rejected descriptors define nothing")

; 6. Library search (alpha.35): in v2.1 mode `#Include <A_B>` looks for A_B.ahk
;    only (no fallback to A.ahk); in v2.0 mode the fallback still applies. The
;    AhkLibPath environment variable replaces the default search list, so the
;    child finds the library in a directory that is not A_ScriptDir\Lib.
; OLD (v2.1 mode): `#Include <A_B>` fell back to A.ahk, like v2.0.
libDir := A_Temp "\qa_lib35_" ProcessExist() "_" A_TickCount
DirCreate(libDir)
FileAppend("global QaLib35 := `"A.ahk`"`n", libDir "\A.ahk", "UTF-8")
EnvSet("AhkLibPath", libDir)
try {
    r := RunSnippet("#Requires AutoHotkey v2.1-alpha.35`n#Include <A>`nPrint(QaLib35)")
    Assert.eq(r.code, 0, "AhkLibPath: #Include <A> in v2.1 mode: exit 0")
    Assert.eq(r.out, "A.ahk`n", "AhkLibPath: #Include <A> loads A.ahk from the override directory")

    r := RunSnippet("#Requires AutoHotkey v2.0`n#Include <A_B>`nPrint(QaLib35)")
    Assert.eq(r.code, 0, "v2.0 mode: #Include <A_B> falls back to A.ahk: exit 0")
    Assert.eq(r.out, "A.ahk`n", "v2.0 mode: #Include <A_B> falls back to A.ahk")

    r := RunSnippet("#Requires AutoHotkey v2.1-alpha.35`n#Include <A_B>`nPrint(QaLib35)")
    Assert.truthy(r.code != 0, "v2.1 mode: #Include <A_B> without A_B.ahk fails to load")
    Assert.truthy(InStr(r.out, "Script library not found"), "v2.1 mode: #Include <A_B> reports 'Script library not found'")
    Assert.falsy(InStr(r.out, "A.ahk`n"), "v2.1 mode: #Include <A_B> did not load A.ahk")
} finally {
    EnvSet("AhkLibPath", "")
    try DirDelete(libDir, true)
}

; 7. Print (fork built-in) on this engine: no-arg form, single-arg verbatim
;    (braces are not Format placeholders), and the Format form.
r := RunSnippet("Print()`nPrint(`"{ok: true}`")`nPrint(`"0x{:08X} = {1}`", 0xD05)`nPrint(A_AhkVersion)")
Assert.eq(r.code, 0, "Print: exit 0")
Assert.eq(r.out, "`n{ok: true}`n0x00000D05 = 3333`n2.1-alpha.35+Console`n", "Print: blank line, verbatim single arg, Format form, version")

Assert.Summary()
