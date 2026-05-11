/*
Alpha23_Example.ahk -- AutoHotkey v2.1-alpha.23 feature showcase

New features:
  1. Numeric type classes extending Struct (Int32, Float32, UInt8, etc.)
  2. Structured array classes via StructClass[N]
  3. Struct.Prototype.Size fix
*/
#Requires AutoHotkey v2.1-alpha.23

stdout := FileOpen("*", "w", "UTF-8")
Print(text) => stdout.Write(text)

; Numeric types as struct fields
Struct Vec3f {
    x: Float32
    y: Float32
    z: Float32
}
v := Vec3f()
v.x := 1.5, v.y := 2.7, v.z := -3.14
Print Format("Vec3f({:.2f}, {:.2f}, {:.2f}) -- {} bytes`n", v.x, v.y, v.z, v.Size)

; Mixed numeric types
Struct SensorReading {
    timestamp: Int64
    temperature: Float32
    humidity: Float32
    sensor_id: UInt16
    flags: UInt8
}
reading := SensorReading()
reading.timestamp := 1711234567890
reading.temperature := 22.5
reading.humidity := 45.2
reading.sensor_id := 1042
reading.flags := 0x03
Print Format("SensorReading: temp={}, id={}, flags=0x{:02X} -- {} bytes`n",
    reading.temperature, reading.sensor_id, reading.flags, reading.Size)

; Typed arrays with StructClass[N]
a := Int32[4]()
a[1] := 10, a[2] := 20, a[3] := 30, a[4] := 40
Print Format("Int32[4]: [{}, {}, {}, {}] -- {} bytes, Length={}`n",
    a[1], a[2], a[3], a[4], a.Size, a.Length)
Print Format("  a[-1] = {} (negative indexing)`n", a[-1])

; Float array
f := Float64[3]()
f[1] := 3.14159, f[2] := 2.71828, f[3] := 1.41421
Print Format("Float64[3]: [{}, {}, {}] -- {} bytes`n", f[1], f[2], f[3], f.Size)

; Struct arrays
Struct POINT {
    x: i32
    y: i32
}
pa := POINT[3]()
pa[1].x := 10,  pa[1].y := 20
pa[2].x := 100, pa[2].y := 200
pa[3].x := 50,  pa[3].y := 150
Print Format("POINT[3]: {} bytes`n", pa.Size)
loop pa.Length
    Print Format("  [{1}] = ({2}, {3})`n", A_Index, pa[A_Index].x, pa[A_Index].y)

; Byte buffer
h := UInt8[32]()
loop 32
    h[A_Index] := Mod(A_Index * 17, 256)
Print "UInt8[32]: "
loop 8
    Print Format("{:02X} ", h[A_Index])
Print Format("... ({} bytes)`n", h.Size)

; Size fix -- returns struct layout size, not allocated size
Struct SmallPair {
    a: u8
    b: u8
}
s := SmallPair()
s.a := 0xFF, s.b := 0x42
Print Format("SmallPair(0x{:02X}, 0x{:02X}) -- Size={} bytes`n", s.a, s.b, s.Size)

; RGBQUAD color palette using struct arrays
Struct RGBQUAD {
    blue: u8
    green: u8
    red: u8
    reserved: u8
}
pal := RGBQUAD[256]()
loop 256
    pal[A_Index].red := pal[A_Index].green := pal[A_Index].blue := A_Index - 1
Print Format("RGBQUAD[256]: {} bytes`n", pal.Size)
Print Format("  [1]=RGB({1},{1},{1})  [128]=RGB({2},{2},{2})  [256]=RGB({3},{3},{3})`n",
    pal[1].red, pal[128].red, pal[256].red)
