#Requires AutoHotkey v2.1-alpha.29
stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")

; test a known global constant read: IsInteger
try {
    r := _Eval("StrLen('hi')")
    PrintLine "StrLen result: " . r
} catch as e {
    PrintLine "Exception: " . e.Message . " | " . e.Extra
}
ExitApp 0
