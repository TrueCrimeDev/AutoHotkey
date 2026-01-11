#Requires AutoHotkey v2.0
; ============================================================================
; ErrorInterceptor.ahk
; Comprehensive Global Error Handler for AutoHotkey v2
; ============================================================================
; Description: Captures all unhandled runtime errors with detailed reporting
;              via message box and optional file logging. Includes stack trace
;              analysis and multiple error scenario demonstrations.
; ============================================================================

; Include LLM analyzer for intelligent error analysis
#Include LLMAnalyzer.ahk

; ============================================================================
; CONFIGURATION
; ============================================================================
class ErrorConfig {
    static enableLogging := true        ; Set to false to disable file logging
    static logDirectory := A_ScriptDir "\logs"  ; Log file directory
    static showStackTrace := true       ; Include stack trace in message box
    static maxStackDepth := 10          ; Maximum stack frames to display
    static enableLLMAnalysis := true    ; Get Claude AI analysis of errors
    static llmAnalysisTimeout := 5000   ; Max wait for LLM response (ms)
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
        ; Get LLM analysis if enabled
        llmAnalysis := ""
        if (ErrorConfig.enableLLMAnalysis) {
            llmAnalysis := this.GetLLMAnalysis(report)
        }

        ; Create GUI with dark mode title bar support
        errorGui := Gui("+AlwaysOnTop +Owner", "Runtime Error Detected")

        ; Dark mode colors
        darkBg := 0x2d2d2d        ; Dark background
        darkGrey := 0x1e1e1e      ; Dark grey for edit controls
        darkText := 0xE0E0E0      ; Light text

        ; Apply dark mode to GUI background
        errorGui.BackColor := "2d2d2d"
        errorGui.SetFont("s9 cFFE0E0E0", "Consolas")

        ; Apply Windows dark mode theme to title bar and controls
        DllCall("uxtheme\SetWindowTheme", "Ptr", errorGui.hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)

        ; Enable dark mode for Windows 10/11
        DWMWA_USE_IMMERSIVE_DARK_MODE := 19
        if (VerCompare(A_OSVersion, "10.0.18985") >= 0)
            DWMWA_USE_IMMERSIVE_DARK_MODE := 20
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", errorGui.hwnd, "Int", DWMWA_USE_IMMERSIVE_DARK_MODE, "Int*", true, "Int", 4)

        ; Build display content
        displayContent := report
        if (llmAnalysis) {
            displayContent .= "`n`n"
            displayContent .= "╔════════════════════════════════════════════════════════╗`n"
            displayContent .= "║              CLAUDE AI ANALYSIS                        ║`n"
            displayContent .= "╚════════════════════════════════════════════════════════╝`n`n"
            displayContent .= llmAnalysis
        }

        ; Add edit control with dark background
        editCtrl := errorGui.Add("Edit", "r35 w700 ReadOnly", displayContent)
        editCtrl.SetFont("s9 cFFE0E0E0", "Consolas")
        DllCall("uxtheme\SetWindowTheme", "Ptr", editCtrl.hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)

        ; Set edit background color - use BGR format
        static EM_SETBKGNDCOLOR := 0x0443
        bgColorBGR := ((darkGrey & 0xFF) << 16) | (darkGrey & 0xFF00) | ((darkGrey & 0xFF0000) >> 16)
        DllCall("SendMessage", "Ptr", editCtrl.hwnd, "UInt", EM_SETBKGNDCOLOR, "Ptr", 0, "UInt", bgColorBGR)

        ; Also set via Opt to ensure background applies
        editCtrl.Opt("Background" . Format("{:X}", bgColorBGR))

        ; Force redraw
        DllCall("InvalidateRect", "Ptr", editCtrl.hwnd, "Ptr", 0, "Int", true)
        DllCall("UpdateWindow", "Ptr", editCtrl.hwnd)

        ; Add buttons with dark mode theme (no white halo)
        errorGui.SetFont("s9 cFFFFFF", "Segoe UI")

        btnCopy := errorGui.Add("Button", "w60 h30 -BS_AUTOFOCUS", "Copy")
        btnCopy.OnEvent("Click", (*) => this.CopyToClipboard(displayContent, errorGui))
        DllCall("uxtheme\SetWindowTheme", "Ptr", btnCopy.hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        btnCopy.SetFont("cFFFFFF")

        btnClose := errorGui.Add("Button", "w60 h30 x+10 yp -BS_AUTOFOCUS", "Close")
        btnClose.OnEvent("Click", (*) => errorGui.Destroy())
        DllCall("uxtheme\SetWindowTheme", "Ptr", btnClose.hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        btnClose.SetFont("cFFFFFF")

        ; Show GUI with dimensions
        errorGui.Show("w750 h600")
    }

    /**
     * Get LLM analysis of the error
     * @param report - Error report text
     * @return Analysis string from Claude, or empty if failed/timeout
     */
    static GetLLMAnalysis(report) {
        try {
            ; Call LLM analyzer (has built-in timeout)
            analysis := LLMAnalyzer.GetErrorAnalysis(report)
            return analysis ? this.FormatLLMAnalysis(analysis) : ""
        } catch {
            return ""  ; Silently fail
        }
    }

    /**
     * Format LLM analysis for display
     * @param analysis - Raw analysis from Claude
     * @return Formatted analysis text
     */
    static FormatLLMAnalysis(analysis) {
        ; Clean up markdown if present
        ; Use Chr(96) for backtick character (not special in string)
        backtick := Chr(96)
        tripleBacktick := backtick . backtick . backtick
        analysis := StrReplace(analysis, tripleBacktick, "")
        analysis := Trim(analysis)
        return analysis
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
testGui.Add("GroupBox", "xm w500 h100", "Configuration")
configText := testGui.Add("Text", "xm+10 yp+25 w480",
    "File Logging: " (ErrorConfig.enableLogging ? "ENABLED" : "DISABLED") "`n"
    . "Log Directory: " ErrorConfig.logDirectory "`n"
    . "Stack Trace Display: " (ErrorConfig.showStackTrace ? "ENABLED" : "DISABLED") "`n"
    . "LLM Analysis: " (ErrorConfig.enableLLMAnalysis ? "ENABLED" : "DISABLED")
    . (ErrorConfig.enableLLMAnalysis ? " (requires CLAUDE_API_KEY env var)" : ""))

; Info section
testGui.Add("Text", "xm w500", "")
testGui.Add("Text", "xm w500",
    "Note: Click any button to trigger that error scenario.`n"
    . "The error interceptor will display detailed information and optionally log to file.")

; Show GUI
testGui.Show()
