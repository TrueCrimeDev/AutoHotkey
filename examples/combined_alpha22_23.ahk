/*
combined_alpha22_23.ahk — Practical examples of v2.1-alpha.22 + alpha.23 features

alpha.22: Struct, Struct.At(ptr), DefineProp(), Type() "unset", IsSet(expr)
alpha.23: Numeric types (Int32, Float32...), StructClass[N], Size fix
  2.0.22: File I/O flush on exit (used implicitly by stdout)
*/
#Requires AutoHotkey v2.1-alpha.26

stdout := FileOpen("*", "w", "UTF-8")
Print(text) => stdout.Write(text)

; ─── 1. Win32 structs with numeric types ─────────────────────────────────────
; Real RECT/POINT for DllCall — no more Buffer+NumPut

Struct RECT {
    left: Int32, top: Int32, right: Int32, bottom: Int32
}
Struct POINT {
    x: Int32
    y: Int32
}

; Get cursor position via DllCall + struct
pt := POINT()
DllCall("GetCursorPos", "Ptr", pt)
Print Format("Cursor: ({}, {})`n", pt.x, pt.y)

; Get desktop work area
rc := RECT()
DllCall("SystemParametersInfo", "UInt", 0x30, "UInt", 0, "Ptr", rc, "UInt", 0)  ; SPI_GETWORKAREA
Print Format("Work area: {}x{} (left={}, top={}, right={}, bottom={})`n",
    rc.right - rc.left, rc.bottom - rc.top, rc.left, rc.top, rc.right, rc.bottom)

; ─── 2. Struct.At(ptr) — zero-copy view into existing memory ─────────────────
; Read POINT back from raw pointer (simulates reading callback/API data)

buf := Buffer(8)
NumPut("Int", 1920, "Int", 1080, buf)
view := POINT.At(buf.Ptr)
Print Format("POINT.At(buf): ({}, {}) — no copy, same memory`n", view.x, view.y)

; ─── 3. Struct arrays for bulk API data ───────────────────────────────────────
; POINT[N] — contiguous array, perfect for DllCall that fills arrays

Struct MONITORINFO {
    cbSize: UInt32
    rcMonitor: RECT
    rcWork: RECT
    dwFlags: UInt32
}

; Typed array as a pixel buffer (e.g., for GDI operations)
Struct RGBQUAD {
    b: UInt8, g: UInt8, r: UInt8, a: UInt8
}
pixels := RGBQUAD[8]()
loop 8 {
    c := (A_Index - 1) * 36        ; gradient 0..252
    pixels[A_Index].r := c
    pixels[A_Index].g := 255 - c
    pixels[A_Index].b := 128
}
Print "Gradient: "
loop 8
    Print Format("#{:02X}{:02X}{:02X} ", pixels[A_Index].r, pixels[A_Index].g, pixels[A_Index].b)
Print "`n"

; ─── 4. Numeric arrays for math/signal processing ────────────────────────────
; Float64[N] — typed array, fixed-size, contiguous memory

samples := Float64[8]()
loop 8
    samples[A_Index] := Sin(A_Index * 0.7854)  ; π/4 increments
Print "Sin wave: "
loop 8
    Print Format("{:+.3f} ", samples[A_Index])
Print Format("({} bytes)`n", samples.Size)

; Running average with Int32 array
temps := Int32[5]()
temps[1] := 22, temps[2] := 24, temps[3] := 19, temps[4] := 21, temps[5] := 23
sum := 0
loop temps.Length
    sum += temps[A_Index]
Print Format("Temps avg: {:.1f}°C`n", sum / temps.Length)

; ─── 5. Binary protocol / file format parsing ────────────────────────────────
; Struct for a custom packet header + byte payload

Struct PacketHeader {
    magic: UInt16
    version: UInt8
    flags: UInt8
    length: UInt32
    checksum: UInt32
}

pkt := PacketHeader()
pkt.magic := 0xCAFE, pkt.version := 3, pkt.flags := 0x01, pkt.length := 256
pkt.checksum := 0xDEADBEEF
Print Format("Packet: magic=0x{:04X} v{} flags=0x{:02X} len={} chk=0x{:08X} ({} bytes)`n",
    pkt.magic, pkt.version, pkt.flags, pkt.length, pkt.checksum, pkt.Size)

; UInt8 byte buffer for payload
payload := UInt8[16]()
loop 16
    payload[A_Index] := Mod(A_Index * 0x37, 256)
