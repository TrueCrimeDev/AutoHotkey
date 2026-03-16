; ============================================================
; alpha.21 Feature: Selective imports with { } and `as`
; ============================================================
; You can import specific exports by name, rename them with
; `as`, or use `*` to import everything.
;
; Syntax variants:
;   #Import ModuleName                    ; import module object
;   #Import {Foo, Bar} from ModuleName    ; import specific names
;   #Import {Foo as MyFoo} from Module    ; rename on import
;   #Import * from ModuleName             ; wildcard import
; ============================================================

; Define two modules with overlapping names
#Module Geometry

export global VERSION := "Geometry v1.0"

export Area(shape, params*)
{
    switch shape
    {
        case "circle":   return 3.14159 * params[1] ** 2
        case "rect":     return params[1] * params[2]
        case "triangle": return 0.5 * params[1] * params[2]
        default:         return 0
    }
}

export Describe(shape)
{
    return "Shape: " shape " (from Geometry)"
}


#Module Physics

export global VERSION := "Physics v1.0"

export Force(mass, acceleration)
{
    return mass * acceleration
}

export Energy(mass)
{
    static C := 299792458  ; speed of light m/s
    return mass * C ** 2
}

export Describe(concept)
{
    return "Concept: " concept " (from Physics)"
}


; --- Back to main ---
#Module __Main

; Selective import: only Area from Geometry
#Import {Area} from Geometry

; Import Physics module as an object (access via Physics.Method())
#Import Physics

; Rename to avoid conflict: both modules export "Describe"
#Import {Describe as DescribeShape} from Geometry
#Import {Describe as DescribePhysics} from Physics

; --- Demonstrate ---
MsgBox Format("Circle area: {:.2f}", Area("circle", 7))
MsgBox Format("Rectangle area: {:.0f}", Area("rect", 4, 5))

MsgBox Format("Force: {:.1f} N", Physics.Force(10, 9.8))

; Renamed imports avoid name collisions
MsgBox DescribeShape("hexagon")
MsgBox DescribePhysics("gravity")

; Access module version through object
MsgBox "Physics version: " Physics.VERSION
