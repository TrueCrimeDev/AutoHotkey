#Requires AutoHotkey v2.1-alpha.30
; test_struct.ahk -- typed Struct system (alpha.30). Facts verified against
; 2.1-alpha.30+Console on 2026-07-09. Backlog item #2.
#Include ..\Assert.ahk

Struct PT {
    x: Int32
    y: Int32
}

Struct NEST {
    a: Int32
    pt: PT
}

Struct AR {
    v: Int32[4]
}

; ---- sizes: fields are class refs (Int32 = 4 bytes), packed in order ----
Assert.eq(PT().Size, 8, "sizeof PT (2x Int32)")
Assert.eq(NEST().Size, 12, "sizeof NEST (Int32 + PT)")
Assert.eq(AR().Size, 16, "sizeof AR (Int32[4])")

; ---- field round-trip + raw memory backing ----
p := PT()
p.x := 5
p.y := -7
Assert.eq(p.x, 5, "PT.x round-trips")
Assert.eq(p.y, -7, "PT.y round-trips (signed)")
Assert.truthy(p.Ptr, "PT.Ptr is non-zero")
Assert.eq(NumGet(p.Ptr, 0, "int"), 5, "PT.x commits to raw memory at offset 0")
Assert.eq(NumGet(p.Ptr, 4, "int"), -7, "PT.y commits to raw memory at offset 4")

; ---- nested struct field writes commit to the PARENT block ----
; NEST: a at 0, pt at 4; pt.y is the second Int32 of pt -> offset 4 + 4 = 8.
n := NEST()
n.pt.y := 99
Assert.eq(NumGet(n.Ptr, 8, "int"), 99, "nested pt.y commits to parent memory (offset 8)")
Assert.eq(n.pt.y, 99, "nested pt.y reads back")

; ---- Struct.Array: 1-based, bounds-checked, has .Length/.Ptr, not enumerable ----
a := AR()
a.v[1] := 7
a.v[4] := 40
Assert.eq(a.v.Length, 4, "Struct.Array .Length")
Assert.eq(a.v[1], 7, "Struct.Array is 1-based (index 1 is first)")
Assert.eq(NumGet(a.v.Ptr, 0, "int"), 7, "Struct.Array[1] backs raw offset 0")
Assert.eq(NumGet(a.v.Ptr, 12, "int"), 40, "Struct.Array[4] backs raw offset 12")
Assert.throws(() => a.v[0] := 1, "Struct.Array index 0 throws", "Invalid index")
Assert.throws(() => a.v[5] := 1, "Struct.Array index past end throws", "Invalid index")

Assert.Summary()
