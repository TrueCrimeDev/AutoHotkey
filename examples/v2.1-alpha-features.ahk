/*
    AutoHotkey v2.1 Alpha Feature Showcase
    Demonstrates features from alpha.1 through alpha.26 in a single script.
    Run with: AutoHotkey64.exe /ErrorStdOut=utf-8 examples\v2.1-alpha-features.ahk

    Features are grouped by category with the alpha version that introduced them.
*/

section(title) => FileAppend("`n=== " title " ===`n", "*")
out(text)      => FileAppend(text "`n", "*")

; ─────────────────────────────────────────────────────────────────────────────
section("STRUCT (alpha.22)")
; Native typed structures with field declarations
; ─────────────────────────────────────────────────────────────────────────────

; Declaration with typed fields
Struct POINT {
    x: i32
    y: i32
}

; All supported field types: i8, u8, i16, u16, i32, u32, i64, u64, f32, f64, iptr, uptr
Struct AllTypes {
    int8:    i8
    uint8:   u8
    int16:   i16
    uint16:  u16
    int32:   i32
    uint32:  u32
    int64:   i64
    uint64:  u64
    float32: f32
    float64: f64
    intptr:  iptr
    uintptr: uptr
}

; Nested structs
Struct RECT {
    left: i32
    top: i32
    right: i32
    bottom: i32
}

Struct NMHDR {
    hwndFrom: uptr
    idFrom:   uptr
    code:     i32
}

Struct NMCUSTOMDRAW {
    hdr:         NMHDR    ; nested struct
    dwDrawStage: u32
    hdc:         uptr
    rc:          RECT     ; nested struct
    dwItemSpec:  uptr
    uItemState:  u32
    lItemlParam: iptr
}

; Fixed-size byte buffer field
Struct WithBuffer {
    reserved: 32          ; 32-byte inline buffer
}

; --- Instantiation and field access ---
pt := POINT()
pt.x := 100
pt.y := 200
out("Struct instance:    POINT(" pt.x ", " pt.y ")")
out("Type:              " Type(pt))
out("Size (bytes):      " ObjGetDataSize(pt))

; --- Nested field access ---
nm := NMCUSTOMDRAW()
nm.hdr.code := -12
nm.rc.left := 10
nm.rc.right := 500
out("Nested access:     nm.hdr.code=" nm.hdr.code " nm.rc.left=" nm.rc.left)

; --- Struct.At(ptr) — zero-copy pointer view ---
buf := Buffer(8, 0)
NumPut("i32", 42, "i32", 99, buf)
view := POINT.At(buf.Ptr)
out("At() read:         x=" view.x " y=" view.y)
view.x := 777                    ; write-through to underlying memory
out("At() write-through:" NumGet(buf, 0, "i32") " (wrote 777 via struct view)")

; --- Automatic .Ptr subclass ---
out(".Ptr subclass:     " (POINT.HasOwnProp("Ptr") ? "exists" : "missing"))

; --- Struct behavior ---
; - Dot access only (no bracket r["x"])
; - Cannot own arbitrary properties (CannotOwnProps flag)
; - Assignment copies reference, not value: a := b means same object
; - No .Size static property — use ObjGetDataSize(instance) or ObjGetDataSize(Proto.Prototype)
; - Can add methods via DefineProp on Prototype

DefineProp(POINT.Prototype, "Magnitude", {
    Get: (this) => Sqrt(this.x ** 2 + this.y ** 2)
})
pt2 := POINT()
pt2.x := 3
pt2.y := 4
out("Method on Struct:  POINT(3,4).Magnitude = " pt2.Magnitude)


; ─────────────────────────────────────────────────────────────────────────────
section("DEFINEPROP FUNCTION (alpha.22)")
; Top-level function form — cleaner than obj.DefineProp() for external objects
; ─────────────────────────────────────────────────────────────────────────────

obj := {}

; Getter + Setter
DefineProp(obj, "Name", {
    Get: (this) => this._name ?? "unnamed",
    Set: (this, v) => this._name := v
})
obj.Name := "alpha22"
out("DefineProp Get/Set: " obj.Name)

; Computed property
DefineProp(obj, "NameUpper", {
    Get: (this) => StrUpper(this._name ?? "")
})
out("Computed prop:     " obj.NameUpper)

; Read-only property
DefineProp(obj, "Version", {
    Get: (*) => "2.1-alpha.26"
})
out("Read-only prop:    " obj.Version)


; ─────────────────────────────────────────────────────────────────────────────
section("TYPE() RETURNS 'unset' (alpha.22)")
; Type() with no arguments returns "unset"
; ─────────────────────────────────────────────────────────────────────────────

out("Type()    = " Type())             ; "unset"
out("Type(42)  = " Type(42))           ; "Integer"
out('Type("s") = ' Type("hello"))      ; "String"
out("Type([])  = " Type([]))           ; "Array"
out("Type({})  = " Type({}))           ; "Object"

