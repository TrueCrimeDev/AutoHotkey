#Requires AutoHotkey v2.1-alpha.29
stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")
PrintLine "start"

try {
    r := _Eval("1 + 2")
    PrintLine "1+2 = " . r
} catch as e {
    PrintLine "CAUGHT: " . e.Message
}
PrintLine "after try"
ExitApp 0
