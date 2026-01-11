#Requires AutoHotkey v2.1-alpha.17

; Step-by-step test to identify the issue
testFile := "StepByStepTest.log"
FileAppend "=== STEP-BY-STEP TEST STARTED ===`n", testFile
FileAppend "Timestamp: " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`n", testFile
FileAppend "AHK Version: " A_AhkVersion "`n`n", testFile

try {
    FileAppend "Step 1: Testing basic file operations...`n", testFile

    ; Test if we can create files
    testCreate := FileOpen("StepTest.txt", "w")
    if (testCreate) {
        testCreate.Write("Test file created")
        testCreate.Close()
        FileAppend "SUCCESS: File creation works`n", testFile
    } else {
        FileAppend "ERROR: File creation failed`n", testFile
    }

    FileAppend "Step 2: Testing include of ErrorLogger.ahk...`n", testFile

    ; Try to include ErrorLogger directly
    try {
        #Include ErrorLogger.ahk
        FileAppend "SUCCESS: ErrorLogger.ahk included`n", testFile
    } catch as e {
        FileAppend "ERROR: Failed to include ErrorLogger.ahk: " e.Message "`n", testFile
        throw e
    }

    FileAppend "Step 3: Creating ErrorLogger instance...`n", testFile

    ; Try to create an instance
    try {
        logger := ErrorLogger()
        FileAppend "SUCCESS: ErrorLogger instance created`n", testFile
        FileAppend "Logger type: " Type(logger) "`n", testFile
    } catch as e {
        FileAppend "ERROR: Failed to create ErrorLogger instance: " e.Message "`n", testFile
        throw e
    }

    FileAppend "Step 4: Testing basic logging...`n", testFile

    ; Try basic logging
    try {
        logger.LogInfo("Test message from StepByStepTest")
        FileAppend "SUCCESS: Basic logging works`n", testFile
    } catch as e {
        FileAppend "ERROR: Basic logging failed: " e.Message "`n", testFile
    }

    FileAppend "Step 5: Checking log file...`n", testFile

    ; Check if log file was created
    logFile := logger.logFilePath
    FileAppend "Log file path: " logFile "`n", testFile

    if (FileExist(logFile)) {
        logContent := FileRead(logFile)
        FileAppend "SUCCESS: Log file exists, size: " FileGetSize(logFile) " bytes`n", testFile
        if (InStr(logContent, "Test message")) {
            FileAppend "SUCCESS: Test message found in log`n", testFile
        } else {
            FileAppend "WARNING: Test message not found in log`n", testFile
        }
    } else {
        FileAppend "ERROR: Log file not created`n", testFile
    }

    FileAppend "`n=== STEP-BY-STEP TEST COMPLETED SUCCESSFULLY ===`n", testFile
    MsgBox "Step-by-step test completed! Check StepByStepTest.log for detailed results."

} catch as mainErr {
    FileAppend "ERROR: Test failed at main level: " mainErr.Message "`n", testFile
    FileAppend "Stack: " mainErr.Stack "`n", testFile
    FileAppend "`n=== STEP-BY-STEP TEST FAILED ===`n", testFile
    MsgBox "Step-by-step test failed! Check StepByStepTest.log for error details."
}
