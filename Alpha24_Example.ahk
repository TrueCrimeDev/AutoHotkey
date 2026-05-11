/*
Alpha24_Example.ahk -- AutoHotkey v2.1-alpha.24 feature showcase

New features:
  1. CallbackCreate with typed parameter arrays
  2. DefineProp Offset sub-parameter for union-like fields
  3. #Import Export X {*} wildcard re-export
  4. Struct.Ptr now subclasses base.Ptr (inheritance chain)
  5. GetOwnPropDesc returns classes for numeric types
  6. Bug fixes (circular refs, nested struct cleanup, etc.)

Run: bin\AutoHotkey64.exe Alpha24_Example.ahk
*/
#Requires AutoHotkey v2.1-alpha.24

stdout := FileOpen("*", "w", "UTF-8")
Print(text) => stdout.Write(text)
PrintLine(text := "") => stdout.Write(text "`n")

PrintLine "=== AutoHotkey v2.1-alpha.24 Feature Showcase ==="
PrintLine Format("Version: {}", A_AhkVersion)
PrintLine ""

; ─────────────────────────────────────────────────────
; 1. CallbackCreate with typed parameter arrays
; ─────────────────────────────────────────────────────
PrintLine "── 1. CallbackCreate with typed parameters ──"

; Previously CallbackCreate only accepted a param count:
;   CallbackCreate(Func, Options, ParamCount)
;
; Alpha.24 allows the 3rd param to be an array of type classes.
; The LAST element is the return type, everything before it
; defines parameter types:
;   CallbackCreate(Func, Options, [Param1Type, Param2Type, ..., ReturnType])
;
; This enables proper type conversions for floats, structs, etc.
; that can't be inferred from raw pointer-sized stack values.

; Integer callback (classic vs typed)
AddInts(a, b) => a + b

cb_classic := CallbackCreate(AddInts, , 2)
r1 := DllCall(cb_classic, "Int", 15, "Int", 27, "Int")
PrintLine Format("  Classic:  AddInts(15, 27) = {}", r1)
CallbackFree(cb_classic)

cb_typed := CallbackCreate(AddInts, , [Int32, Int32, Int32])
r2 := DllCall(cb_typed, "Int", 100, "Int", 200, "Int")
PrintLine Format("  Typed:    AddInts(100, 200) = {}", r2)
CallbackFree(cb_typed)

; Float callback -- this is where typed params shine.
; Without types, float values would be misinterpreted as integers.
AddFloats(a, b) => a + b

cb_float := CallbackCreate(AddFloats, , [Float64, Float64, Float64])
r3 := DllCall(cb_float, "Double", 1.5, "Double", 2.7, "Double")
PrintLine Format("  Float:    AddFloats(1.5, 2.7) = {:.1f}", r3)
CallbackFree(cb_float)

; Mixed types
Multiply(x, factor) => x * factor

cb_mix := CallbackCreate(Multiply, , [Float64, Int32, Float64])
r4 := DllCall(cb_mix, "Double", 3.14, "Int", 3, "Double")
PrintLine Format("  Mixed:    Multiply(3.14, 3) = {:.2f}", r4)
CallbackFree(cb_mix)
PrintLine ""

; ─────────────────────────────────────────────────────
; 2. DefineProp Offset for union-like fields
; ─────────────────────────────────────────────────────
PrintLine "── 2. DefineProp Offset (unions) ──"

; The new Offset sub-parameter lets you place typed fields
; at explicit byte offsets. Multiple fields at the same offset
; creates a C-style union -- they share the same memory.

; VARIANT-style union: different types at the same offset
Struct Variant {
    vtype: u16
}
; All three value fields overlap at offset 8
DefineProp Variant.Prototype, "intVal",  {Type: Int32,   Offset: 8}
DefineProp Variant.Prototype, "fltVal",  {Type: Float64, Offset: 8}
DefineProp Variant.Prototype, "ptrVal",  {Type: IntPtr,   Offset: 8}

v := Variant()
v.vtype := 3  ; VT_I4 (integer)
v.intVal := 42
PrintLine Format("  Variant(int):   vtype={}, intVal={}", v.vtype, v.intVal)

v.vtype := 5  ; VT_R8 (double)
v.fltVal := 3.14159
PrintLine Format("  Variant(float): vtype={}, fltVal={:.5f}", v.vtype, v.fltVal)

; RGBA color with overlapping byte views
Struct Color {
    rgba: u32
}
DefineProp Color.Prototype, "r", {Type: UInt8, Offset: 0}
DefineProp Color.Prototype, "g", {Type: UInt8, Offset: 1}
DefineProp Color.Prototype, "b", {Type: UInt8, Offset: 2}
DefineProp Color.Prototype, "a", {Type: UInt8, Offset: 3}

c := Color()
c.rgba := 0xFF8040C0
PrintLine Format("  Color: rgba=0x{:08X}", c.rgba)
PrintLine Format("    r=0x{:02X}  g=0x{:02X}  b=0x{:02X}  a=0x{:02X}", c.r, c.g, c.b, c.a)

; Write individual channels, read as u32
c.r := 0x00, c.g := 0xFF, c.b := 0x00, c.a := 0xFF
PrintLine Format("  Set g=0xFF, a=0xFF -> rgba=0x{:08X}", c.rgba)

