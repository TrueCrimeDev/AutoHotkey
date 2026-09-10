/*
struct_at_showcase.ahk — Everything interesting about Struct.At()

`StructClass.At(ptr)` returns a zero-copy *view* into memory the caller
already owns. No allocation, no byte copy — the view is just a window
onto bytes that live somewhere else (Buffer, another struct, a Win32
lParam, a DllCall output, even another view's pointer).

That single primitive enables a lot of patterns. This file shows them.

Run: bin\AutoHotkey64.exe examples\struct_at_showcase.ahk
*/
#Requires AutoHotkey v2.1-alpha.26

stdout := FileOpen("*", "w", "UTF-8")
Print(text) => stdout.Write(text)
Hr(label) {
    bar := ""
    loop Max(0, 60 - StrLen(label))
        bar .= "─"
    Print Format("`n── {} {}`n", label, bar)
}


; ─── Common struct definitions ──────────────────────────────────────────────

Struct POINT {
    x: Int32, y: Int32
}
Struct RECT {
    left: Int32, top: Int32, right: Int32, bottom: Int32
}
Struct RGBA {
    r: UInt8, g: UInt8, b: UInt8, a: UInt8
}
Struct PACKED_U32 {
    value: UInt32
}


; ─── 1. The basic move: view a struct at an existing pointer ────────────────
; You have raw bytes (from NumPut, an API, a file, anything). You want
; to read them as a struct without copying. .At() hands you a window.

Hr("1. zero-copy view")

buf := Buffer(8)
NumPut("Int", 1920, "Int", 1080, buf)

view := POINT.At(buf.Ptr)
Print Format("buf at 0x{:X}  view.x={} view.y={}`n", buf.Ptr, view.x, view.y)
Print Format("view.Ptr == buf.Ptr ?  {}`n", view.Ptr = buf.Ptr ? "yes" : "no")


; ─── 2. Write-through: mutating the view mutates the source ─────────────────
; The view isn't a snapshot — it's an alias. Writes go straight through.

Hr("2. write-through aliasing")

view.x := -1
Print Format("After view.x := -1   NumGet(buf,0,'Int') = {}`n", NumGet(buf, 0, "Int"))
Print Format("                     view.x             = {}`n", view.x)


; ─── 3. Walk a buffer as an array of structs (cursor pattern) ───────────────
; .At() + pointer arithmetic = iterate any contiguous block, even one
; you didn't allocate as a typed array.

Hr("3. cursor walk over a raw buffer")

raw    := Buffer(POINT().Size * 4)
stride := POINT().Size
NumPut("Int", 10, "Int", 20,  raw, 0 * stride)
NumPut("Int", 30, "Int", 40,  raw, 1 * stride)
NumPut("Int", 50, "Int", 60,  raw, 2 * stride)
NumPut("Int", 70, "Int", 80,  raw, 3 * stride)

loop 4 {
    p := POINT.At(raw.Ptr + (A_Index - 1) * stride)
    Print Format("  point[{}] = ({:3}, {:3})`n", A_Index, p.x, p.y)
}


; ─── 4. Type punning: view the same bytes as different structs ──────────────
; Same 4 bytes, two interpretations. Useful for color packing,
; network byte fiddling, or any "reinterpret_cast" situation.

Hr("4. reinterpret the same bytes")

color := PACKED_U32()
color.value := 0x80FF8040

px := RGBA.At(color.Ptr)
Print Format("packed   value = 0x{:08X}`n", color.value)
Print Format("as RGBA   r={:3}  g={:3}  b={:3}  a={:3}`n", px.r, px.g, px.b, px.a)

px.r := 0xFF
Print Format("after px.r := 0xFF   packed = 0x{:08X}`n", color.value)


; ─── 5. Overlay: view a sub-region inside a bigger struct ───────────────────
; A RECT is just two POINTs back-to-back. .At() at the right offset
; lets you reuse smaller struct types over slices of bigger ones.

Hr("5. sub-struct overlay")

rc := RECT()
rc.left := 5, rc.top := 10, rc.right := 200, rc.bottom := 150

topLeft     := POINT.At(rc.Ptr)
bottomRight := POINT.At(rc.Ptr + 8)
Print Format("RECT   topLeft=({},{})  bottomRight=({},{})`n",
    topLeft.x, topLeft.y, bottomRight.x, bottomRight.y)

bottomRight.x := 999
Print Format("after bottomRight.x := 999   rc.right = {}`n", rc.right)


; ─── 6. Two-stage Win32 dispatch: peek the header, then upgrade the view ────
; Classic WM_NOTIFY pattern. lParam points to "some NMxxx struct" that
; always *starts* with NMHDR. View it as NMHDR first, branch on .code,
; then re-view the SAME pointer as the specific struct.

Hr("6. peek-then-upgrade dispatch")

Struct NMHDR {
    hwndFrom: IntPtr, idFrom: IntPtr, code: Int32
}
Struct NMCUSTOMDRAW {
    hdr: NMHDR
    dwDrawStage: UInt32
    hdc: IntPtr
    rc: RECT
    dwItemSpec: IntPtr
    uItemState: UInt32
    lItemlParam: IntPtr
}

NM_CUSTOMDRAW := -12

