#Requires AutoHotkey v2.1-alpha.31
; tests/run.ahk -- single-process test entry point.
;
; Run it from the repository root with the fork's console engine.
;
; PowerShell:
;   bin\AutoHotkey64Console.exe /Headless /Diag=json test tests\run.ahk
;   New-Item -ItemType Directory -Force coverage | Out-Null
;   bin\AutoHotkey64Console.exe /Headless /Coverage=coverage\tests.lcov test tests\run.ahk
;
; Git Bash rewrites arguments that start with "/" into paths, so use the aliases:
;   ./bin/AutoHotkey64Console.exe --headless --diag=json test tests/run.ahk
;   mkdir -p coverage
;   ./bin/AutoHotkey64Console.exe --headless --coverage=coverage/tests.lcov test tests/run.ahk
;
; Create the coverage directory first: when it is missing, --coverage (/Coverage)
; writes nothing and the run still exits 0 with no diagnostic
; (qa/tests/test_coverage_missing_dir.ahk pins that behavior).
;
; Exit codes: 0 all passed, 14 any failure (or a test file not listed below).
; Every tests/*.test.ahk must be #Included here; the check below fails the run
; if one is missing, so adding a test file is a two-line change.

#Include Test.ahk

#Include check.test.ahk
#Include framework.test.ahk
#Include json.test.ahk

VerifyEveryTestFileIsIncluded()
Test.Run()

VerifyEveryTestFileIsIncluded() {
    included := Map()
    included.CaseSense := false
    for line in StrSplit(FileRead(A_ScriptFullPath), "`n", "`r")
        if RegExMatch(line, 'i)^\s*#Include\s+"?([^"\s]+\.test\.ahk)"?', &m)
            included[m[1]] := true
    missing := []
    Loop Files A_ScriptDir "\*.test.ahk"
        if !included.Has(A_LoopFileName)
            missing.Push(A_LoopFileName)
    if missing.Length {
        for name in missing
            Print("tests: {} exists but is not #Included by {}", name, A_ScriptName)
        ExitApp(14)
    }
}
