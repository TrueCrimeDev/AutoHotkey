#Requires AutoHotkey v2.1-alpha.29
stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")

try {
    r := _Eval("1 + 2")
    PrintLine "Result type: " . Type(r)
    PrintLine "Result: " . r
    PrintLine "Equals 3: " . (r = 3 ? "yes" : "no")
    PrintLine "r is: " . r
} catch as e {
    PrintLine "Exception: " . e.Message
    if (e.Extra != "")
        PrintLine "Extra: " . e.Extra
}
ExitApp 0
