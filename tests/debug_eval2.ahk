#Requires AutoHotkey v2.1-alpha.29
stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")
PrintLine "start"

; Try a very simple case first
r := _Eval("42")
PrintLine "42 = " . r
ExitApp 0
