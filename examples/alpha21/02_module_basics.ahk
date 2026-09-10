; ============================================================
; alpha.21 Feature: #Module / #Import basics
; ============================================================
; The module system lets you organize code into isolated
; namespaces. Since alpha.31 every module-level name is exported
; implicitly (the `export` keyword was removed).
;
; Key alpha.21 changes:
;   - #Module requires a valid identifier
;   - #Module ends at end of file (no leaking across #Include)
;   - Module names are private to each file-based module
; ============================================================

; --- Define a module inline ---
#Module MathUtils

; Every module-level name is visible to importers (alpha.31 removed `export`).
; unless it starts with an underscore, which keeps it out of `{*}` imports.

global PI := 3.14159265358979
global TAU := PI * 2

CircleArea(radius)
{
    return PI * radius ** 2
}

DegreesToRadians(degrees)
{
    return degrees * PI / 180
}

; Leading underscore: kept out of `{*}` imports (the alpha.31 convention for helpers)
_ValidatePositive(n)
{
    if n < 0
        throw ValueError("Expected positive number, got " n)
    return n
}

CircleCircumference(radius)
{
    _ValidatePositive(radius)
    return TAU * radius
}

; --- Back to default module ---
#Module __Main

; Import every name from the module ({*}); `#Import MathUtils` alone would
; only bind the module object, reachable as MathUtils.CircleArea(...).
#Import MathUtils {*}

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
