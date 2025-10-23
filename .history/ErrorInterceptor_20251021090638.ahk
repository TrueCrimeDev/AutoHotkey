#Requires AutoHotkey v2.0
; ============================================================================
; ErrorInterceptor.ahk
; Comprehensive Global Error Handler for AutoHotkey v2
; ============================================================================
; Description: Captures all unhandled runtime errors with detailed reporting
;              via message box and optional file logging. Includes stack trace
;              analysis and multiple error scenario demonstrations.
; ============================================================================

; ============================================================================
; CONFIGURATION
; ============================================================================
class ErrorConfig {
    static enableLogging := true        ; Set to false to disable file logging
    static logDirectory := A_ScriptDir "\logs"  ; Log file directory
    static showStackTrace := true       ; Include stack trace in message box
    static maxStackDepth := 10          ; Maximum stack frames to display
}

; ============================================================================
; GLOBAL ERROR INTERCEPTOR CLASS
; ============================================================================
class GlobalErrorInterceptor {
    /**
     * Initialize the global error handler
     * Sets up OnError callback to intercept all unhandled errors
     */
    static Initialize() {
        ; Register global error handler with mode 1 (call and continue)
        OnError(GlobalErrorInterceptor.HandleError.Bind(GlobalErrorInterceptor), 1)

        ; Create log directory if logging is enabled
        if (ErrorConfig.enableLogging) {
            if (!DirExist(ErrorConfig.logDirectory)) {
                try {
                    DirCreate(ErrorConfig.logDirectory)
                } catch Error as e {
                    MsgBox("Warning: Failed to create log directory`n"
                        . ErrorConfig.logDirectory "`n`n"
                        . "Error: " e.Message, "Logger Warning")
                }
            }
        }
    }

    /**
     * Main error handler callback
     * @param exception - The Error object containing error details
     * @param mode - Error handler mode (1 = call handler, continue execution)
     * @return -1 to suppress standard error dialog
     */
    static HandleError(exception, mode) {
        ; Build comprehensive error report
        errorReport := this.BuildErrorReport(exception)

        ; Display error in message box
        this.DisplayErrorDialog(errorReport)

        ; Log to file if enabled
        if (ErrorConfig.enableLogging) {
            this.LogToFile(errorReport)
        }

        ; Return -1 to suppress the default error dialog
        return -1
    }

    /**
     * Build detailed error report from exception object
     * @param exception - The Error object
     * @return Formatted error report string
     */
    static BuildErrorReport(exception) {
        ; Extract error details
        errorType := Type(exception)
        errorMessage := exception.Message
        errorWhat := exception.What
        errorFile := exception.File
        errorLine := exception.Line
        errorExtra := exception.HasProp("Extra") ? exception.Extra : ""
        errorStack := exception.HasProp("Stack") ? exception.Stack : ""

        ; Build header
        report := "╔════════════════════════════════════════════════════════╗`n"
        report .= "║          RUNTIME ERROR INTERCEPTED                     ║`n"
        report .= "╚════════════════════════════════════════════════════════╝`n`n"

        ; Error type and message
        report .= "Error Type: " errorType "`n"
        report .= "Message: " errorMessage "`n"

        ; What (function/property that caused error)
        if (errorWhat) {
            report .= "What: " errorWhat "`n"
        }

        ; File and line information
        report .= "`n── Location ──────────────────────────────────────────`n"
        report .= "File: " errorFile "`n"
        report .= "Line: " errorLine "`n"

        ; Extra information (if available)
        if (errorExtra) {
            report .= "`n── Additional Info ───────────────────────────────────`n"
            report .= errorExtra "`n"
        }

        ; Stack trace
        if (ErrorConfig.showStackTrace && errorStack) {
            report .= "`n── Stack Trace ───────────────────────────────────────`n"
            report .= this.FormatStackTrace(errorStack)
        }

        ; Timestamp
        report .= "`n── Timestamp ─────────────────────────────────────────`n"
        report .= FormatTime(, "yyyy-MM-dd HH:mm:ss") "`n"

        return report
    }

