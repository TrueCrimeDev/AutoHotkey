#Requires AutoHotkey v2.1-alpha.37
; test_alpha37.ahk -- pins behaviour from the upstream v2.1-alpha.37 merge
; (2026-10-25, upstream/alpha 279247ee; the tag was announced but not yet
; pushed). Every fact below was verified against 2.1-alpha.37+Console
; (6460921b); the "OLD:" note on a section records what 2.1-alpha.36+Console
; (165d7384) did, so an assert that only passes here is genuinely pinning the
; change.
;
; Load-time behaviour (IsSet on a property) and anything that took the old
; engine down (a.b() with b => unset, DllCall(IntPtr, obj), the numeric struct
; DllCall argument) run in a child process via RunSnippet.
#Include ..\Assert.ahk
#Include ..\Harness.ahk

; 1. DllCall "Str" and pointer ("Int*", "P") parameters accept unset as a null
;    pointer (1fa8d1f1). _wcsdup(NULL) returns NULL; _wcsdup("") returns a
;    real allocation, so the distinction is observable.
; OLD (alpha.36): "Missing a required parameter." for both.
Assert.eq(DllCall("msvcrt\_wcsdup", "Str", unset, "Ptr"), 0, 'DllCall "Str" unset passes a null pointer')
Assert.eq(DllCall("msvcrt\_wcsdup", "Int*", unset, "Ptr"), 0, 'DllCall "Int*" unset passes a null pointer')
p := DllCall("msvcrt\_wcsdup", "Str", "", "Ptr")
Assert.truthy(p != 0, 'DllCall "Str" "" still passes a real pointer')
DllCall("msvcrt\free", "Ptr", p)
Assert.eq(DllCall("GetCurrentDirectoryW", "UInt", 0, "Str", unset, "UInt") > 0, 1, 'DllCall "Str" unset: GetCurrentDirectoryW(0, NULL) reports the size')

; 2. Struct.Prototype.__New(fieldValues*) (176a9d1d): the class call assigns
;    every field in declaration order and requires exactly one value per
;    field; no arguments still zero-initializes. A script __New may call
;    super.__New(...) to reuse it.
; OLD (alpha.36): Pt(3, 4) threw "Too many parameters passed to function."
;      and super.__New(x, y) threw MethodError.
struct QaPt37 {
    x : Int32
    y : Int32
}
pt := QaPt37(3, 4)
Assert.eq(pt.x " " pt.y, "3 4", "Struct.__New(fieldValues*) assigns the fields in order")
pt0 := QaPt37()
Assert.eq(pt0.x " " pt0.y, "0 0", "Struct.__New() still zero-initializes")
Assert.throws(() => QaPt37(3), "Struct.__New with too few values throws", "Invalid number of parameters.")
Assert.throws(() => QaPt37(1, 2, 3), "Struct.__New with too many values throws", "Invalid number of parameters.")
struct QaScaled37 {
    x : Int32
    y : Int32
    __New(x, y) {
        super.__New(x * 10, y * 10)
    }
}
s := QaScaled37(3, 4)
Assert.eq(s.x " " s.y, "30 40", "a script __New can delegate to super.__New(fieldValues*)")

; 3. IsSet(a.b) implies a final ? when none is written (42fb8260): a missing
;    property or a call that returns unset gives 0 instead of a load error.
;    Only the final access is optional: IsSet(o.x.y) with no o.x still throws
;    PropertyError at run time. IsSet(a.b?) keeps working.
; OLD (alpha.36): "IsSet requires a variable or unset expression." at load
;      time (exit 12) for IsSet(o.a) and IsSet(f()).
r := RunSnippet("o := {a: 1}`nPrint('{} {} {} {}', IsSet(o.a), IsSet(o.missing), IsSet(o.a?), IsSet(o.missing?))")
Assert.eq(r.code " " r.out, "0 1 0 1 0`n", "IsSet(o.prop) loads and reports presence, with or without ?")
r := RunSnippet("f() => unset`ng() => 1`nclass C {`n    m() => unset`n}`nPrint('{} {} {}', IsSet(f()), IsSet(g()), IsSet(C().m()))")
Assert.eq(r.code " " r.out, "0 0 1 0`n", "IsSet(call()) is 0 when the call returns unset")
r := RunSnippet("o := {a: {b: 2}}`nPrint(IsSet(o.a.b))`ntry IsSet(o.x.y)`ncatch PropertyError as e`n    Print('PropertyError')")
Assert.eq(r.code " " r.out, "0 1`nPropertyError`n", "IsSet(o.x.y): only the final access is optional")

; 4. Struct.At accepts Struct itself (d99ace41): the result is a zero-field
;    view with Ptr and Size, and the fork's f24c23d1 still makes it reject
;    own properties.
; OLD (alpha.36): Struct.At(ptr) threw "Invalid class".
buf := Buffer(8, 0)
sv := Struct.At(buf.Ptr)
Assert.eq(Type(sv), "Struct", "Struct.At(ptr) returns a Struct")
Assert.eq(sv.Ptr, buf.Ptr, "Struct.At(ptr): Ptr is the address")
Assert.eq(sv.Size, 0, "Struct.At(ptr): Size is 0")
Assert.throws(() => sv.foo := 1, "Struct.At(ptr) view rejects own properties (fork f24c23d1)", 'has no property named "foo"')

