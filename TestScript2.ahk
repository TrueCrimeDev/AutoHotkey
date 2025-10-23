#Requires AutoHotkey v2.0
; ============================================================================
; TestScript2.ahk - Test script with nested function calls
; ============================================================================
; Tests stack trace capture with function chains
; Run with: AutoDebug.ahk TestScript2.ahk
; ============================================================================

MsgBox("TestScript2 starting...`n`nTesting stack trace capture with nested calls.", "Test Script", "i T2")

Sleep(2000)

; Call nested functions that will eventually error
Level1()

MsgBox("TestScript2 completed!", "Test Complete", "i")

Level1() {
    MsgBox("Entering Level1", "Debug", "i T0.5")
    Level2()
}

Level2() {
    MsgBox("Entering Level2", "Debug", "i T0.5")
    Level3()
}

Level3() {
    MsgBox("Entering Level3", "Debug", "i T0.5")
    Level4()
}

Level4() {
    MsgBox("Entering Level4 - Error will occur here!", "Debug", "i T1")

    try {
        ; This will generate an error with full stack trace
        obj := {name: "Test"}
        value := obj.nonExistent.deepProperty
    } catch {
        ; Error will be captured by DebugClient with full stack
    }
}
