#Requires AutoHotkey v2.1-alpha.17

; Simple version test
try {
    FileAppend "Version test started at: " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`n", "VersionTest.log"
    FileAppend "AHK Version: " A_AhkVersion "`n", "VersionTest.log"
    FileAppend "Script working directory: " A_WorkingDir "`n", "VersionTest.log"

    ; Test basic functionality
    testVar := "Hello World"
    FileAppend "Test variable: " testVar "`n", "VersionTest.log"

    ; Test simple error handling
    try {
        result := 10 / 2  ; This should work
        FileAppend "Division result: " result "`n", "VersionTest.log"
    } catch as e {
        FileAppend "Error in division: " e.Message "`n", "VersionTest.log"
    }

    FileAppend "Version test completed successfully!`n", "VersionTest.log"
    MsgBox "Version test completed! Check VersionTest.log for results."
} catch as mainErr {
    FileAppend "FATAL ERROR: " mainErr.Message "`n", "VersionTest.log"
    MsgBox "Version test failed! Check VersionTest.log for error details."
}