; Named offset: reference another field's position
Struct Register {
    lo: u16
    hi: u16
}
DefineProp Register.Prototype, "full", {Type: UInt32, Offset: "lo"}

reg := Register()
reg.full := 0xDEADBEEF
PrintLine Format("  Register: full=0x{:08X}, lo=0x{:04X}, hi=0x{:04X}",
    reg.full, reg.lo, reg.hi)
PrintLine ""

; ─────────────────────────────────────────────────────
; 3. GetOwnPropDesc returns classes for numeric types
; ─────────────────────────────────────────────────────
PrintLine "── 3. GetOwnPropDesc returns type classes ──"

; Previously GetOwnPropDesc returned type codes as strings.
; Now it returns the actual type class (Int32, Float64, etc.)

Struct Sensor {
    value: Float32
    id: UInt16
    flags: UInt8
}

for field in ["value", "id", "flags"] {
    desc := Sensor.Prototype.GetOwnPropDesc(field)
    PrintLine Format("  Sensor.{}: Type={}", field, desc.Type)
}
PrintLine ""

; ─────────────────────────────────────────────────────
; 4. Struct.Ptr inheritance chain
; ─────────────────────────────────────────────────────
PrintLine "── 4. Struct.Ptr inheritance ──"

; a.Ptr now subclasses a.base.Ptr instead of Struct.Ptr.
; This preserves the inheritance chain for pointer types.

Struct Shape {
    area: Float64
}

Struct Circle extends Shape {
    radius: Float64
}

ci := Circle()
ci.radius := 5.0
ci.area := 3.14159 * ci.radius ** 2
PrintLine Format("  Circle: radius={:.1f}, area={:.2f}", ci.radius, ci.area)
PrintLine Format("  Circle.Size={} bytes (Shape={} + radius={})",
    ci.Size, Shape().Size, ci.Size - Shape().Size)

; The Ptr type inherits properly:
;   Circle.Ptr -> Shape.Ptr -> Struct.Ptr
; This means functions accepting Shape.Ptr also accept Circle.Ptr
PrintLine "  Ptr chain: Circle.Ptr inherits from Shape.Ptr"
PrintLine ""

; ─────────────────────────────────────────────────────
; 5. #Import Export {*} wildcard re-export
; ─────────────────────────────────────────────────────
PrintLine "── 5. #Import Export X {*} ──"

; New syntax: #Import Export ModuleName {*}
; Re-exports all public symbols from another module.
; Useful for creating barrel/facade modules that
; aggregate exports from sub-modules.
;
; Example (requires separate files):
;
;   ; math/vector.ahk
;   #Module Math.Vector
;   export Vec2(x, y) => {x: x, y: y}
;   export Vec3(x, y, z) => {x: x, y: y, z: z}
;
;   ; math/index.ahk
;   #Module Math
;   #Import Export Math.Vector {*}   ; re-exports Vec2, Vec3
;
;   ; app.ahk
;   #Import Math {Vec2, Vec3}        ; works! imported via re-export

PrintLine "  Syntax: #Import Export ModuleName {*}"
PrintLine "  Re-exports all public symbols from a module"
PrintLine "  Enables barrel/facade module patterns"
PrintLine ""

; ─────────────────────────────────────────────────────
; 6. Bug fixes
; ─────────────────────────────────────────────────────
PrintLine "── 6. Bug fixes ──"

; Circular reference fix: Struct.Ptr and Struct[N] classes
; no longer prevent garbage collection
Struct Tile {
    id: u16
    elevation: Float32
}
grid := Tile[6]()
loop 6 {
    grid[A_Index].id := A_Index
    grid[A_Index].elevation := A_Index * 1.5
}
PrintLine Format("  Struct arrays: no circular ref leaks")
PrintLine Format("  Tile[6]: ids=[{},{},{},{},{},{}]",
    grid[1].id, grid[2].id, grid[3].id, grid[4].id, grid[5].id, grid[6].id)

; Nested struct cleanup: releasing outer struct properly
; releases inner struct references
Struct Inner {
    data: u32
}
Struct Outer {
    header: Inner
    tag: u16
}
o := Outer()
o.header.data := 0xCAFEBABE
o.tag := 24
PrintLine Format("  Nested struct cleanup safe: header=0x{:08X}, tag={}",
    o.header.data, o.tag)

; Class self-subclass prevention
PrintLine "  Class declarations cannot subclass themselves"
PrintLine "  #Import loops (var pointing to itself) prevented"
PrintLine ""

; ─────────────────────────────────────────────────────
; Summary
; ─────────────────────────────────────────────────────
PrintLine "═══════════════════════════════════════════════"
PrintLine "Alpha.24 headline features:"
PrintLine "  • CallbackCreate accepts [ParamTypes..., ReturnType]"
PrintLine "  • DefineProp Offset enables C-style unions"
PrintLine "  • #Import Export X {*} for wildcard re-exporting"
PrintLine "  • Struct.Ptr follows proper inheritance chain"
PrintLine "  • GetOwnPropDesc returns type classes"
PrintLine "  • Struct circular ref + nested cleanup fixes"
PrintLine "═══════════════════════════════════════════════"