Print "Payload: "
loop 16
    Print Format("{:02X}", payload[A_Index])
Print "`n"

; ─── 6. DefineProp — extend prototypes you don't own ─────────────────────────
; Add .ToHex() to Integer prototype

DefineProp(Integer.Prototype, "ToHex", {
    Call: (this, width := 0) => width ? Format("0x{:0" width "X}", this) : Format("0x{:X}", this)
})
Print Format("255.ToHex()={} 255.ToHex(4)={}`n", (255).ToHex(), (255).ToHex(4))

; Add .Clamp() to Float/Integer
for proto in [Integer.Prototype, Float.Prototype]
    DefineProp(proto, "Clamp", {
        Call: (this, lo, hi) => Min(Max(this, lo), hi)
    })
Print Format("Clamp: (-5).Clamp(0,100)={}  (150.7).Clamp(0,100)={}`n",
    (-5).Clamp(0, 100), (150.7).Clamp(0, 100))

; ─── 7. Type() "unset" + IsSet(expr) — cleaner optional params ───────────────

LogEvent(msg, level?, data?) {
    parts := Format("[{}]", Type(level?) = "unset" ? "INFO" : level)
    parts .= " " msg
    if IsSet(data)
        parts .= " | data=" data
    Print parts "`n"
}
LogEvent("Server started")
LogEvent("Connection failed", "ERROR")
LogEvent("Request received", "DEBUG", '{"path":"/api"}')

; IsSet with expression — no assignment needed
ValidateConfig(host?, port?) {
    missing := []
    if !IsSet(host) ; alpha.22: no assignment needed
        missing.Push("host")
    if !IsSet(port)
        missing.Push("port")
    if missing.Length
        Print Format("Missing config: {}`n", Join(", ", missing*))
    else
        Print Format("Config OK: {}:{}`n", host, port)
}

Join(sep, items*) {
    s := ""
    for item in items
        s .= (A_Index > 1 ? sep : "") . item
    return s
}
ValidateConfig()
ValidateConfig("localhost", 8080)

; ─── 8. Struct.Ptr auto-class + DllCall ───────────────────────────────────────
; Struct.Ptr is auto-generated — use directly in DllCall type signatures

Struct SYSTEM_INFO {
    wProcessorArchitecture: UInt16
    wReserved: UInt16
    dwPageSize: UInt32
    lpMinAppAddress: IntPtr
    lpMaxAppAddress: IntPtr
    dwActiveProcessorMask: IntPtr
    dwNumberOfProcessors: UInt32
    dwProcessorType: UInt32
    dwAllocationGranularity: UInt32
    wProcessorLevel: UInt16
    wProcessorRevision: UInt16
}

si := SYSTEM_INFO()
DllCall("GetSystemInfo", "Ptr", si)
Print Format("CPU: {} cores, page={}KB, arch={}`n",
    si.dwNumberOfProcessors, si.dwPageSize // 1024,
    si.wProcessorArchitecture = 9 ? "x64" : si.wProcessorArchitecture = 12 ? "ARM64" : "other")

; ─── 9. Nested structs + Struct.At for callback data ─────────────────────────

Struct NMHDR {
    hwndFrom: IntPtr
    idFrom: IntPtr
    code: Int32
}

; Simulate reading a WM_NOTIFY lParam — write raw bytes, read as struct
hdr := NMHDR()
NumPut("UPtr", 0x12345, "UPtr", 100, "Int", -12, hdr)
Print Format("NMHDR: hwnd=0x{:X} id={} code={} ({} bytes)`n",
    hdr.hwndFrom, hdr.idFrom, hdr.code, hdr.Size)

; Struct.At — zero-copy view of same memory
hdr2 := NMHDR.At(hdr.Ptr)
Print Format("NMHDR.At: hwnd=0x{:X} id={} code={} — same memory`n",
    hdr2.hwndFrom, hdr2.idFrom, hdr2.code)

; ─── 10. Size fix demo — layout size vs allocation size ───────────────────────

Struct Tiny {
    a: UInt8
}

Struct Pair {
    a: UInt8, b: UInt8
}

Struct Triple {
    a: UInt8, b: UInt8, c: UInt8
}

Struct Mixed {
    flag: UInt8
    value: Float64  ; padding between UInt8 and Float64
}

Print Format("Sizes: Tiny={} Pair={} Triple={} Mixed={}`n",
    Tiny().Size, Pair().Size, Triple().Size, Mixed().Size)