fakeLParam := Buffer(NMCUSTOMDRAW().Size, 0)
nm := NMCUSTOMDRAW.At(fakeLParam.Ptr)
nm.hdr.hwndFrom := 0xCAFE, nm.hdr.idFrom := 7, nm.hdr.code := NM_CUSTOMDRAW
nm.dwDrawStage  := 0x1
nm.rc.left := 0, nm.rc.top := 0, nm.rc.right := 80, nm.rc.bottom := 24

Dispatch(lParam) {
    hdr := NMHDR.At(lParam)
    if (hdr.code = -12) {
        cd := NMCUSTOMDRAW.At(lParam)
        Print Format("  CUSTOMDRAW from hwnd=0x{:X} stage={} rect={}x{}`n",
            cd.hdr.hwndFrom, cd.dwDrawStage,
            cd.rc.right - cd.rc.left, cd.rc.bottom - cd.rc.top)
    } else {
        Print Format("  unhandled code={}`n", hdr.code)
    }
}
Dispatch(fakeLParam.Ptr)


; ─── 7. Fixed-slot arena / object pool ──────────────────────────────────────
; One Buffer() up front, .At() carves it into N slots on demand.
; No GC churn, contiguous memory, friendly to caches and to DllCall.

Hr("7. arena allocator")

Struct Particle {
    x: Float32, y: Float32, vx: Float32, vy: Float32, life: Float32, _pad: UInt32
}

class ParticlePool {
    __New(capacity) {
        this.cap   := capacity
        this.slot  := Particle().Size
        this.mem   := Buffer(this.slot * capacity, 0)
        this.count := 0
    }
    Spawn(x, y, vx, vy, life) {
        if (this.count >= this.cap)
            throw Error("pool full")
        p := Particle.At(this.mem.Ptr + this.count * this.slot)
        p.x := x, p.y := y, p.vx := vx, p.vy := vy, p.life := life
        this.count += 1
        return p
    }
    At(i) => Particle.At(this.mem.Ptr + (i - 1) * this.slot)
}

pool := ParticlePool(1000)
pool.Spawn( 100,  50, 1.5, -0.5, 2.0)
pool.Spawn( 200, 120, 0.8,  1.2, 1.5)
pool.Spawn(-40, 300, 3.0,  0.0, 0.4)

loop pool.count {
    p := pool.At(A_Index)
    Print Format("  particle[{}] pos=({:+.1f},{:+.1f}) vel=({:+.1f},{:+.1f}) life={:.2f}`n",
        A_Index, p.x, p.y, p.vx, p.vy, p.life)
}
Print Format("  one allocation, {} slots, {} bytes total`n", pool.cap, pool.mem.Size)


; ─── 8. Byte-level inspection via a typed-array .At() ───────────────────────
; Numeric types expose .At() through the [N] form, so a UInt8[16] window
; over any pointer lets you dump raw bytes for layout/debug work.

Hr("8. byte-level inspection")

probe := Buffer(16, 0)
NumPut("UInt", 0xDEADBEEF, "UInt", 0xCAFEBABE, "UShort", 0x1234, probe)
view16 := UInt8[16].At(probe.Ptr)
Print "  hex: "
loop 16
    Print Format("{:02X}{}", view16[A_Index], A_Index = 8 ? "  " : " ")
Print "`n"


; ─── 9. Stable "handle": store the Ptr, recreate the view on demand ─────────
; Views are cheap. Ptrs are 8 bytes. Pass a Ptr around like a handle and
; hydrate the view wherever you need typed access. The bytes don't move.

Hr("9. ptr-as-handle")

GetCursorHandle() {
    pt := POINT()
    DllCall("GetCursorPos", "Ptr", pt)
    return { ptr: pt.Ptr, _keepalive: pt }
}

ReadCursor(h) {
    p := POINT.At(h.ptr)
    return Format("({}, {})", p.x, p.y)
}

handle := GetCursorHandle()
Print Format("  cursor (via handle) = {}`n", ReadCursor(handle))
;  Important: _keepalive holds the owning struct so its bytes persist.
;  .At() does NOT extend lifetime — drop the source and the Ptr dangles.


; ─── 10. Byte-swap a UInt32 by viewing it as 4 bytes ───────────────────────────
; Endian fiddling without bitshifts: alias a UInt32 as a UInt8[4] view, swap
; in place. Same bytes, different field labels.

Hr("10. endian flip via aliasing")

n := PACKED_U32()
n.value := 0x11223344
bytes := UInt8[4].At(n.Ptr)
Print Format("  before: 0x{:08X}  bytes={:02X} {:02X} {:02X} {:02X}`n",
    n.value, bytes[1], bytes[2], bytes[3], bytes[4])

t := bytes[1], bytes[1] := bytes[4], bytes[4] := t
t := bytes[2], bytes[2] := bytes[3], bytes[3] := t

Print Format("  after:  0x{:08X}  bytes={:02X} {:02X} {:02X} {:02X}`n",
    n.value, bytes[1], bytes[2], bytes[3], bytes[4])


; ─── Recap ──────────────────────────────────────────────────────────────────

Hr("recap")
Print "  .At(ptr) is a zero-cost cast from 'raw bytes I already own' to`n"
Print "  'typed struct view'. It composes with everything: pointer math,`n"
Print "  nested structs, typed arrays, DllCall outputs, Win32 callbacks.`n`n"
Print "  Three rules to remember:`n"
Print "    - The view aliases — writes are visible everywhere.`n"
Print "    - The view does NOT own — keep the source alive.`n"
Print "    - The view is free — make as many as you like.`n"
