#Requires AutoHotkey v2.1-alpha.29
stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")

; Test calling a pre-defined function
f := () => 7
try {
    r := _Eval("(()=> 7)()")
    PrintLine "fat-arrow IIFE = " . r
} catch as e {
    PrintLine "Exception: " . e.Message
}
ExitApp 0
