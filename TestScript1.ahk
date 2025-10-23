#Requires AutoHotkey v2.0
; ============================================================================
; TestScript1.ahk - Test script for global debugging system
; ============================================================================
; This script intentionally generates errors to test error capture
; Run with: AutoDebug.ahk TestScript1.ahk
; ============================================================================

MsgBox("TestScript1 starting...`n`nThis script will generate test errors in 3 seconds.", "Test Script", "i T3")

Sleep(3000)

; Test 1: Division by zero
MsgBox("Test 1: Division by zero", "Test", "i T1")
Sleep(1000)
try {
    result := 10 / 0
} catch {
    ; Will be caught by DebugClient
}

Sleep(2000)

; Test 2: Array bounds error
MsgBox("Test 2: Array bounds error", "Test", "i T1")
Sleep(1000)
try {
    arr := [1, 2, 3]
    value := arr[99]
} catch {
    ; Will be caught by DebugClient
}

Sleep(2000)

; Test 3: Undefined variable
MsgBox("Test 3: Undefined variable", "Test", "i T1")
Sleep(1000)
try {
    #Warn VarUnset, Off
    x := nonExistentVariable
} catch {
    ; Will be caught by DebugClient
}

MsgBox("TestScript1 completed!`n`nCheck GlobalDebugServer for captured errors.", "Test Complete", "i")
