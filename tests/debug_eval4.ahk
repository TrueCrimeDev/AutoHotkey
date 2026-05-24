#Requires AutoHotkey v2.1-alpha.29
stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")

PrintLine "C.1: " . _Eval("1 + 2")
PrintLine "C.2: " . _Eval("'hi ' . 'there'")
PrintLine "C.3: " . _Eval("[1,2,3].Length")
try {
    r := _Eval("(()=> 7)()")
    PrintLine "C.4: " . r
} catch as e {
    PrintLine "C.4 exception: " . e.Message
}
ExitApp 0
