#Requires AutoHotkey v2.1-alpha.31
; Tiny child for the ProcessPipe demonstration.
; Prints two lines on stdout and exits: one through Print's Format dispatch,
; one through Print's single-argument literal path (braces must survive).

payload := A_Args.Length ? A_Args[1] : "no-arg"

Print("echo: {}", payload)
Print("literal {braces} kept")

ExitApp(0)
