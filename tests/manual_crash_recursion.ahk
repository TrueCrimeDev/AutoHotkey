#Requires AutoHotkey v2.1-alpha.29
; Deliberately crashes via infinite recursion (stack overflow). NOT part of automated tests.
; Use to verify the SEH filter writes a [FATAL] record to the crash log.
; Run as: AutoHotkey64.exe /CrashLog=tests\tmp\fatal_stack.log tests\manual_crash_recursion.ahk
Recurse() {
    Recurse()
}
Recurse()
