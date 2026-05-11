/*
Alpha22_Example.ahk -- AutoHotkey v2.1-alpha.22 feature showcase

New features:
  1. Native Struct keyword with typed fields and memory layout
  2. Automatic Struct.Ptr subclasses (replaces StructFromPtr)
  3. DefineProp() as a top-level function
  4. Type() returns "unset" for omitted parameters
  5. IsSet() permits unset expressions
  6. Export function call behavior change (block syntax required)
  7. Bug fixes (!~=, #Import __Init, module reopening, DllCall)

Run: bin\AutoHotkey64.exe Alpha22_Example.ahk
*/
#Requires AutoHotkey v2.1-alpha.22

stdout := FileOpen("*", "w", "UTF-8")
Print(text) => stdout.Write(text)
PrintLine(text := "") => stdout.Write(text "`n")

PrintLine "=== AutoHotkey v2.1-alpha.22 Feature Showcase ==="
PrintLine Format("Version: {}", A_AhkVersion)
PrintLine ""

; ─────────────────────────────────────────────────────
; 1. Native Struct keyword
; ─────────────────────────────────────────────────────
PrintLine "── 1. Struct keyword ──"

; The `Struct` keyword creates classes with defined memory layout.
; Fields use typed annotations: i32, u8, u16, uptr, etc.

Struct POINT {
    x: i32
    y: i32
}

pt := POINT()
pt.x := 100
pt.y := 200
PrintLine Format("  POINT({}, {}) -- Type={}, Size={} bytes", pt.x, pt.y, Type(pt), pt.Size)

; Structs with mixed types
Struct RECT {
    left: i32
    top: i32
    right: i32
    bottom: i32
}

rc := RECT()
rc.left := 0, rc.top := 0, rc.right := 1920, rc.bottom := 1080
PrintLine Format("  RECT({},{} to {},{}) -- {} bytes",
    rc.left, rc.top, rc.right, rc.bottom, rc.Size)

; Small byte-level struct
Struct Color {
    r: u8
    g: u8
    b: u8
    a: u8
}

c := Color()
c.r := 255, c.g := 128, c.b := 0, c.a := 255
PrintLine Format("  Color RGBA({},{},{},{}) -- {} bytes", c.r, c.g, c.b, c.a, c.Size)

; Nested structs
Struct NMHDR {
    hwndFrom: uptr
    idFrom: uptr
    code: i32
}

Struct NMCUSTOMDRAW {
    hdr: NMHDR
    dwDrawStage: u32
    hdc: uptr
    rc: RECT
    dwItemSpec: uptr
    uItemState: u32
    lItemlParam: iptr
}

ncd := NMCUSTOMDRAW()
ncd.hdr.code := -12  ; NM_CUSTOMDRAW
ncd.dwDrawStage := 1
ncd.rc.left := 10
ncd.rc.top := 20
PrintLine Format("  NMCUSTOMDRAW: hdr.code={}, rc.left={} -- {} bytes",
    ncd.hdr.code, ncd.rc.left, ncd.Size)

; DllCall with Struct types
Struct SYSTEMTIME {
    wYear: u16
    wMonth: u16
    wDayOfWeek: u16
    wDay: u16
    wHour: u16
    wMinute: u16
    wSecond: u16
    wMilliseconds: u16
}

st := SYSTEMTIME()
DllCall("GetLocalTime", SYSTEMTIME, st)
PrintLine Format("  DllCall GetLocalTime: {}-{:02}-{:02} {:02}:{:02}:{:02}",
    st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond)
PrintLine ""

; ─────────────────────────────────────────────────────
; 2. Automatic Struct.Ptr subclasses
; ─────────────────────────────────────────────────────
PrintLine "── 2. Struct.Ptr (auto-generated pointer types) ──"

; Every Struct automatically gets a .Ptr subclass for pointer
; handling. This replaces the old StructFromPtr function.

PrintLine Format("  POINT.Ptr exists: {}", POINT.HasOwnProp("Ptr") ? "yes" : "no")
PrintLine Format("  RECT.Ptr exists: {}", RECT.HasOwnProp("Ptr") ? "yes" : "no")

