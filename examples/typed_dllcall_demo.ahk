#Requires AutoHotkey v2.1-alpha.26

; Before: Buffer + NumGet + magic offsets
buf := Buffer(8)
DllCall("GetCursorPos", "Ptr", buf)
x := NumGet(buf, 0, "Int")
y := NumGet(buf, 4, "Int")

; After: Struct + named fields
Struct POINT {
    x: Int32
    y: Int32
}
pt := POINT()
DllCall("GetCursorPos", POINT.Ptr, pt)
; pt.x, pt.y — done

; Numeric type classes work as DllCall types too
DllCall("GetSystemMetrics", Int32, 0)          ; was "Int"
DllCall("msvcrt\sqrt", Float64, 2.0, Float64)  ; was "Double"

; Typed callbacks — floats actually work now (alpha.24)
AddFloats(a, b) => a + b
cb := CallbackCreate(AddFloats, , [Float64, Float64, Float64])
DllCall(cb, "Double", 1.5, "Double", 2.7, "Double")  ; => 4.2
CallbackFree(cb)

; Union via DefineProp Offset — overlapping fields (alpha.24)
Struct Color {
    rgba: UInt32
}
DefineProp(Color.Prototype, "r", {Type: UInt8, Offset: 0})
DefineProp(Color.Prototype, "g", {Type: UInt8, Offset: 1})
DefineProp(Color.Prototype, "b", {Type: UInt8, Offset: 2})
DefineProp(Color.Prototype, "a", {Type: UInt8, Offset: 3})
c := Color()
c.rgba := 0xFF00FF80
; c.r => 128, c.g => 255, c.b => 0, c.a => 255

; Inline arrays in struct fields (alpha.26)
Struct Sensor {
    id: UInt8
    readings: Float64[3]
}
s := Sensor()
s.id := 1
s.readings[1] := 23.5, s.readings[2] := 24.1, s.readings[3] := 22.9
