#Requires AutoHotkey v2.1-alpha.17

; Robust test with detailed error handling
testFile := "RobustTestResults.log"
FileAppend "=== ROBUST TEST STARTED ===`n", testFile
FileAppend "Timestamp: " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`n", testFile
FileAppend "Working Directory: " A_WorkingDir "`n`n", testFile

try {
    FileAppend "Step 1: Attempting to include Initialize.ahk...`n", testFile

    ; Try to include with error handling
    try {
        #Include Initialize.ahk
        FileAppend "SUCCESS: Initialize.ahk included`n", testFile
    } catch as includeErr {
        FileAppend "ERROR: Failed to include Initialize.ahk: " includeErr.Message "`n", testFile
        throw includeErr
    }

    FileAppend "Step 2: Attempting initialization...`n", testFile

    ; Try to initialize
    try {
        logger := InitializeDebuggerInterceptor(false)
        if (logger) {
            FileAppend "SUCCESS: DebuggerInterceptor initialized`n", testFile
            FileAppend "Logger instance: " logger "`n", testFile
        } else {
            FileAppend "WARNING: Initialization returned null`n", testFile
        }
    } catch as initErr {
        FileAppend "ERROR: Failed to initialize: " initErr.Message "`n", testFile
        throw initErr
    }

    FileAppend "Step 3: Testing basic functionality...`n", testFile

    ; Test basic logging
    try {
        DebugLog("Test message from RobustTest")
        FileAppend "SUCCESS: DebugLog called`n", testFile
    } catch as logErr {
        FileAppend "ERROR: DebugLog failed: " logErr.Message "`n", testFile
    }

    FileAppend "Step 4: Checking for log files...`n", testFile

    ; Check if any log files were created
    if (FileExist("ErrorLogs\")) {
        FileAppend "SUCCESS: ErrorLogs directory exists`n", testFile
        Loop Files, "ErrorLogs\*.log" {
            FileAppend "Found log file: " A_LoopFileName " (" A_LoopFileSize " bytes)`n", testFile
        }
    } else {
        FileAppend "INFO: ErrorLogs directory not found`n", testFile
    }

    FileAppend "`n=== ROBUST TEST COMPLETED SUCCESSFULLY ===`n", testFile
    MsgBox "Robust test completed successfully! Check RobustTestResults.log for details."

} catch as mainErr {
    FileAppend "ERROR: Test failed at main level: " mainErr.Message "`n", testFile
    FileAppend "Stack: " mainErr.Stack "`n", testFile
    FileAppend "`n=== ROBUST TEST FAILED ===`n", testFile
    MsgBox "Robust test failed! Check RobustTestResults.log for error details."
}
