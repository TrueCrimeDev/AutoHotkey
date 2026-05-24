#Requires AutoHotkey v2.1-alpha.29
stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")

; Can we call a pre-defined function?
myFunc() => 7
try {
    r := _Eval("myFunc()")
    PrintLine "myFunc() = " . r
} catch as e {
    PrintLine "Exception: " . e.Message
    PrintLine "Extra: " . e.Extra
}
ExitApp 0
