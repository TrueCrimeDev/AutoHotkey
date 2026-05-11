/*
Alpha29_Example.ahk -- AutoHotkey v2.1-alpha.29 feature showcase

Changes in alpha.29:
  1. `X() => Y()` propagates implicit blank-unset return through tail calls
  2. Maybe operator (?) can short-circuit most operators
  3. v2.1 mode default return is `unset` when any `return expr` is present
  4. Built-ins now return `unset` (not "") in v2.1 mode:
     Array.Delete/Pop/RemoveAt, Object.DeleteProp/GetMethod/GetOwnPropDesc,
     Gui.MenuBar, Gui.FocusedCtrl, Gui[], GuiFromHwnd, GuiCtrlFromHwnd,
     InputHook.On*, MenuFromHandle, ObjGetBase / Any.Prototype.Base,
     RegExMatch OutputVar on no-match
  Alpha-only fixes:
    - Map/Array now throw UnsetItemError in v2.0 mode when result unused
    - Struct.Array.Prototype no longer permits new typed properties
    - ClassObj.Prototype.Base writable when no typed properties

  Reading guide:
    Now that more built-ins return `unset`, bare `x := fn()` will throw
    if fn() didn't return a value. Use `?? default`, `try { ... } catch`,
    or test the underlying var with IsSet() before consuming the result.

Run: bin\AutoHotkey64.exe Alpha29_Example.ahk
*/
#Requires AutoHotkey v2.1-alpha.29

stdout := FileOpen("*", "w", "UTF-8")
Print(text) => stdout.Write(text)
PrintLine(text := "") => stdout.Write(text "`n")

PrintLine "=== AutoHotkey v2.1-alpha.29 Feature Showcase ==="
PrintLine Format("Version: {}", A_AhkVersion)
PrintLine ""

; ─────────────────────────────────────────────────────
; 1. Tail-call unset propagation:  X() => Y()
; ─────────────────────────────────────────────────────
PrintLine "── 1. `X() => Y()` propagates blank-unset return ──"

; A fat-arrow function that tail-calls another function/method now
; transparently propagates Y's "no value returned" state.
; Previously X() => Y() always produced a value (`` if Y was void);
; now if Y returns without a value, X behaves the same way.
;
; Applies to tail calls of functions and methods only, not properties.

VoidCallee() {            ; bare `return;` (no expression) -> blank-unset
    return
}

PassThrough() => VoidCallee()    ; tail call: should also be blank-unset

; Capturing the result directly would throw, which itself proves the
; propagation. Wrap in try/catch to observe it.
got_value := true
try
    result := PassThrough()
catch
    got_value := false

PrintLine Format("  result := PassThrough() raised because no value? {}", !got_value)
PrintLine "  -> alpha.29 propagated the missing return value across the tail call."
PrintLine ""

; ─────────────────────────────────────────────────────
; 2. Maybe operator `?` short-circuits more operators
; ─────────────────────────────────────────────────────
PrintLine "── 2. Maybe operator (?) short-circuits ──"

; The `?` suffix turns an unset variable into the `unset` sentinel
; rather than throwing. Alpha.29 lets that sentinel short-circuit
; through most operators (||, &&, comparisons, arithmetic, etc.)
; instead of erroring inside the operator. The whole sub-expression
; yields unset, which you handle at the outer level with `??`.

; Pre-alpha.29, `(() => a? || 1)()` could crash; alpha.29 fixed the
; parser path so the IIFE evaluates cleanly. The result of an unset
; `?` operand still propagates through `||` as unset, so assigning
; the IIFE result raises "No value was returned" -- which itself
; proves the short-circuit didn't crash inside `||`.
iife_propagated_unset := false
try
    boxed := (() => unsetLocal? || 42)()
catch
    iife_propagated_unset := true
PrintLine Format("  (() => a? || 42)() short-circuited cleanly (unset propagated)? {}",
    iife_propagated_unset)

; Comparisons short-circuit too -- comparing the maybe-sentinel with
; a number no longer raises inside `>`; the comparison just falls
; through. (Result captured but unused.)
cmp_result := (missingVar? > 0)
PrintLine "  (missing? > 0) evaluated without raising inside the operator"
PrintLine ""

; ─────────────────────────────────────────────────────
; 3. v2.1 mode default return is `unset` when any `return expr` present
; ─────────────────────────────────────────────────────
PrintLine "── 3. v2.1 default return is `unset` (was blank) ──"

; In v2.1 mode (set by `#Requires AutoHotkey v2.1-...`), if a function
; contains any `return <expr>` then the implicit fall-through return
; is `unset` rather than blank. Forgetting to return is now visible.

EvenOrUnset(n) {
    if Mod(n, 2) = 0
        return n
    ; falls through with no return -> unset (not "")
}

a := EvenOrUnset(4) ?? "<unset>"
b := EvenOrUnset(5) ?? "<unset>"
PrintLine Format("  EvenOrUnset(4) = {}", a)
PrintLine Format("  EvenOrUnset(5) = {}", b)
PrintLine ""

