; ============================================================
; alpha.21 Feature: Selective imports with { } and `as`
; ============================================================
; You can import specific names, rename them with
; `as`, or use `*` to import everything.
;
; Syntax variants:
;   #Import ModuleName                    ; import module object
;   #Import ModuleName {Foo, Bar}         ; import specific names
;   #Import ModuleName {Foo as MyFoo}     ; rename on import
;   #Import ModuleName {*}                ; wildcard import
; ============================================================

; Define two modules with overlapping names
#Module Geometry

global VERSION := "Geometry v1.0"

Area(shape, params*)
{
    switch shape
    {
        case "circle":   return 3.14159 * params[1] ** 2
        case "rect":     return params[1] * params[2]
        case "triangle": return 0.5 * params[1] * params[2]
        default:         return 0
    }
}

Describe(shape)
{
    return "Shape: " shape " (from Geometry)"
}


#Module Physics

global VERSION := "Physics v1.0"

Force(mass, acceleration)
{
    return mass * acceleration
}

Energy(mass)
{
    static C := 299792458  ; speed of light m/s
    return mass * C ** 2
}

Describe(concept)
{
    return "Concept: " concept " (from Physics)"
}


; --- Back to main ---
#Module __Main

; Selective import: only Area from Geometry
#Import Geometry {Area}

; Import Physics module as an object (access via Physics.Method())
#Import Physics

; Rename to avoid conflict: both modules define "Describe"
#Import Geometry {Describe as DescribeShape}
#Import Physics {Describe as DescribePhysics}

; --- Demonstrate ---
MsgBox Format("Circle area: {:.2f}", Area("circle", 7))
MsgBox Format("Rectangle area: {:.0f}", Area("rect", 4, 5))

MsgBox Format("Force: {:.1f} N", Physics.Force(10, 9.8))

; Renamed imports avoid name collisions
MsgBox DescribeShape("hexagon")
MsgBox DescribePhysics("gravity")

; Access module version through object
MsgBox "Physics version: " Physics.VERSION