    /**
     * Format stack trace for better readability
     * @param stackTrace - Raw stack trace string
     * @return Formatted stack trace
     */
    static FormatStackTrace(stackTrace) {
        if (!stackTrace) {
            return "(No stack trace available)"
        }

        ; Split stack trace into lines
        lines := StrSplit(stackTrace, "`n", "`r")
        formatted := ""
        frameCount := 0

        for index, line in lines {
            if (line == "" || frameCount >= ErrorConfig.maxStackDepth) {
                continue
            }

            ; Add frame number and indentation
            formatted .= Format("  #{:02d} {}`n", frameCount + 1, Trim(line))
            frameCount++
        }

        if (lines.Length > ErrorConfig.maxStackDepth) {
            formatted .= Format("  ... ({} more frames)`n",
                lines.Length - ErrorConfig.maxStackDepth)
        }

        return formatted ? formatted : "(Stack trace empty)"
    }

    /**
     * Display error dialog with formatted report
     * @param report - Formatted error report string
     */
    static DisplayErrorDialog(report) {
        ; Create custom GUI for better formatting
        errorGui := Gui("+AlwaysOnTop +Owner", "Runtime Error Detected")
        errorGui.SetFont("s9", "Consolas")

        ; Add edit control with error report (read-only)
        editCtrl := errorGui.Add("Edit", "r30 w700 ReadOnly -Wrap vErrorText", report)

        ; Add buttons
        errorGui.SetFont("s9", "Segoe UI")
        btnCopy := errorGui.Add("Button", "w100", "Copy to Clipboard")
        btnCopy.OnEvent("Click", (*) => this.CopyToClipboard(report, errorGui))

        btnClose := errorGui.Add("Button", "w100 x+10", "Close")
        btnClose.OnEvent("Click", (*) => errorGui.Destroy())

        ; Show GUI
        errorGui.Show()
    }

    /**
     * Copy error report to clipboard
     * @param report - Error report text
     * @param gui - GUI object to show feedback
     */
    static CopyToClipboard(report, gui) {
        A_Clipboard := report

        ; Show brief feedback
        originalTitle := gui.Title
        gui.Title := "Copied to Clipboard!"
        SetTimer(() => gui.Title := originalTitle, -1500)
    }

    /**
     * Log error report to timestamped file
     * @param report - Error report text
     */
    static LogToFile(report) {
        try {
            ; Generate log filename with date
            logFile := ErrorConfig.logDirectory
                . "\error_log_"
                . FormatTime(, "yyyy-MM-dd")
                . ".txt"

            ; Prepare log entry with separator
            logEntry := "`n"
                . "════════════════════════════════════════════════════════`n"
                . report
                . "════════════════════════════════════════════════════════`n"

            ; Append to log file
            FileAppend(logEntry, logFile, "UTF-8")

        } catch Error as e {
            ; If logging fails, show warning (but don't interfere with error handling)
            MsgBox("Warning: Failed to write error log`n`n"
                . "Log file: " logFile "`n"
                . "Error: " e.Message, "Logger Warning")
        }
    }
}

; ============================================================================
; INITIALIZE ERROR HANDLER
; ============================================================================
GlobalErrorInterceptor.Initialize()

; ============================================================================
; DEMONSTRATION: ERROR SCENARIO EXAMPLES
; ============================================================================

/**
 * Example error scenarios to test the error interceptor
 * Uncomment the scenario you want to test
 */
class ErrorDemos {
    /**
     * Scenario 1: Division by Zero
     */
    static DivisionByZero() {
        numerator := 100
        denominator := 0
        result := numerator / denominator  ; This will throw an error
        return result
    }

    /**
     * Scenario 2: Undefined Variable Access
     */
    static UndefinedVariable() {
        ; Try to access a variable that doesn't exist
        #Warn VarUnset, Off  ; Suppress warning - intentional error demo
        return nonExistentVariable
    }

    /**
     * Scenario 3: Type Mismatch Error
     */
    static TypeMismatch() {
        stringValue := "Hello"
        numberValue := 42
        ; Try to perform invalid operation
        return stringValue + numberValue  ; This may cause issues depending on context
    }

    /**
     * Scenario 4: Array Index Out of Bounds
     */
    static ArrayIndexError() {
        myArray := [1, 2, 3, 4, 5]
        ; Try to access invalid index
        return myArray[99]  ; Index out of bounds
    }

    /**
     * Scenario 5: Map Key Not Found
     */
    static MapKeyError() {
        myMap := Map("key1", "value1", "key2", "value2")
        ; Try to access non-existent key without Has() check
        return myMap["nonExistentKey"]
    }