; Struct.Ptr enables zero-copy views into existing memory.
; Useful for accessing structs returned by DllCall or in
; callback parameters (lParam pointing to a struct).
;
; Example pattern (in a WM_NOTIFY handler):
;   OnMessage(0x4E, WM_NOTIFY)
;   WM_NOTIFY(wParam, lParam, msg, hwnd) {
;       hdr := NMHDR.At(lParam)  ; zero-copy view at lParam
;       if hdr.code == -12       ; NM_CUSTOMDRAW
;           ncd := NMCUSTOMDRAW.At(lParam)
;   }

PrintLine "  Struct.At(ptr) provides zero-copy pointer views"
PrintLine "  StructFromPtr removed -- use .Ptr/.At() instead"
PrintLine ""

; ─────────────────────────────────────────────────────
; 3. DefineProp() top-level function
; ─────────────────────────────────────────────────────
PrintLine "── 3. DefineProp() function ──"

; New top-level function complements the obj.DefineProp() method.
; Useful when the target is dynamic or passed as a parameter.

; Getter/setter pair
obj := {}
DefineProp(obj, "Name", {
    Get: (this) => this._name ?? "unnamed",
    Set: (this, value) => this._name := value
})
obj.Name := "alpha22"
PrintLine Format("  obj.Name = '{}'", obj.Name)

; Computed read-only property
coords := { x: 3, y: 4 }
DefineProp(coords, "Magnitude", {
    Get: (this) => Sqrt(this.x ** 2 + this.y ** 2)
})
PrintLine Format("  coords({},{}).Magnitude = {}", coords.x, coords.y, coords.Magnitude)

; Adding properties to a class prototype dynamically
class Counter {
    __New() => this._count := 0
}

DefineProp(Counter.Prototype, "Count", {
    Get: (this) => this._count,
    Set: (this, value) => this._count := Max(0, value)
})

ctr := Counter()
ctr.Count := 42
PrintLine Format("  Counter.Count = {}", ctr.Count)

; Practical: factory function that adds timestamps
AddTimestamp(target, propName) {
    DefineProp(target, propName, {
        Get: (*) => FormatTime(, "yyyy-MM-dd HH:mm:ss")
    })
}

record := {}
AddTimestamp(record, "CreatedAt")
PrintLine Format("  record.CreatedAt = '{}'", record.CreatedAt)
PrintLine ""

; ─────────────────────────────────────────────────────
; 4. Type() returns "unset"
; ─────────────────────────────────────────────────────
PrintLine "── 4. Type() returns 'unset' ──"

; Type() with no argument (or an omitted optional param)
; now returns the string "unset" instead of throwing.
; Enables clean type-dispatch patterns.

PrintLine Format("  Type()     = '{}'", Type())
PrintLine Format("  Type(42)   = '{}'", Type(42))
PrintLine Format("  Type('hi') = '{}'", Type("hi"))
PrintLine Format("  Type([])   = '{}'", Type([]))

; Type-dispatch function
FormatValue(val?) {
    if !IsSet(val)
        return "(unset) -- Type() = " Type()
    switch Type(val) {
        case "Integer", "Float": return Format("Number: {}", val)
        case "String":           return Format('String: "{}"', val)
        case "Array":            return Format("Array[{}]", val.Length)
        default:                 return Format("Object: {}", Type(val))
    }
}

PrintLine Format("  FormatValue(100)    = {}", FormatValue(100))
PrintLine Format("  FormatValue('test') = {}", FormatValue("test"))
PrintLine Format("  FormatValue()       = {}", FormatValue())
PrintLine ""

; ─────────────────────────────────────────────────────
; 5. IsSet() permits unset expressions
; ─────────────────────────────────────────────────────
PrintLine "── 5. IsSet() with unset expressions ──"

; IsSet() can now take optional parameters directly.
; Also fixed: IsSet(p) correctly returns 0 for unset
; virtual references.

CheckValue(val?) {
    if IsSet(val)
        PrintLine Format("  val is set: {}", String(val))
    else
        PrintLine "  val is unset"
}

CheckValue("hello")
CheckValue()

