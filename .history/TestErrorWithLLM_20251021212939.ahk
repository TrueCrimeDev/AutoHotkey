#Requires AutoHotkey v2.0
; ============================================================================
; TestErrorWithLLM.ahk
; ============================================================================
; Quick test of error interception with LLM analysis
; Include ErrorInterceptor at top to enable global error handling
; ============================================================================

#Include ErrorInterceptor.ahk

; Simple GUI for quick testing
testGui := Gui()
testGui.SetFont("s11")
testGui.Add("Text", "w400 h30", "AutoHotkey Error Interception with Claude AI")
testGui.Add("Text", "w400 h10")

; Test buttons
testGui.Add("Button", "w150", "File Not Found").OnEvent("Click", FileNotFoundError)
testGui.Add("Button", "w150 x+10", "Division by Zero").OnEvent("Click", DivByZeroError)
testGui.Add("Button", "w150", "Undefined Variable").OnEvent("Click", UndefinedVarError)
testGui.Add("Button", "w150 x+10", "Array Out of Bounds").OnEvent("Click", ArrayOutOfBoundsError)
testGui.Add("Button", "w150", "Type Mismatch").OnEvent("Click", TypeMismatchError)
testGui.Add("Button", "w150 x+10", "Custom Throw").OnEvent("Click", CustomThrowError)

testGui.Add("Text", "w400 h20")
testGui.Add("Text", "w400", "Note: With LLM enabled, errors show Claude's analysis")
testGui.Add("Text", "w400", "Check Configuration in ErrorInterceptor.ahk for LLM settings")
testGui.Add("Text", "w400", "Requires CLAUDE_API_KEY environment variable")

testGui.Show()

; ============================================================================
; Error Scenario Functions
; ============================================================================

FileNotFoundError(GuiCtrlObj, Info) {
    content := FileRead("C:\This\Path\Does\Not\Exist\file.txt")
    MsgBox("If you see this, error wasn't caught!")
}

DivByZeroError(GuiCtrlObj, Info) {
    result := 100 / 0
    MsgBox("If you see this, error wasn't caught!")
}

UndefinedVarError(GuiCtrlObj, Info) {
    #Warn VarUnset, Off
    x := undefinedVariable
    MsgBox("If you see this, error wasn't caught!")
}

ArrayOutOfBoundsError(GuiCtrlObj, Info) {
    arr := [1, 2, 3, 4, 5]
    result := arr[999]
    MsgBox("If you see this, error wasn't caught!")
}

TypeMismatchError(GuiCtrlObj, Info) {
    str := "Hello"
    result := str.SubStr()  ; Missing required parameter
    MsgBox("If you see this, error wasn't caught!")
}

CustomThrowError(GuiCtrlObj, Info) {
    throw ValueError("Custom demonstration error", -1, "This is intentional for testing LLM analysis")
}
