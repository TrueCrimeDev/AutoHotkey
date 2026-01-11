#Requires AutoHotkey v2.1-alpha.17

; Simple test to verify the DebuggerInterceptor system works
MsgBox "Starting DebuggerInterceptor test..."

; Include the core files
#Include Initialize.ahk

; Initialize the system
try {
    logger := InitializeDebuggerInterceptor(false)
    MsgBox "DebuggerInterceptor initialized successfully!"

    ; Test basic logging
    DebugLog("Test message - this should appear in logs")
    ErrorLogger.Info("Info level test")
    ErrorLogger.Warning("Warning level test")
    ErrorLogger.Error("Error level test")

    ; Test error handling
    try {
        result := 10 / 0  ; Generate error
    } catch as err {
        DebugError("Caught test error", err)
        MsgBox "Error successfully caught and logged!"
    }

    ; Check if log file was created
    if (FileExist(ErrorLogger.Instance.logFilePath)) {
        logContent := FileRead(ErrorLogger.Instance.logFilePath)
        if (InStr(logContent, "Test message")) {
            MsgBox "SUCCESS: Test message found in logs!"
        } else {
            MsgBox "WARNING: Test message not found in logs"
        }
    } else {
        MsgBox "ERROR: Log file not created"
    }

    MsgBox "DebuggerInterceptor test completed!"
} catch as initErr {
    MsgBox "ERROR: Failed to initialize DebuggerInterceptor: " initErr.Message
}
