#Requires AutoHotkey v2.1-alpha.17

; Simple file-based test
try {
    ; Create a test file to verify execution
    testFile := "TestExecution.log"
    FileAppend "Test executed at: " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`n", testFile

    ; Try to include the core files
    #Include Initialize.ahk

    ; Write success message
    FileAppend "Include successful at: " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`n", testFile

    ; Try to initialize
    logger := InitializeDebuggerInterceptor(false)
    FileAppend "Initialization result: " (logger ? "SUCCESS" : "FAILED") " at: " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`n", testFile

    MsgBox "Test completed. Check " testFile " for results."
} catch as e {
    FileAppend "ERROR: " e.Message " at: " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`n", "TestExecution.log"
    MsgBox "Error occurred. Check TestExecution.log for details."
}
