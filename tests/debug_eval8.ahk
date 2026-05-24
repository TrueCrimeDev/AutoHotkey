#Requires AutoHotkey v2.1-alpha.29
stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")

PrintLine "before"
r := _Eval("1 + 2")
PrintLine "1+2=" . r
r2 := _Eval("'hello'")
PrintLine "hello=" . r2
r3 := _Eval("StrLen('hello')")
PrintLine "strlen=" . r3
ExitApp 0
