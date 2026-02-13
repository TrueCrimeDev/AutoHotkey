#Requires AutoHotkey v2.1-alpha.17

; Minimal test - just try to include and initialize
try {
    #Include Initialize.ahk
    MsgBox "Include successful"

    logger := InitializeDebuggerInterceptor(false)
    MsgBox "Initialization successful: " (logger ? "Yes" : "No")
} catch as e {
    MsgBox "Error: " e.Message
}