    /**
     * Scenario 6: File Operation Error
     */
    static FileOperationError() {
        ; Try to read from non-existent file
        content := FileRead("C:\NonExistent\Path\File.txt")
        return content
    }

    /**
     * Scenario 7: Custom Error Throwing
     */
    static CustomErrorThrow() {
        throw ValueError("This is a custom error demonstration",
            -1, "Custom error with extra details")
    }

    /**
     * Scenario 8: Nested Function Calls (Stack Trace Demo)
     */
    static NestedCallsDemo() {
        return this.Level1()
    }

    static Level1() {
        return this.Level2()
    }

    static Level2() {
        return this.Level3()
    }

    static Level3() {
        return this.Level4()
    }

    static Level4() {
        ; This will create a nice stack trace
        #Warn VarUnset, Off  ; Suppress warning - intentional error demo
        undefinedFunction()
        return "Should never reach here"
    }

    /**
     * Scenario 9: Property Access Error
     */
    static PropertyAccessError() {
        obj := {name: "Test"}
        ; Try to access non-existent property
        return obj.nonExistentProperty.deepProperty
    }

    /**
     * Scenario 10: Method Call Error
     */
    static MethodCallError() {
        str := "Hello World"
        ; Try to call with wrong parameters
        return str.SubStr()  ; Missing required parameter
    }
}

; ============================================================================
; GUI TEST INTERFACE
; ============================================================================

; Create test GUI
testGui := Gui(, "Error Interceptor Test Suite")
testGui.SetFont("s10")

; Header
testGui.Add("Text", "w500", "Select an error scenario to test the global error interceptor:")
testGui.Add("Text", "w500", "")

; Error scenario buttons
btnDivZero := testGui.Add("Button", "w240", "1. Division by Zero")
btnDivZero.OnEvent("Click", (*) => ErrorDemos.DivisionByZero())

btnUndef := testGui.Add("Button", "w240 x+10", "2. Undefined Variable")
btnUndef.OnEvent("Click", (*) => ErrorDemos.UndefinedVariable())

btnType := testGui.Add("Button", "w240 xm", "3. Type Mismatch")
btnType.OnEvent("Click", (*) => ErrorDemos.TypeMismatch())

btnArray := testGui.Add("Button", "w240 x+10", "4. Array Index Error")
btnArray.OnEvent("Click", (*) => ErrorDemos.ArrayIndexError())

btnMap := testGui.Add("Button", "w240 xm", "5. Map Key Not Found")
btnMap.OnEvent("Click", (*) => ErrorDemos.MapKeyError())

btnFile := testGui.Add("Button", "w240 x+10", "6. File Operation Error")
btnFile.OnEvent("Click", (*) => ErrorDemos.FileOperationError())

btnCustom := testGui.Add("Button", "w240 xm", "7. Custom Error Throw")
btnCustom.OnEvent("Click", (*) => ErrorDemos.CustomErrorThrow())

btnNested := testGui.Add("Button", "w240 x+10", "8. Nested Calls (Stack Trace)")
btnNested.OnEvent("Click", (*) => ErrorDemos.NestedCallsDemo())

btnProp := testGui.Add("Button", "w240 xm", "9. Property Access Error")
btnProp.OnEvent("Click", (*) => ErrorDemos.PropertyAccessError())

btnMethod := testGui.Add("Button", "w240 x+10", "10. Method Call Error")
btnMethod.OnEvent("Click", (*) => ErrorDemos.MethodCallError())

; Configuration display
testGui.Add("Text", "xm w500", "")
testGui.Add("GroupBox", "xm w500 h80", "Configuration")
configText := testGui.Add("Text", "xm+10 yp+25 w480",
    "File Logging: " (ErrorConfig.enableLogging ? "ENABLED" : "DISABLED") "`n"
    . "Log Directory: " ErrorConfig.logDirectory "`n"
    . "Stack Trace Display: " (ErrorConfig.showStackTrace ? "ENABLED" : "DISABLED"))

; Info section
testGui.Add("Text", "xm w500", "")
testGui.Add("Text", "xm w500",
    "Note: Click any button to trigger that error scenario.`n"
    . "The error interceptor will display detailed information and optionally log to file.")

; Show GUI
testGui.Show()
