#Requires AutoHotkey v2.1-alpha.29
stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")

try {
    r := _Eval("StrLen('hello')")
    PrintLine "StrLen = " . r
} catch as e {
    PrintLine "Exception: " . e.Message . " | " . e.Extra
}
ExitApp 0
