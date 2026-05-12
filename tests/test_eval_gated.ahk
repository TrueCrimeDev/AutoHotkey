#Requires AutoHotkey v2.1-alpha.29

Assert(cond, msg := "assertion failed") {
    if !cond {
        FileAppend("FAIL: " . msg . "`n", "**")
        ExitApp 14
    }
}

stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")

PrintLine "=== _Eval test (no /Eval flag) ==="

threw := false
err   := unset
try
    _Eval("1 + 1")
catch Any as e {
    threw := true
    err := e
}

Assert(threw,                                       "must throw when /Eval not set")
Assert(InStr(err.Message, "_Eval is disabled") > 0, "message mentions disabled")

PrintLine "all checks passed"
ExitApp 0