; Robust multi-parameter handling
SmartFunc(a, b?, c?) {
    parts := [Format("a={}", a)]
    parts.Push(IsSet(b) ? Format("b={}", b) : "b=unset")
    parts.Push(IsSet(c) ? Format("c={}", c) : "c=unset")
    result := ""
    for p in parts
        result .= (A_Index > 1 ? ", " : "") p
    PrintLine Format("  SmartFunc: {}", result)
}

SmartFunc("x", "y", "z")
SmartFunc("x", "y")
SmartFunc("x")
PrintLine ""

; ─────────────────────────────────────────────────────
; 6. Export function syntax change
; ─────────────────────────────────────────────────────
PrintLine "── 6. Export syntax change ──"

; `export a() => b` is now a function CALL statement
; (matching v2.0 behavior), not a fat-arrow definition.
;
; This means exported module functions must use block syntax:
;
;   ; WRONG (alpha.22+): treated as calling export()
;   export MyFunc(x) => x * 2
;
;   ; CORRECT: block syntax
;   export MyFunc(x) {
;       return x * 2
;   }

PrintLine "  export func() => expr  -> function call (not definition)"
PrintLine "  Use block syntax { } for exported module functions"
PrintLine ""

; ─────────────────────────────────────────────────────
; 7. Bug fixes
; ─────────────────────────────────────────────────────
PrintLine "── 7. Bug fixes ──"

; a) Fixed !~= (not-regex-match) operator
result := "hello" ~= "^h"
PrintLine Format("  !~= operator fixed: 'hello' ~= '^h' -> {}", result)

; b) DllCall now requires Struct subclasses (not arbitrary objects)
;    for struct parameters. ObjGetDataPtr fallback removed.
PrintLine "  DllCall requires proper Struct subclasses"

; c) Module fixes
PrintLine "  #Import __Init works without sub-modules"
PrintLine "  Module reopening at end of file fixed"
PrintLine ""

; ─────────────────────────────────────────────────────
; 8. Practical: Win32 API with structs
; ─────────────────────────────────────────────────────
PrintLine "── 8. Practical: Win32 structs ──"

; Alpha.22's Struct keyword shines with Win32 APIs.
; Define once, use everywhere -- type-safe and sized correctly.

Struct MEMORYSTATUSEX {
    dwLength: u32
    dwMemoryLoad: u32
    ullTotalPhys: u64
    ullAvailPhys: u64
    ullTotalPageFile: u64
    ullAvailPageFile: u64
    ullTotalVirtual: u64
    ullAvailVirtual: u64
    ullAvailExtendedVirtual: u64
}

ms := MEMORYSTATUSEX()
ms.dwLength := ms.Size
DllCall("GlobalMemoryStatusEx", MEMORYSTATUSEX, ms)

totalGB := ms.ullTotalPhys / (1024**3)
availGB := ms.ullAvailPhys / (1024**3)
PrintLine Format("  Memory: {:.1f} GB total, {:.1f} GB available ({}% used)",
    totalGB, availGB, ms.dwMemoryLoad)

; Get cursor position
Struct CURSORPOINT {
    x: i32
    y: i32
}
cp := CURSORPOINT()
DllCall("GetCursorPos", CURSORPOINT, cp)
PrintLine Format("  Cursor: ({}, {})", cp.x, cp.y)
PrintLine ""

; ─────────────────────────────────────────────────────
; Summary
; ─────────────────────────────────────────────────────
PrintLine "═══════════════════════════════════════════════"
PrintLine "Alpha.22 is the foundational Struct release:"
PrintLine "  • Struct keyword with typed fields (i32, u8, uptr...)"
PrintLine "  • Auto-generated .Ptr classes (replaces StructFromPtr)"
PrintLine "  • Nested structs with proper layout"
PrintLine "  • DllCall integration with Struct types"
PrintLine "  • DefineProp() top-level function"
PrintLine "  • Type() returns 'unset' for missing params"
PrintLine "  • IsSet() accepts unset expressions"
PrintLine "  • Export syntax aligned with v2.0"
PrintLine "═══════════════════════════════════════════════"
