#Requires AutoHotkey v2.1-alpha.29

; Lightweight Assert: exits the process with code 14 on first failure.
Assert(cond, msg := "assertion failed") {
    if !cond {
        FileAppend("FAIL: " . msg . "`n", "**")
        ExitApp 14
    }
}

stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")

PrintLine "=== _Eval test (with /Eval enabled) ==="

; --- Section A: presence ---
Assert(IsSet(_Eval),     "A.1 _Eval is defined")
Assert(_Eval is Func,    "A.2 _Eval is a function")

PrintLine "all checks passed"
ExitApp 0
