/*
Alpha30_Example.ahk -- AutoHotkey v2.1-alpha post-2026-05-17 feature showcase

This file targets the alpha state at upstream commit 34b17011 (merged into
the fork on 2026-05-22). Upstream did not bump A_AhkVersion, so the
#Requires directive still names alpha.29; what changed is the underlying
binary. Run with the fork's bin\AutoHotkey64.exe rebuilt after the merge.

What's new since Alpha29_Example.ahk:

  Added:
    1. 'Void' return type for DllCall / ComCall / CallbackCreate

  Breaking (removed -- migration required):
    2. 'a?.()' and 'a?.[]' -- use '(a?)()' and '(a?)[]' instead
    3. Property type strings ('i32', 'u32', ...) -- use class references
       ('Int32', 'UInt32', ...)
    4. Typeless typed properties (size specifier without a class)

  Fixed:
    5. 'String(x)' no longer crashes when x.ToString() returns no value
    6. 'x?.%y%' is no longer flagged as a syntax error
    7. 'StrGet(x, 0)' returns a String, not a Number
    8. Virtual ref assignments permit 'unset'
    9. DllCall propagates errors thrown by an output-arg __Value eval
   10. Load-time catch for ambiguous '!a ?? b' and 'b + a ?? c'

Print() in this fork takes (Fmt, Values*) and dispatches to Format
internally for 2+ args, so `Print("x={}", x)` replaces the old
`Print(Format("x={}", x))` idiom. See updates.md for details.

Run: bin\AutoHotkey64.exe Alpha30_Example.ahk
*/
#Requires AutoHotkey v2.1-alpha.30

Print("=== AutoHotkey v2.1-alpha post-merge Feature Showcase ===")
Print("Version: {}", A_AhkVersion)
Print("")

; ─────────────────────────────────────────────────────
; 1. New: 'Void' return type for DllCall / ComCall / CallbackCreate
; ─────────────────────────────────────────────────────
Print("── 1. 'Void' return type ──")

; Mark a Windows API as returning nothing. The call still runs, but the
; expression yields blank-unset instead of fabricating a numeric return
; value. Useful for APIs whose return value is documented as ignored or
; nonexistent (e.g. MessageBeep's documented BOOL is uninteresting in
; many UI flows).

ran := false
try {
    DllCall("MessageBeep", "uint", 0, "Void")
    ran := true
}
Print("  DllCall('MessageBeep', ..., 'Void') ran cleanly? {}", ran)

; A CallbackCreate-style usage: a callback declared with a Void return
; type will not push a value onto the native stack. Sketching only:
;
;     cb := CallbackCreate(myFn, "Void")     ; native ABI: void return
;
Print("  (CallbackCreate / ComCall also accept 'Void' analogously)")
Print("")

; ─────────────────────────────────────────────────────
; 2. Migration: a?.() -> (a?)() ,  a?.[] -> (a?)[]
; ─────────────────────────────────────────────────────
Print("── 2. Migration: a?.() and a?.[] -> (a?)() and (a?)[] ──")

; Old: a?.() invoked a only if it was set. The form was ambiguous
; because the ?. token already means "maybe-property". Alpha drops
; the call/index variants; the replacement parenthesises the maybe
; operand so the call/index is unambiguous.

callable := () => 42
unsetCallable := unset

direct  := (callable?)()  ?? "<unset>"        ; invoked: 42
skipped := (unsetCallable?)() ?? "<unset>"    ; short-circuited: <unset>
Print("  (callable?)()       = {}", direct)
Print("  (unsetCallable?)()  = {}", skipped)

indexable := [10, 20, 30]
unsetIndexable := unset
hit  := (indexable?)[2]      ?? "<unset>"     ; 20
miss := (unsetIndexable?)[2] ?? "<unset>"     ; <unset>
Print("  (indexable?)[2]      = {}", hit)
Print("  (unsetIndexable?)[2] = {}", miss)
Print("")

