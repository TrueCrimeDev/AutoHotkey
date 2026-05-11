/*
struct_arrays_demo.ahk — Struct arrays in AHK v2.1-alpha

Demonstrates:
  - Struct keyword with typed fields (alpha.22)
  - StructClass[N] fixed-size arrays (alpha.23)
  - Struct.At() zero-copy pointer views (alpha.22)
  - Negative indexing on struct arrays (alpha.23)
  - DefineProp to extend struct prototypes (alpha.22)
  - Nested structs in arrays

Run: bin\AutoHotkey64.exe examples\struct_arrays_demo.ahk
See also: typed_dllcall_demo.ahk — type classes in DllCall (old vs new)
*/
#Requires AutoHotkey v2.1-alpha.23

; 1. Basic numeric arrays

; Int32[N] creates a fixed-size contiguous array of 32-bit integers
scores := Int32[5]()
scores[1] := 92, scores[2] := 87, scores[3] := 95, scores[4] := 78, scores[5] := 88

sum := 0
loop scores.Length
    sum += scores[A_Index]

; scores[1]           => 92
; scores.Length        => 5
; scores.Size          => 20 (bytes)
; sum / scores.Length  => 88.0

; Float64 array — good for scientific data
readings := Float64[4]()
readings[1] := 3.14159, readings[2] := 2.71828, readings[3] := 1.61803, readings[4] := 1.41421

; readings[1]  => 3.14159
; readings[4]  => 1.41421

; Negative indexing — access from the end
; scores[-1]   => 88
; scores[-2]   => 78


; 2. Struct arrays — contiguous array of structs

Struct Enemy {
    x: Float32
    y: Float32
    hp: i32
    speed: Float32
}

; Create a fixed array of 4 enemies
enemies := Enemy[4]()
enemies[1].x := 100, enemies[1].y := 50,  enemies[1].hp := 100, enemies[1].speed := 2.5
enemies[2].x := 300, enemies[2].y := 120, enemies[2].hp := 75,  enemies[2].speed := 3.0
enemies[3].x := 180, enemies[3].y := 200, enemies[3].hp := 150, enemies[3].speed := 1.5
enemies[4].x := 400, enemies[4].y := 80,  enemies[4].hp := 50,  enemies[4].speed := 4.0

; enemies.Size         => 64 (bytes total)
; Enemy().Size         => 16 (per enemy)
; enemies[2].x         => 300
; enemies[3].hp        => 150

; Find the fastest enemy
fastest := 1
loop enemies.Length
    if enemies[A_Index].speed > enemies[fastest].speed
        fastest := A_Index

; fastest                => 4
; enemies[fastest].speed => 4.0


; 3. Nested structs in arrays

Struct Vec2 {
    x: Float32
    y: Float32
}

Struct Waypoint {
    pos: Vec2
    radius: Float32
    wait_time: Float32
}

path := Waypoint[3]()
path[1].pos.x := 0,   path[1].pos.y := 0,   path[1].radius := 10, path[1].wait_time := 0.0
path[2].pos.x := 100, path[2].pos.y := 200, path[2].radius := 20, path[2].wait_time := 1.5
path[3].pos.x := 400, path[3].pos.y := 50,  path[3].radius := 15, path[3].wait_time := 0.5

; path.Size          => 48
; path[2].pos.x      => 100
; path[2].pos.y      => 200
; path[3].wait_time  => 0.5

; Calculate total path distance
totalDist := 0.0
loop path.Length - 1 {
    dx := path[A_Index + 1].pos.x - path[A_Index].pos.x
    dy := path[A_Index + 1].pos.y - path[A_Index].pos.y
    totalDist += Sqrt(dx * dx + dy * dy)
}

; totalDist  => 559.0


; 4. Byte buffers with UInt8[N]

; UInt8[N] works like a typed byte array
packet := UInt8[12]()
packet[1] := 0xCA, packet[2] := 0xFE  ; magic bytes
packet[3] := 0x01                       ; version
packet[4] := 8                          ; payload length
loop 8
    packet[4 + A_Index] := A_Index * 11 ; payload

; packet.Size  => 12
; packet[1]    => 202 (0xCA)
; packet[2]    => 254 (0xFE)
; packet[5]    => 11
; packet[12]   => 88


; 5. Struct.At() — pointer views into arrays

Struct POINT {
    x: i32
    y: i32
}

; Allocate raw buffer and read it as a POINT array
buf := Buffer(POINT().Size * 3)
NumPut("Int", 10, "Int", 20, "Int", 30, "Int", 40, "Int", 50, "Int", 60, buf)

; Read each POINT from the buffer using zero-copy views
stride := POINT().Size  ; => 8

p1 := POINT.At(buf.Ptr)
; p1.x  => 10
; p1.y  => 20

p2 := POINT.At(buf.Ptr + stride)
; p2.x  => 30
; p2.y  => 40

p3 := POINT.At(buf.Ptr + stride * 2)
; p3.x  => 50
; p3.y  => 60

; Write through the view — modifies the underlying buffer
p1.x := 999
; NumGet(buf, 0, "Int")  => 999 (same memory)


; 6. Extend struct arrays with DefineProp

Struct Measurement {
    value: Float64
    timestamp: i64
}

; Add a display method to the struct prototype
DefineProp(Measurement.Prototype, "Display", {
    Call: (this) => Format("{:.2f} @{}", this.value, this.timestamp)
})

data := Measurement[3]()
data[1].value := 23.45, data[1].timestamp := 1000
data[2].value := 24.10, data[2].timestamp := 2000
data[3].value := 22.89, data[3].timestamp := 3000

; data[1].Display()  => "23.45 @1000"
; data[2].Display()  => "24.10 @2000"
; data[3].Display()  => "22.89 @3000"


; 7. Practical: DllCall with struct array

Struct CURSORPOS {
    x: i32
    y: i32
}

cp := CURSORPOS()
DllCall("GetCursorPos", "Ptr", cp)

; cp.x  => (current cursor X)
; cp.y  => (current cursor Y)

; Array of points for a polyline triangle (3 vertices + close)
Struct PolyPoint {
    x: i32
    y: i32
}

triangle := PolyPoint[4]()
triangle[1].x := 200, triangle[1].y := 50
triangle[2].x := 350, triangle[2].y := 300
triangle[3].x := 50,  triangle[3].y := 300
triangle[4].x := 200, triangle[4].y := 50   ; close the shape

; triangle.Size    => 32
; triangle.Length  => 4
