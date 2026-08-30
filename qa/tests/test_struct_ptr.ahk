#Requires AutoHotkey v2.1-alpha.30
; test_struct_ptr.ahk -- the `.Ptr` pointer-view subclass (the alpha.30
; replacement for the removed StructFromPtr). Facts verified against
; 2.1-alpha.30+Console on 2026-07-09. Backlog item #2.
;
; Mechanism (undocumented elsewhere): `PT.Ptr` is an auto-generated Struct
; subclass whose single field is a pointer (size = sizeof(void*)). A `PT.Ptr()`
; instance is 8 bytes of pointer storage; you overlay it on foreign memory by
; writing the target address into its own `.Ptr` storage, then dereference the
; target through `.__Value`, which yields a live `PT` view. Writes through that
; view commit to the pointed-to memory.
#Include ..\Assert.ahk

Struct PT {
    x: Int32
    y: Int32
}

; ---- base-class Struct.Ptr() no longer crashes (alpha.30 fix) ----
; Calling Ptr() on the Struct class object itself used to access-violate.
Assert.noThrow(() => Struct.Ptr(), "Struct.Ptr() on the base class does not crash")
Assert.eq(Type(Struct.Ptr()), "Struct.Ptr", "Struct.Ptr() returns a Struct.Ptr instance")

; ---- PT.Ptr is a generated class; PT.Ptr() a pointer-sized instance ----
Assert.eq(Type(PT.Ptr), "Class", "PT.Ptr (getter) is the pointer Class")
v := PT.Ptr()
Assert.eq(Type(v), "PT.Ptr", "PT.Ptr() constructs a PT.Ptr instance")
Assert.eq(v.Size, 8, "PT.Ptr instance is pointer-sized (8 bytes of storage)")

; ---- overlay a view on foreign memory + dereference via __Value ----
p := PT()
p.x := 5
p.y := 6
NumPut("ptr", p.Ptr, v.Ptr)                 ; aim the view at p's memory
Assert.eq(Type(v.__Value), "PT", ".__Value dereferences to a PT view")
Assert.eq(v.__Value.x, 5, "deref reads the pointed-to x")
Assert.eq(v.__Value.y, 6, "deref reads the pointed-to y")

; ---- writes through the deref commit to the pointed-to memory ----
v.__Value.x := 111
Assert.eq(p.x, 111, "write through .__Value commits to the target struct")
Assert.eq(NumGet(p.Ptr, 0, "int"), 111, "...and lands in the target's raw memory")

; ---- __Value := unset is now permitted (alpha.30 fix), read-back is unset ----
Assert.noThrow(() => v.__Value := unset, ".__Value := unset does not throw")
Assert.eq(v.__Value ?? "UNSET", "UNSET", "after unset, reading .__Value yields unset")

Assert.Summary()