; ─────────────────────────────────────────────────────
; 3. Migration: property type strings -> class references
; ─────────────────────────────────────────────────────
Print("── 3. Migration: Struct {x: i32} -> Struct {x: Int32} ──")

; Type strings ("i32", "u32", "f64", ...) were a shorthand for the
; corresponding native type. Alpha removes the shorthand; you now name
; the primitive class directly. Class names: Int8/16/32/64, UInt8/16/32,
; Float32/64, IntPtr. (Note: no UInt64 class is created -- use Int64
; for 64-bit values and treat the sign yourself if needed.)

Struct Point30 {
    x: Int32
    y: Int32
}

pts := Point30()
pts.x := 7
pts.y := 11
Print("  Point30()  size: {} bytes", pts.Size)
Print("  Point30(x:7, y:11) = ({}, {})", pts.x, pts.y)

; What happens with the old shorthand:
fail_msg := ""
try {
    Struct OldStyle {
        x: i32                                ; "i32" no longer exists
    }
} catch as e
    fail_msg := e.Message
Print("  Old 'x: i32' raises: {}", fail_msg ? fail_msg : "(unexpectedly accepted)")
Print("")

; ─────────────────────────────────────────────────────
; 4. Migration: typeless typed properties removed
; ─────────────────────────────────────────────────────
Print("── 4. Migration: a size specifier without a class is now rejected ──")

; The old Struct { buf: 32 } form (untyped raw buffer of 32 bytes,
; no class type) is gone. To reserve raw bytes inside a struct, build
; one using IntPtr / Int8 fields or wrap a Buffer alongside the struct.

old_form_fail := ""
try {
    Struct OldBuf {
        buf: 32                               ; typeless typed property
    }
} catch as e
    old_form_fail := e.Message
Print("  Old 'buf: 32' raises: {}", old_form_fail ? old_form_fail : "(unexpectedly accepted)")
Print("")

; ─────────────────────────────────────────────────────
; 5. Fix: String(x) when x.ToString() returns no value
; ─────────────────────────────────────────────────────
Print("── 5. String(x) survives a void ToString ──")

; Previously String(x) crashed when x.ToString() returned no value.
; Now the call cleanly produces unset (blank-unset) and you get a
; normal "No value was returned" exception if you try to consume the
; result -- or you can default it with ?? as usual.

class Silent {
    ToString() {                              ; intentionally returns nothing
    }
}

s := String(Silent()) ?? "<unset>"
Print("  String(Silent()) ?? '<unset>' = '{}'", s)

caught := ""
try
    raw := String(Silent())
catch as e
    caught := e.Message
Print("  String(Silent()) raises cleanly: '{}'", caught)
Print("")

; ─────────────────────────────────────────────────────
; 6. Fix: x?.%y% is no longer a syntax error
; ─────────────────────────────────────────────────────
Print("── 6. x?.%y% parses ──")

; The maybe-property operator (?.) plus a dynamic property name
; (%y%) used to be rejected at parse time. It is now accepted and
; behaves like a normal dynamic property lookup that short-circuits
; when the receiver is unset.

config := {theme: "dark", lang: "en"}
absent := unset
key := "theme"

present_val := config?.%key% ?? "<unset>"
absent_val  := absent?.%key% ?? "<unset>"
Print("  config?.%key% = {}", present_val)
Print("  absent?.%key% = {}", absent_val)
Print("")

; ─────────────────────────────────────────────────────
; 7. Fix: StrGet(x, 0) returns String, not Number
; ─────────────────────────────────────────────────────
Print("── 7. StrGet(x, 0) returns String ──")

; A zero length used to slip through and return the numeric pointer.
; Now it always returns a (possibly empty) String, matching the
; documented return type.

buf := Buffer(64, 0)
StrPut("hello", buf, "UTF-16")
zero_len := StrGet(buf, 0)
Print("  StrGet(buf, 0)            = '{}' (Type={})", zero_len, Type(zero_len))
five := StrGet(buf, 5, "UTF-16")
Print("  StrGet(buf, 5, 'UTF-16')  = '{}' (Type={})", five, Type(five))
Print("")

