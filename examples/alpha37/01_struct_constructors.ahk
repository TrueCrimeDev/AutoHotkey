; alpha.37: Struct.Prototype.__New(fieldValues*)
;
; Calling a struct class with arguments now fills its fields in declaration
; order, so a POINT or RECT can be written as a literal instead of four
; assignment lines. The count must match the field count exactly, and a
; script-defined __New can delegate to super.__New to validate or normalize.
;
; Before alpha.37, POINT(10, 20) threw "Too many parameters passed to function."
;
; Run: bin\AutoHotkey64Console.exe examples\alpha37\01_struct_constructors.ahk
#Requires AutoHotkey v2.1-alpha.37

struct POINT {
    x : Int32
    y : Int32
}

struct RECT {
    left   : Int32
    top    : Int32
    right  : Int32
    bottom : Int32
}

; --- 1. Literals -------------------------------------------------------------
pt := POINT(10, 20)
rc := RECT(0, 0, 100, 50)
Print("POINT({}, {})  RECT({}, {}, {}, {})", pt.x, pt.y, rc.left, rc.top, rc.right, rc.bottom)
Print("POINT() still zero-initializes: ({}, {})", POINT().x, POINT().y)

; --- 2. Straight into a Win32 call -------------------------------------------
; PtInRect takes a RECT* and a POINT by value. The POINT literal is built in
; the argument list and never needs a name.
hit := DllCall("user32\PtInRect", "Ptr", rc.Ptr, POINT, POINT(10, 10), "Int")
miss := DllCall("user32\PtInRect", "Ptr", rc.Ptr, POINT, POINT(10, 60), "Int")
Print("PtInRect (10,10): {}   (10,60): {}", hit, miss)

; --- 3. A table of structs in one expression ---------------------------------
corners := [POINT(rc.left, rc.top), POINT(rc.right, rc.top),
            POINT(rc.right, rc.bottom), POINT(rc.left, rc.bottom)]
out := ""
for c in corners
    out .= Format("({},{}) ", c.x, c.y)
Print("corners: {}", out)

; --- 4. A constructor that normalizes its input ------------------------------
; super.__New(fieldValues*) is the new base constructor, so a subclass can
; accept arguments in any order and store them canonically.
struct Span {
    lo : Int32
    hi : Int32
    __New(a, b) {
        super.__New(Min(a, b), Max(a, b))
    }
    Length => this.hi - this.lo
}
s := Span(90, 30)
Print("Span(90, 30) stores {}..{} (length {})", s.lo, s.hi, s.Length)

; --- 5. The count is checked ----------------------------------------------------
try POINT(1)
catch Error as e
    Print("POINT(1): {}", e.Message)
try RECT(1, 2, 3, 4, 5)
catch Error as e
    Print("RECT(1, 2, 3, 4, 5): {}", e.Message)
