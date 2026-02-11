#Requires AutoHotkey v2.0

; First error - undefined variable
x := undefined1.property

; This won't run because first error stops execution
y := undefined2.property

; Neither will this
obj := {}
obj.BadMethod()