; 5. DllCall(..., Int32, n, ...) with a numeric struct instance passes n's
;    value, not its address (91ab8b82); the same for Int64. Run in a child:
;    the Int64 form corrupted memory on alpha.36.
; OLD (alpha.36): TypeError "Expected a Number but got an Int32." for Int32,
;      exit 11 "Invalid memory read/write." for Int64.
r := RunSnippet("n := Int32()`nn.__Value := -5`nPrint(DllCall('msvcrt\abs', Int32, n, 'Int'))`nf(n := Int32()) => DllCall('msvcrt\abs', Int32, n, 'Int')`nPrint(f())")
Assert.eq(r.code " " r.out, "0 5`n0`n", "DllCall(Int32, n) passes the Int32's value")
r := RunSnippet("n := Int64()`nn.__Value := -9`nPrint(DllCall('msvcrt\_abs64', Int64, n, 'Int64'))")
Assert.eq(r.code " " r.out, "0 9`n", "DllCall(Int64, n) passes the Int64's value")

; 6. a.b() throws UnsetError when the property getter returns unset
;    (2f4f3967), and a.b[c] throws when a.b is a method (77595540).
; OLD (alpha.36): a.b() exited 11 "Invalid memory read/write."; a.b[c]
;      returned without throwing.
r := RunSnippet("class C {`n    b => unset`n}`ntry C().b()`ncatch as e`n    Print('{}: {}', Type(e), e.Message)")
Assert.eq(r.code " " r.out, "0 UnsetError: No value was returned.`n", "a.b() with b => unset throws UnsetError")
class QaM37 {
    m() => 1
}
Assert.throws(() => QaM37().m[1], "a.b[c] with b a method throws", 'has no property named "__Item"')

; 7. NumGet/NumPut throw ValueError for a type that is not a numeric class or
;    type string: an empty string, a plain object, or a Struct class with
;    fields (2cdf79a6). Numeric classes still work.
; OLD (alpha.36): all three read or wrote memory as a pointer-sized integer.
Assert.throws(() => NumGet(Buffer(8), ""), 'NumGet(buf, "") throws', "Invalid parameter(s).")
Assert.throws(() => NumPut({}, 123, Buffer(8)), "NumPut({}, ...) throws", "Invalid parameter(s).")
Assert.throws(() => NumGet(Buffer(8), QaPt37), "NumGet(buf, StructClass) throws", "Invalid parameter(s).")
Assert.throws(() => NumPut(QaPt37, 1, Buffer(8)), "NumPut(StructClass, ...) throws", "Invalid parameter(s).")
b8 := Buffer(8, 0)
NumPut(Int32, 77, b8)
Assert.eq(NumGet(b8, Int32), 77, "NumGet/NumPut still accept numeric classes")

; 8. DllCall(..., IntPtr, obj, ...) with a plain object throws TypeError
;    instead of reading the object as memory (f74fd031). Child process.
; OLD (alpha.36): exit 11 "Invalid memory read/write."
r := RunSnippet("try DllCall('msvcrt\abs', IntPtr, {}, 'Int')`ncatch as e`n    Print('{}: {}', Type(e), e.Message)")
Assert.eq(r.code " " r.out, "0 TypeError: Expected a Number but got an Object.`n", "DllCall(IntPtr, {}) throws TypeError")

; 9. Fork fixes to alpha.37 regressions found by Copilot on fork PR #33, each
;    reproduced on the unfixed merge build (6460921b) first; the report is
;    docs/upstream/alpha37-regressions.md.
; OLD (6460921b, upstream 279247ee): NumPut("Int", 1, "Bogus", 2, buf) wrote 2
;      with the previous pair's 4-byte size (ConvertNumGetType no longer reset
;      num_size per pair); C().b() with a getter that throws replaced the
;      exception with UnsetError (CallProperty tested the token before the
;      result); CallbackCreate rejected a struct subclass with only inherited
;      fields until an instance existed (GetStructCallbackArgInfo required
;      StructInfoInitialized). On Win32 only: "Int64*", unset occupied eight
;      bytes ("Parameter list too large.") and "Double*", unset shifted the
;      following arguments, because the unset branch cleared passed_by_address
;      but kept the 64-bit type; an array callback parameter was counted at its
;      struct size instead of one pointer slot (from source).
b16 := Buffer(16, 0)
Assert.throws(() => NumPut("Int", 1, "Bogus", 2, b16), "NumPut rejects an invalid type in a later pair", "Invalid parameter(s).")
NumPut("Int", 1, "Short", 2, "UChar", 3, b16)
Assert.eq(NumGet(b16, 0, "Int") " " NumGet(b16, 4, "Short") " " NumGet(b16, 6, "UChar"), "1 2 3", "NumPut still writes every valid pair")
class QaThrows37 {
    b {
        get {
            throw ValueError("original")
        }
    }
}
Assert.throws(() => QaThrows37().b(), "a.b() keeps the getter's own exception", "original")
struct QaBase37 {
    x : Int32
}
struct QaDerived37 extends QaBase37 {
}
Assert.noThrow(() => CallbackCreate((s) => 0, , [QaDerived37, "Void"]), "CallbackCreate accepts a struct subclass with only inherited fields before any instance exists")
Assert.eq(DllCall("kernel32\lstrlenW", "Int64*", unset, "Int"), 0, 'DllCall "Int64*" unset passes one null pointer slot (Win32 regression)')
Assert.eq(DllCall("msvcrt\_wcsnicmp", "Double*", unset, "Str", "abc", "UPtr", 0, "Cdecl Int"), 0, 'DllCall "Double*" unset does not shift the following arguments (Win32 regression)')

Assert.Summary()