; Practical use: optional parameter dispatch
FormatArg(val?) {
    if !IsSet(val)
        return "(not provided) — Type()=" Type()
    return Type(val) ": " String(val)
}
out("FormatArg(42):     " FormatArg(42))
out("FormatArg():       " FormatArg())


; ─────────────────────────────────────────────────────────────────────────────
section("ISSET WITH EXPRESSIONS (alpha.22)")
; IsSet() now permits unset optional parameters directly
; ─────────────────────────────────────────────────────────────────────────────

TestIsSet(p?) {
    return IsSet(p)    ; works even when p is unset virtual reference
}
out("IsSet(set):   " TestIsSet("hello"))
out("IsSet(unset): " TestIsSet())


; ─────────────────────────────────────────────────────────────────────────────
section("!~= NOT-REGEX OPERATOR (alpha.20, syntax fixed alpha.21/22)")
; Negated regex match: returns true if pattern does NOT match
; ─────────────────────────────────────────────────────────────────────────────

text := "Hello World"
out('"Hello World" !~= "^\d+":  ' (text !~= "^\d+" ? "true (not digits)" : "false"))
out('"12345" !~= "^\d+":        ' ("12345" !~= "^\d+" ? "true" : "false (is digits)"))


; ─────────────────────────────────────────────────────────────────────────────
section("MAYBE / OPTIONAL CHAINING (alpha.2)")
; ?. ?? ??= operators for safe optional access
; ─────────────────────────────────────────────────────────────────────────────

; Maybe operator (?.) — short-circuits to unset if LHS is unset
config := {theme: "dark"}
out("config?.theme:     " (config?.theme ?? "fallback"))

; ?. guards against unset variables, not missing properties
unsetVar := unset
out("unsetVar?.x:       " (unsetVar?.x ?? "safely unset"))

; Or-maybe (??) — default value for unset
GetSetting(key, default?) {
    settings := Map("volume", 80)
    return settings.Get(key, unset) ?? default ?? 0
}
out("volume:            " GetSetting("volume"))
out("brightness:        " GetSetting("brightness", 50))
out("unknown:           " GetSetting("unknown"))

; Maybe-assign (??=) — only assign if currently unset
x := 10
x ??= 99
out("x := 10; x ??= 99: " x)  ; stays 10


; ─────────────────────────────────────────────────────────────────────────────
section("FUNCTION DEFINITION EXPRESSIONS (alpha.3)")
; Define functions inline as expressions
; ─────────────────────────────────────────────────────────────────────────────

double := (x) => x * 2
add := (a, b) => a + b
out("double(21):        " double(21))
out("add(10, 5):        " add(10, 5))

; With block body
clamp := (val, lo, hi) {
    if val < lo
        return lo
    if val > hi
        return hi
    return val
}
out("clamp(150, 0, 100):" clamp(150, 0, 100))


; ─────────────────────────────────────────────────────────────────────────────
section("TYPED PROPERTIES (alpha.3)")
; Class fields with native types — stored as binary data, not AHK objects
; ─────────────────────────────────────────────────────────────────────────────

class Color {
    r: u8
    g: u8
    b: u8
    a: u8

    ToString() => Format("rgba({},{},{},{})", this.r, this.g, this.b, this.a)
}

clr := Color()
clr.r := 255, clr.g := 128, clr.b := 0, clr.a := 255
out("Typed class:       " clr.ToString())
out("Data size:         " ObjGetDataSize(clr) " bytes")


; ─────────────────────────────────────────────────────────────────────────────
section("VIRTUAL REFERENCES (alpha.10)")
; Variables that can hold unset without erroring
; ─────────────────────────────────────────────────────────────────────────────

OptionalLookup(key, &result) {
    data := Map("a", 1, "b", 2)
    if data.Has(key)
        result := data[key]
    else
        result := unset   ; explicitly set to unset
}

OptionalLookup("a", &found)
out("Lookup 'a':        " (IsSet(found) ? String(found) : "not found"))
OptionalLookup("z", &missing)
out("Lookup 'z':        " (IsSet(missing) ? String(missing) : "not found"))


; ─────────────────────────────────────────────────────────────────────────────
section("CLASS() DYNAMIC CREATION (alpha.3)")
; Create classes at runtime with Class(name, base)
; ─────────────────────────────────────────────────────────────────────────────

DynClass := Class("DynamicWidget")
DefineProp(DynClass.Prototype, "Greet", {
    Call: (this) => "Hello from " this.__Class
})
inst := (Object.Call)(DynClass)
out("Dynamic class:     " inst.Greet())
out("__Class:           " inst.__Class)


