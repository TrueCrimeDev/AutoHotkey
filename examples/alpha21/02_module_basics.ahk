; ============================================================
; alpha.21 Feature: #Module / #Import basics
; ============================================================
; The module system lets you organize code into isolated
; namespaces with explicit exports.
;
; Key alpha.21 changes:
;   - #Module requires a valid identifier
;   - #Module ends at end of file (no leaking across #Include)
;   - Module names are private to each file-based module
; ============================================================

; --- Define a module inline ---
#Module MathUtils

; Variables and functions in a module are private by default.
; Use `export` to make them visible to importers.

export global PI := 3.14159265358979
export global TAU := PI * 2

export CircleArea(radius)
{
    return PI * radius ** 2
}

export DegreesToRadians(degrees)
{
    return degrees * PI / 180
}

; This helper is NOT exported — it's internal to MathUtils
_ValidatePositive(n)
{
    if n < 0
        throw ValueError("Expected positive number, got " n)
    return n
}

export CircleCircumference(radius)
{
    _ValidatePositive(radius)
    return TAU * radius
}

; --- Back to default module ---
#Module __Main

; Import the module
#Import MathUtils

; Use exported members
area := CircleArea(5)
MsgBox Format("Circle area (r=5): {:.2f}", area)
; Expected: 78.54

circumference := CircleCircumference(10)
MsgBox Format("Circle circumference (r=10): {:.2f}", circumference)
; Expected: 62.83

MsgBox Format("PI = {:.5f}, TAU = {:.5f}", PI, TAU)

; Convert 90 degrees to radians
rad := DegreesToRadians(90)
MsgBox Format("90° = {:.4f} radians", rad)
; Expected: 1.5708