; ─────────────────────────────────────────────────────
; 8. Fix: virtual ref assignments permit unset
; ─────────────────────────────────────────────────────
Print("── 8. Virtual ref assignments permit unset ──")

; Functions that take an output VarRef (&var) can now have unset
; written through the ref by the callee, leaving the caller's slot
; uninitialised rather than holding "".

ClearOut(&out) {
    out := unset
}

x := "had a value"
ClearOut(&x)
Print("  After ClearOut(&x): IsSet(x) = {}", IsSet(x))
Print("")

; ─────────────────────────────────────────────────────
; 9. Fix: DllCall propagates errors from output-arg __Value eval
; ─────────────────────────────────────────────────────
Print("── 9. DllCall propagates output-arg __Value errors ──")

; Struct-typed output parameters call __Value on the passed-in object
; to commit the result back. If that getter throws, the exception used
; to be swallowed (DllCall returned silently). It now surfaces as a
; normal exception.
;
; This is a fix in behaviour; an example would need a struct class
; whose __Value getter raises, which is involved. The contract is:
; throwing from a DllCall output-arg __Value getter now reaches your
; try/catch like any other call-site exception.

Print("  (DllCall now rethrows __Value errors from struct output args.)")
Print("")

; ─────────────────────────────────────────────────────
; 10. Fix: load-time catch for ambiguous !a ?? b / b + a ?? c
; ─────────────────────────────────────────────────────
Print("── 10. Ambiguous !a ?? b and b + a ?? c caught at load time ──")

; Without explicit parentheses, the precedence of ! and + against
; ?? was ambiguous and could parse into a tree the author did not
; intend. The parser now rejects the ambiguous form at load time; you
; must parenthesise to make the grouping explicit. Demonstrating this
; safely from a runnable script means showing the workarounds:

a := unset
b := 42

; Workaround for !a ?? b : parenthesise around (a ?? b) first.
val1 := !(a ?? b)
Print("  !(a ?? b)        = {}", val1)

; Workaround for b + a ?? c : parenthesise the ?? side.
c := 100
val2 := b + (a ?? c)
Print("  b + (a ?? c)     = {}", val2)

Print("  (Load-time check rejects unparenthesised !a ?? b / b + a ?? c.)")
Print("")

; ─────────────────────────────────────────────────────
; Bonus: the variadic Print itself
; ─────────────────────────────────────────────────────
Print("── Bonus: this fork's Print(Fmt, Values*) dispatches to Format ──")

; Every Print(...) call above used to be Print(Format(...)). The
; fork's Print BIF now accepts a format string and trailing values
; directly. One arg with literal braces is preserved as-is (no Format
; pass), so JSON-like text still prints verbatim.

Print("  positional      : {}/{}/{}", "a", "b", "c")
Print("  indexed (reused): {1}-{2}-{1}", "x", "y")
Print("  format specs    : 0x{:08X} = {1}", 0xDEAD)
Print("  literal braces  : {ok: true, n: 42}")
Print("")

; ─────────────────────────────────────────────────────
; Summary
; ─────────────────────────────────────────────────────
Print("═══════════════════════════════════════════════")
Print("Post-merge alpha tightens the type system and call syntax:")
Print("  • New: DllCall/ComCall/CallbackCreate accept 'Void' return")
Print("  • Removed: a?.() and a?.[]  -> use (a?)() and (a?)[]")
Print("  • Removed: type strings i32/u32/...  -> use class names")
Print("  • Removed: typeless typed properties (size specifier alone)")
Print("  • Fixed: String(), x?.%y%, StrGet(_,0), unset thru &refs,")
Print("           DllCall output-arg __Value errors, load-time !??/+??")
Print("  • Fork: Print is now variadic -- Format dispatch is built in")
Print("═══════════════════════════════════════════════")
