#Requires AutoHotkey v2.1-alpha.29

Assert(cond, msg := "assertion failed") {
    if !cond {
        FileAppend("FAIL: " . msg . "`n", "**")
        ExitApp 14
    }
}

; Usage: bin\AutoHotkey64.exe tests\crashlog_check.ahk <logfile> <substring> [<substring2> ...]
if A_Args.Length < 2 {
    FileAppend("USAGE: crashlog_check.ahk <logfile> <substring> [<substring2> ...]`n", "**")
    ExitApp 64
}

logpath := A_Args[1]
Assert(FileExist(logpath), "log file should exist: " . logpath)

content := FileRead(logpath, "UTF-8")
loop A_Args.Length - 1 {
    needle := A_Args[A_Index + 1]
    Assert(InStr(content, needle) > 0, "log should contain substring: " . needle)
}

FileAppend("crashlog_check: all checks passed`n", "*")
ExitApp 0