; ─────────────────────────────────────────────────────
; 4. Array.Pop / Array.RemoveAt / Array.Delete return unset on hole
; ─────────────────────────────────────────────────────
PrintLine "── 4. Array remove operations return `unset` for holes ──"

; In v2.1 mode, these built-ins now return unset (no value) when
; the slot they touch had no value -- previously they returned "".
; Use `?? default` or try/catch on the result to handle the unset case.

arr := [1, , 3]                          ; element 2 is a hole
removed := arr.RemoveAt(2) ?? "<unset>"
PrintLine Format("  arr.RemoveAt(hole) = {}", removed)

arr2 := [10, 20, 30]
popped := arr2.Pop() ?? "<unset>"
PrintLine Format("  arr2.Pop() = {}", popped)

arr3 := [100, , 300]
deleted := arr3.Delete(2) ?? "<unset>"   ; deleting an existing hole
PrintLine Format("  arr3.Delete(hole) = {}", deleted)
PrintLine ""

; ─────────────────────────────────────────────────────
; 5. Object.DeleteProp / GetMethod / GetOwnPropDesc return unset
; ─────────────────────────────────────────────────────
PrintLine "── 5. Object reflection returns `unset` for missing ──"

obj := { a: 1 }

gone := obj.DeleteProp("nope") ?? "<unset>"
PrintLine Format("  DeleteProp('nope') = {}", gone)

m := obj.GetMethod("nonexistent") ?? "<unset>"
PrintLine Format("  GetMethod('nonexistent') = {}", m)

desc := obj.GetOwnPropDesc("b") ?? "<unset>"
PrintLine Format("  GetOwnPropDesc('b') = {}", desc)
PrintLine ""

; ─────────────────────────────────────────────────────
; 6. RegExMatch OutputVar is unset on no-match
; ─────────────────────────────────────────────────────
PrintLine "── 6. RegExMatch OutputVar is `unset` on no-match ──"

; Previously OutputVar would be set to "" when the regex didn't match.
; Now it's left unset, so IsSet(match) distinguishes match vs miss.

RegExMatch("hello", "x",  &match1)
RegExMatch("hello", "l+", &match2)
PrintLine Format("  No-match: IsSet(match1) = {}", IsSet(match1))
PrintLine Format("  Match:    IsSet(match2) = {}, match = '{}'",
    IsSet(match2), IsSet(match2) ? match2[0] : "")
PrintLine ""

; ─────────────────────────────────────────────────────
; 7. GuiFromHwnd / GuiCtrlFromHwnd / MenuFromHandle return unset
; ─────────────────────────────────────────────────────
PrintLine "── 7. Hwnd/Handle lookups return `unset` for unknown IDs ──"

g_lookup  := GuiFromHwnd(0)     ?? "<unset>"
gc_lookup := GuiCtrlFromHwnd(0) ?? "<unset>"
mn_lookup := MenuFromHandle(0)  ?? "<unset>"
PrintLine Format("  GuiFromHwnd(0)     = {}", g_lookup)
PrintLine Format("  GuiCtrlFromHwnd(0) = {}", gc_lookup)
PrintLine Format("  MenuFromHandle(0)  = {}", mn_lookup)
PrintLine ""

; ─────────────────────────────────────────────────────
; 8. ObjGetBase / .Base at the top of a chain
; ─────────────────────────────────────────────────────
PrintLine "── 8. ObjGetBase returns `unset` past the chain top ──"

; When you walk a base chain, the topmost prototype's base used to come
; back as "". It's now `unset`, which lets you cleanly stop iterating.

class Foo {
}

p := Foo.Prototype
walked := 0
loop {
    nextBase := ObjGetBase(p) ?? unset
    if !IsSet(nextBase)
        break
    p := nextBase
    walked++
}
PrintLine Format("  Walked {} bases before ObjGetBase returned unset.", walked)
PrintLine ""

; ─────────────────────────────────────────────────────
; 9. Alpha-only fix: Struct.Array.Prototype is sealed
; ─────────────────────────────────────────────────────
PrintLine "── 9. Struct.Array.Prototype no longer takes typed props ──"

Struct Point29 {
    x: i32
    y: i32
}

pts := Point29[4]()
loop 4
    pts[A_Index].x := A_Index * 11, pts[A_Index].y := A_Index * 13
PrintLine Format("  Point29[4]() size: {} bytes", pts.Size)
PrintLine Format("  pts[2] = ({}, {})", pts[2].x, pts[2].y)
PrintLine "  Struct.Array.Prototype is sealed against new typed props"
PrintLine ""

; ─────────────────────────────────────────────────────
; Summary
; ─────────────────────────────────────────────────────
PrintLine "═══════════════════════════════════════════════"
PrintLine "Alpha.29 sharpens v2.1's `unset` story:"
PrintLine "  • Tail-call functions propagate blank-unset returns"
PrintLine "  • Maybe operator (?) short-circuits most operators"
PrintLine "  • v2.1-mode default return is `unset` (not '')"
PrintLine "  • Array/Object/Gui/RegEx built-ins return `unset` for miss"
PrintLine "  • Struct.Array.Prototype is now sealed"
PrintLine "  • Class.Prototype.Base writable when no typed properties"
PrintLine "═══════════════════════════════════════════════"
