; alpha.22 Feature: Struct keyword and class
; New native Struct support for typed, memory-layout-aware data structures.
; Struct classes get automatic .Ptr subclasses for pointer handling.

; --- Defining a Struct ---
; The `Struct` keyword creates a class with defined memory layout

Struct POINT {
    x: Int32
    y: Int32
}

pt := POINT()
pt.x := 100
pt.y := 200

FileAppend("POINT: (" pt.x ", " pt.y ")`n", "*")
FileAppend("Type: " Type(pt) "`n", "*")

; --- Struct with different field types ---

Struct RECT {
    left:   Int32
    top:    Int32
    right:  Int32
    bottom: Int32
}

rc := RECT()
rc.left := 0
rc.top := 0
rc.right := 1920
rc.bottom := 1080

FileAppend("RECT: " rc.left "," rc.top " to " rc.right "," rc.bottom "`n", "*")

; --- Automatic .Ptr classes ---
; Each Struct automatically gets a .Ptr subclass for working with pointers.
; This replaces the old StructFromPtr function (removed in alpha.22).

FileAppend("POINT.Ptr exists: " (POINT.HasOwnProp("Ptr") ? "yes" : "no") "`n", "*")

; --- Structs are value types with defined layout ---

Struct Color {
    r: UInt8
    g: UInt8
    b: UInt8
    a: UInt8
}

c := Color()
c.r := 255
c.g := 128
c.b := 0
c.a := 255

FileAppend("Color RGBA: " c.r "," c.g "," c.b "," c.a "`n", "*")

; --- Breaking changes in alpha.22 ---
; - StructFromPtr removed. Use automatic .Ptr classes instead.
; - ObjGetDataPtr fallback for DllCall Ptr parameters removed.
; - DllCall and typed properties now require a Struct subclass.
