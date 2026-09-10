; ============================================================
; alpha.21 Feature: Module file scoping
; ============================================================
; Two key scoping changes:
;
; 1. #Module ends at end of file — if you #Include a file that
;    defines a module, returning from the include goes back to
;    the previous module (no leaking).
;
; 2. Module names are private to each file-based module —
;    two different files can each define a #Module Helper
;    without conflict.
; ============================================================

; --- Main script ---
; Include two library files that each define their own
; internal "Helper" module. These don't conflict because
; module names are file-scoped in alpha.21.

#Import "lib/StringUtils.ahk" {*}
#Import "lib/Collections.ahk:Stack" {Stack}

; Both files could internally use `#Module Helper` for private
; utilities without any naming collision.

; Use the imported public APIs
reversed := Reverse("hello")
MsgBox "Reversed 'hello': " reversed

s := Stack()
s.Push("alpha.21")
s.Push("is great")
MsgBox "Stack peek: " s.Peek()

; #Module defined here stays in THIS file only.
; If we #Include another file, our module doesn't leak into it,
; and any modules they define don't leak into us.

#Module LocalHelper

Greet(name)
{
    return "Hello, " name "! Welcome to alpha.21."
}

#Module __Main

#Import LocalHelper {Greet}

MsgBox Greet("Developer")
