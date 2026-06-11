#Requires AutoHotkey v2
; Verifies that KeyHistory/ListLines/ListVars/ListHotkeys write to stdout
; (instead of opening the main window) when a console is attached.

testVar1 := 42
testVar2 := "console mirror test"

Print("=== KeyHistory ===")
KeyHistory()
Print("=== ListLines ===")
ListLines()
Print("=== ListVars ===")
ListVars()
Print("=== ListHotkeys ===")
ListHotkeys()
Print("=== done ===")
ExitApp(0)
