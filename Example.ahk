#Requires AutoHotkey v2.1-alpha.17

; DebuggerInterceptor Example Script
; Demonstrates all features of the error logging system

#Include Initialize.ahk

; ============================================================================
; INITIALIZATION
; ============================================================================

; Initialize with test GUI shown
logger := InitializeDebuggerInterceptor(true)

; Configure for this example
ErrorLogger.Config["logLevel"] := "DEBUG"
ErrorLogger.Config["clipboardFormat"] := "detailed"

; ============================================================================
; MAIN APPLICATION WINDOW
; ============================================================================

mainGui := Gui()
mainGui.SetFont("s11", "Segoe UI")
mainGui.Add("Text",, "DebuggerInterceptor Demo Application")
mainGui.Add("Text", "w300", "Click buttons to test error logging:")
mainGui.Add("Button", "w300", "Logging Test").OnEvent("Click", LoggingTest)
mainGui.Add("Button", "w300", "Error Test").OnEvent("Click", ErrorTest)
mainGui.Add("Button", "w300", "Complex Operation").OnEvent("Click", ComplexOp)
mainGui.Add("Button", "w300", "Function Chain").OnEvent("Click", FunctionChain)
mainGui.Add("Button", "w300", "File Operations").OnEvent("Click", FileOpsTest)
mainGui.Add("Button", "w300", "Show Viewer").OnEvent("Click", (*) => ShowLogViewer())
mainGui.Add("Text",, "`nPress Ctrl+Alt+L to open log viewer`nClose this window to exit")

mainGui.Show("w320")

; ============================================================================
; TEST FUNCTIONS
; ============================================================================

LoggingTest(GuiObj, Info) {
    DebugLog("=== LOGGING TEST START ===")
    DebugLog("Info level message - normal operation")
    DebugWarning("Warning level message - potential issue")
    DebugError("Error level message - operation failed")
    DebugLog("=== LOGGING TEST END ===")

    MsgBox("Logged 4 messages. Check the log viewer!")
}

ErrorTest(GuiObj, Info) {
    DebugLog("Starting error test...")

    try {
        DebugLog("Attempting division by zero")
        result := 10 / 0  ; This triggers an error
    } catch as err {
        DebugError("Caught division error", err)
    }

    try {
        DebugLog("Attempting array bounds violation")
        arr := [1, 2, 3]
        value := arr[100]  ; Out of bounds
    } catch as err {
        DebugError("Caught array error", err)
    }

    try {
        DebugLog("Attempting invalid operation")
        obj := {}
        result := obj.nonexistent + 5
    } catch as err {
        DebugError("Caught object error", err)
    }

    DebugLog("Error test completed")
    MsgBox("Generated 3 errors. Check the log viewer!")
}

ComplexOp(GuiObj, Info) {
    DebugLog("=== COMPLEX OPERATION START ===")

    try {
        DebugLog("Step 1: Initializing data")
        data := {users: [], count: 0}

        DebugLog("Step 2: Processing users")
        Loop 5 {
            DebugLog("  Processing user " A_Index)
            user := {id: A_Index, name: "User" A_Index}
            data.users.Push(user)
            data.count++
        }

        DebugLog("Step 3: Validating data")
        if (data.count = 5)
            DebugLog("  Validation passed: 5 users created")
        else
            DebugWarning("  Unexpected user count: " data.count)

        DebugLog("Step 4: Finalizing")
        DebugLog("Operation successful with " data.count " users")
    } catch as err {
        DebugError("Complex operation failed", err)
    }

    DebugLog("=== COMPLEX OPERATION END ===")
    MsgBox("Operation completed. Check log for detailed trace!")
}

FunctionChain(GuiObj, Info) {
    DebugLog("=== FUNCTION CHAIN START ===")

    try {
        DebugLog("Calling Level1Function")
        Level1Function()
    } catch as err {
        DebugError("Function chain error", err)
    }

    DebugLog("=== FUNCTION CHAIN END ===")
    MsgBox("Function chain completed!")
}

Level1Function() {
    DebugLog("  In Level1Function")
    Level2Function()
}

Level2Function() {
    DebugLog("    In Level2Function")
    Level3Function()
}

Level3Function() {
    DebugLog("      In Level3Function")
    DebugLog("      Performing operation...")
    ; Simulate some work
    value := 42
    DebugLog("      Operation result: " value)
}

FileOpsTest(GuiObj, Info) {
    DebugLog("=== FILE OPERATIONS TEST START ===")

    try {
        testFile := A_ScriptDir "\test_debug.txt"

        DebugLog("Step 1: Creating test file")
        FileAppend("Test content`nLine 2`nLine 3", testFile)
        DebugLog("  File created: " testFile)

        DebugLog("Step 2: Reading file")
        content := FileRead(testFile)
        DebugLog("  File read successfully, " StrLen(content) " bytes")

        DebugLog("Step 3: Modifying file")
        FileAppend("`nLine 4 appended", testFile)
        DebugLog("  File modified")

        DebugLog("Step 4: Deleting file")
        FileDelete(testFile)
        DebugLog("  File deleted")

        DebugLog("File operations completed successfully")
    } catch as err {
        DebugError("File operation failed", err)
    }

    DebugLog("=== FILE OPERATIONS TEST END ===")
    MsgBox("File operations test completed!")
}

; ============================================================================
; EXIT HANDLER
; ============================================================================

mainGui.OnEvent("Close", (*) => ExitApp)

; Log script exit
ExitApp(code) {
    DebugLog("Script exiting with code: " code)
}

; ============================================================================
; DEMONSTRATION NOTES
; ============================================================================

/*
    This example script demonstrates:

    1. INITIALIZATION
       - Loading the DebuggerInterceptor system
       - Configuring log levels and options
       - Setting up the test GUI

    2. LOGGING FUNCTIONS
       - DebugLog() - Information messages
       - DebugWarning() - Warning messages
       - DebugError() - Error messages

    3. ERROR HANDLING
       - Try/catch blocks with error logging
       - Automatic error interception
       - Error details to clipboard

    4. REAL-WORLD SCENARIOS
       - Multi-step operations with progress tracking
       - Function call chains showing stack context
       - File operations with error handling
       - Data structure operations

    5. LOG VIEWER
       - Open with Ctrl+Alt+L
       - Filter by log level
       - Search for messages
       - View full error details
       - Copy errors to clipboard

    TO USE THIS EXAMPLE:
    1. Run this script
    2. Click the test buttons
    3. Open the log viewer (Ctrl+Alt+L or "Show Viewer" button)
    4. Watch as operations are logged in real-time
    5. See errors appear with full context
    6. Filter and search the logs
    7. Copy error details to clipboard

    TIPS:
    - The test GUI shows useful test scenarios
    - Errors are caught and logged, script continues
    - Check ErrorLogs folder for saved log files
    - Each log entry has timestamp and context
    - Stack traces show calling function chain
*/