; ─────────────────────────────────────────────────────────────────────────────
section("REGEXREPLACE CALLBACK (alpha.1)")
; Pass a function instead of a replacement string
; ─────────────────────────────────────────────────────────────────────────────

result := RegExReplace("hello world", "\b\w", (m) => StrUpper(m[0]))
out("Capitalize words:  " result)

result2 := RegExReplace("a1b2c3", "\d+", (m) => m[0] * 10)
out("Multiply digits:   " result2)


; ─────────────────────────────────────────────────────────────────────────────
section("OPTIONAL MID-PARAMETERS (alpha.18)")
; Optional parameters can appear in the middle of the parameter list
; ─────────────────────────────────────────────────────────────────────────────

MidOpt(a, b?, c) {
    return a " | " (IsSet(b) ? String(b) : "skipped") " | " c
}
out("All args:          " MidOpt("x", "y", "z"))
out("Skip middle:       " MidOpt("x",, "z"))


; ─────────────────────────────────────────────────────────────────────────────
section("PER-MONITOR DPI (alpha.16)")
; Default DPI awareness changed to per-monitor v2
; ─────────────────────────────────────────────────────────────────────────────

out("A_ScreenDPI:       " A_ScreenDPI)
; GUIs auto-rescale when moved between monitors with different DPI
; ListView columns auto-scale
; Gui.DPIResize method available


; ─────────────────────────────────────────────────────────────────────────────
section("ATAN2 (alpha.1)")
; Two-argument arctangent
; ─────────────────────────────────────────────────────────────────────────────

angle := ATan2(1, 1)  ; 45 degrees in radians
out("ATan2(1,1):        " Round(angle * 180 / 3.14159265, 1) " degrees")


; ─────────────────────────────────────────────────────────────────────────────
section("GUI.ONMESSAGE (alpha.1/7)")
; Window message handling per-control and per-GUI
; ─────────────────────────────────────────────────────────────────────────────

out("Gui.OnMessage:     available (handle WM_* per-GUI)")
out("Control.OnMessage: available (handle WM_* per-control with subclassing)")


; ─────────────────────────────────────────────────────────────────────────────
section("ERROR.SHOW (alpha.10)")
; Programmatic error display with mode control
; ─────────────────────────────────────────────────────────────────────────────

err := Error("Demo error", -1, "extra info")
out("Error.Show():      available (modes: dialog, stdout, etc.)")
out("Error props:       Message='" err.Message "' Extra='" err.Extra "'")


; ─────────────────────────────────────────────────────────────────────────────
section("PROPS() ENUMERATION (alpha.10/18)")
; Enumerate own and inherited properties
; ─────────────────────────────────────────────────────────────────────────────

class Animal {
    species := "unknown"
    Speak() => "..."
}
class Dog extends Animal {
    breed := "mutt"
    Speak() => "Woof"
}
myDog := Dog()
propList := ""
for name in myDog.Props()
    propList .= name " "
out("Dog.Props():       " propList)


; ─────────────────────────────────────────────────────────────────────────────
section("MODELESS MENUS (alpha.1)")
; Menu.Show with Wait parameter
; ─────────────────────────────────────────────────────────────────────────────

out("Menu.Show(,,, Wait:=false) — non-blocking popup menus")


; ─────────────────────────────────────────────────────────────────────────────
section("MISCELLANEOUS")
; ─────────────────────────────────────────────────────────────────────────────

; alpha.1: WinGetEnabled, WinGetAlwaysOnTop
out("WinGetEnabled:     available")

; alpha.7: Menu.ToggleCheck returns new state
out("Menu.ToggleCheck:  returns new state (alpha.7)")

; alpha.7: A_KeybdHookInstalled, A_MouseHookInstalled
out("Hook vars:         A_KeybdHookInstalled, A_MouseHookInstalled (alpha.7)")

; alpha.8: Optimized auto-replace hotstrings
out("Hotstrings:        skip retyping identical leading chars (alpha.8)")

; alpha.14: A_HotIf variable
out("A_HotIf:           available (alpha.14)")

; alpha.18: Case-insensitive ahk_class
out("ahk_class:         case-insensitive (alpha.18)")


; ─────────────────────────────────────────────────────────────────────────────
section("MODULE SYSTEM (alpha.11-21)")
; #Module / #Import / Export
; Not demonstrated inline (requires separate files) but here's the syntax:
; ─────────────────────────────────────────────────────────────────────────────

out("Syntax:")
out('  #Module MyLib')
out('  export MyFunc(x) { return x * 2 }')
out('  #Module __Main')
out('  #Import MyLib { MyFunc }')
out("")
out("Key behaviors (alpha.21):")
out("  - #Module ends at end of file")
out("  - Module names are file-scoped")
out('  - #Import "file:mod" imports specific module from file')
out("  - Lazy initialization on first reference")
out("  - #Import recognizes names regardless of order")


out("`n=== All features demonstrated ===")
