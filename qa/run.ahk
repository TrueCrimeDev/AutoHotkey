#Requires AutoHotkey v2.1-alpha.30
; qa/run.ahk -- subprocess regression runner for this AHK fork.
;
; Every qa/tests/test_*.ahk is a standalone script that #Includes ..\Assert.ahk
; and ends with Assert.Summary(). The runner launches each one in its OWN
; process, so a test that throws at runtime or dies at load time (parse error,
; fatal) is a normal, assertable outcome instead of aborting the whole suite --
; which the NewLoop single-process #Include model cannot do.
;
; Per test we capture stdout + the process exit code:
;   * a "qa: P passed, F failed" line present  -> tally P/F, status PASS/FAIL
;   * that line absent                          -> the test crashed before
;                                                  Summary(); count 1 failure,
;                                                  status CRASH, echo its output
;
; Suite exit code = total failing assertions + crashes, so `$? -eq 0` from any
; shell means the whole tree is green.
;
; Usage:  bin\AutoHotkey64.exe /ErrorStdOut qa\run.ahk

engine  := A_AhkPath
testDir := A_ScriptDir "\tests"

files := []
Loop Files testDir "\test_*.ahk"
    files.Push(A_LoopFileFullPath)

; Deterministic order regardless of filesystem enumeration.
StableSort(files)

if !files.Length {
    Print("qa: no test files found in {}", testDir)
    ExitApp 0
}

totalPassed := 0
totalFailed := 0
crashes     := 0
idx         := 0

Print("qa: running {} test file(s) with {}", files.Length, engine)
Print("")

for file in files {
    idx += 1
    name := NameOf(file)
    tmp  := A_Temp "\qa_" A_TickCount "_" idx ".out"

    ; cmd /c "..." with redirection; nested quotes are the standard ComSpec form.
    ; A_ComSpec can be empty when the engine is launched from WSL (ComSpec is
    ; not in the translated environment), so fall back to the well-known path.
    shell := A_ComSpec != "" ? A_ComSpec : A_WinDir "\System32\cmd.exe"
    cmd  := shell ' /c ""' engine '" /ErrorStdOut "' file '" >"' tmp '" 2>&1"'
    code := RunWait(cmd, , "Hide")

    ; try: FileRead of a zero-byte file returns no value on this alpha, which
    ; a bare ternary turns into "No value was returned".
    out := ""
    if FileExist(tmp)
        try out := FileRead(tmp, "UTF-8")
    try FileDelete(tmp)

    if RegExMatch(out, "m)^qa: (\d+) passed, (\d+) failed", &m) {
        p := Integer(m[1]), f := Integer(m[2])
        totalPassed += p
        totalFailed += f
        status := f ? "FAIL" : "PASS"
        Print("  [{}] {}  ({} passed, {} failed)", status, name, p, f)
        if f
            EchoFailLines(out)
    } else {
        crashes += 1
        Print("  [CRASH] {}  (exit {}, no summary line)", name, code)
        EchoIndented(out)
    }
}

Print("")
grandFail := totalFailed + crashes
Print("qa: {} passed, {} failed, {} crashed across {} file(s)",
      totalPassed, grandFail, crashes, files.Length)
ExitApp grandFail

; ---- helpers ----

NameOf(path) => RegExReplace(path, "^.*[\\/]", "")

; Echo only the "  FAIL ..." detail lines a failing test emitted.
EchoFailLines(out) {
    for line in StrSplit(out, "`n", "`r")
        if RegExMatch(line, "^\s*FAIL ")
            Print("    {}", Trim(line))
}

; Echo every non-empty line, indented, for a crashed test.
EchoIndented(out) {
    for line in StrSplit(out, "`n", "`r")
        if Trim(line) != ""
            Print("      {}", Trim(line, "`r`n"))
}

; In-place insertion sort -- avoids relying on a fork Sort() BIF signature.
StableSort(arr) {
    Loop arr.Length - 1 {
        i := A_Index + 1
        key := arr[i]
        j := i - 1
        while (j >= 1 && StrCompare(arr[j], key) > 0) {
            arr[j + 1] := arr[j]
            j -= 1
        }
        arr[j + 1] := key
    }
}
