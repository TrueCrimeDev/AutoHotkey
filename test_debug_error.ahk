#SingleInstance Force
; Test script for MCP debugger demo
; This will trigger an error for the LLM to analyze

ProcessData(data) {
    ; Bug: accessing property that might not exist
    result := data.value * 2
    return result
}

; This will cause an error - data doesn't have .value property
myData := {name: "test"}
output := ProcessData(myData)
MsgBox("Result: " output)
