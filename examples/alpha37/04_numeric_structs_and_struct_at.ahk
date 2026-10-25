; alpha.37: numeric struct instances pass by value; Struct.At accepts Struct
;
; 1. DllCall(..., Int32, n, ...) with n := Int32() now passes n's *value*,
;    the same as "Int", n.__Value. Before, Int32 threw TypeError "Expected a
;    Number but got an Int32." and Int64 corrupted memory. A default such as
;    f(n := Int32()) therefore works as a typed zero.
; 2. Struct.At(ptr) no longer needs a subclass: it returns a zero-size view
;    whose only job is to carry an address (Ptr) that other struct classes can
;    reinterpret. Before, it threw "Invalid class".
;
; Run: bin\AutoHotkey64Console.exe examples\alpha37\04_numeric_structs_and_struct_at.ahk
#Requires AutoHotkey v2.1-alpha.37

; --- 1. Typed counters passed straight to C ----------------------------------
delta := Int32()
delta.__Value := -42
Print("abs({}) = {}", delta.__Value, DllCall("msvcrt\abs", Int32, delta, "Int"))

big := Int64()
big.__Value := -9000000000
Print("_abs64({}) = {}", big.__Value, DllCall("msvcrt\_abs64", Int64, big, "Int64"))

; A typed default parameter: the callee gets a real Int32 zero, not a string.
Clamp(v, lo := Int32(), hi := Int32()) {
    if hi.__Value = 0
        hi.__Value := 100
    return Min(Max(v, lo.__Value), hi.__Value)
}
Print("Clamp(150) = {}  Clamp(-5) = {}", Clamp(150), Clamp(-5))

; The same instance can still be passed by pointer when the function writes
; back: Int32.Ptr hands over its address.
n := Int32()
n.__Value := DllCall("GetCurrentDirectoryW", "UInt", 0, "Str", unset, "UInt")
Print("by value: {}   by pointer reads back: {}", DllCall("msvcrt\abs", Int32, n, "Int"), NumGet(n.Ptr, "Int"))

; --- 2. Struct.At as an address carrier ---------------------------------------
struct Pair {
    a : Int32
    b : Int32
}
buf := Buffer(16, 0)
NumPut("Int", 7, "Int", 9, "Int", 11, "Int", 13, buf)

anchor := Struct.At(buf.Ptr)
Print("Struct.At: Type {}  Size {}  Ptr matches buffer: {}", Type(anchor), anchor.Size, anchor.Ptr = buf.Ptr)

; Reinterpret the same memory through two different layouts. Size is an
; instance property, so read it from a throwaway Pair().
pairSize := Pair().Size
first := Pair.At(anchor.Ptr)
second := Pair.At(anchor.Ptr + pairSize)
Print("Pair #1 = ({}, {})   Pair #2 = ({}, {})", first.a, first.b, second.a, second.b)

; Walk a packed array of Pair with nothing but an address and a size.
Walk(base, count) {
    out := ""
    loop count {
        p := Pair.At(base + (A_Index - 1) * Pair().Size)
        out .= Format("{}+{}={} ", p.a, p.b, p.a + p.b)
    }
    return out
}
Print("walk: {}", Walk(anchor.Ptr, 2))

; A Struct view is still a struct: it cannot grow properties by accident.
try anchor.label := "x"
catch PropertyError as e
    Print("anchor.label := `"x`": {}", e.Message)
