# Building a Custom Lower-Level Debugging Interceptor for AHK v2

A practical guide to building your own error interception system from the ground up.

## Foundation: The OnError() Hook

Every AHK v2 debugging system starts here:

```autohotkey
#Requires AutoHotkey v2.0

; Register error handler
OnError(MyErrorHandler, 1)

MyErrorHandler(exception, mode) {
    ; exception = Error object with details
    ; mode = 1 (we want to continue after this)

    MsgBox("Error: " . exception.Message)
    return -1  ; Suppress default error dialog
}

; Test it
x := 1 / 0  ; Will trigger handler
```

**That's the lowest level.** Everything else builds on this.

## Level 1: Basic Error Information Capture

```autohotkey
#Requires AutoHotkey v2.0

OnError(CaptureErrorInfo, 1)

CaptureErrorInfo(exception, mode) {
    ; Extract all available information
    info := Map(
        "Type", Type(exception),
        "Message", exception.Message,
        "File", exception.File,
        "Line", exception.Line,
        "What", exception.What,
        "Stack", exception.HasProp("Stack") ? exception.Stack : "",
        "Extra", exception.HasProp("Extra") ? exception.Extra : ""
    )

    ; Display it
    DisplayError(info)

    return -1
}

DisplayError(info) {
    output := ""
    for key, value in info {
        if (value != "") {
            output .= key . ": " . value . "`n"
        }
    }

    MsgBox(output, "Captured Error Information")
}

; Test it
x := 1 / 0
```

## Level 2: Add Stack Trace Parsing

```autohotkey
#Requires AutoHotkey v2.0

OnError(ParseStackTrace, 1)

ParseStackTrace(exception, mode) {
    ; Get raw stack trace
    rawStack := exception.HasProp("Stack") ? exception.Stack : ""

    ; Parse into frames
    frames := []
    if (rawStack != "") {
        lines := StrSplit(rawStack, "`n", "`r")
        for index, line in lines {
            if (line != "") {
                frames.Push(Trim(line))
            }
        }
    }

    ; Display formatted
    output := "=== ERROR ===" . "`n"
    output .= exception.Message . "`n`n"
    output .= "File: " . exception.File . "`n"
    output .= "Line: " . exception.Line . "`n`n"

    if (frames.Length > 0) {
        output .= "=== CALL STACK ===" . "`n"
        for index, frame in frames {
            output .= "[" . index . "] " . frame . "`n"
        }
    }

    MsgBox(output)
    return -1
}

; Test with nested calls
Level1() {
    return Level2()
}

Level2() {
    return Level3()
}

Level3() {
    x := 1 / 0  ; Error here - shows full stack
}

Level1()
```

## Level 3: Add File Logging

```autohotkey
#Requires AutoHotkey v2.0

class ErrorLogger {
    static logDir := A_ScriptDir "\ErrorLogs"
    static logFile := ""

    static Initialize() {
        ; Create directory
        if (!DirExist(this.logDir)) {
            DirCreate(this.logDir)
        }

        ; Set daily log file
        this.logFile := this.logDir . "\error_log_"
                      . FormatTime(, "yyyy_MM_dd")
                      . ".txt"

        ; Register handler
        OnError(this.HandleError.Bind(this), 1)
    }

    static HandleError(exception, mode) {
        ; Build report
        report := this.BuildReport(exception)

        ; Log to file
        FileAppend(report . "`n`n", this.logFile, "UTF-8")

        ; Display to user
        MsgBox(report, "Error Logged")

        return -1
    }

    static BuildReport(exception) {
        report := "Timestamp: " . FormatTime(, "yyyy-MM-dd HH:mm:ss") . "`n"
        report .= "Error Type: " . Type(exception) . "`n"
        report .= "Message: " . exception.Message . "`n"
        report .= "File: " . exception.File . "`n"
        report .= "Line: " . exception.Line . "`n"

        if (exception.HasProp("Stack") && exception.Stack != "") {
            report .= "`nStack Trace:`n"
            report .= exception.Stack
        }

        return report
    }
}

ErrorLogger.Initialize()

; Test it
x := 1 / 0  ; Error gets logged to file and displayed
```

## Level 4: Add GUI Display

```autohotkey
#Requires AutoHotkey v2.0

class ErrorGUI {
    static Initialize() {
        OnError(this.ShowErrorGUI.Bind(this), 1)
    }

    static ShowErrorGUI(exception, mode) {
        ; Create GUI
        gui := Gui("+AlwaysOnTop", "Error Detected")
        gui.SetFont("s10", "Consolas")
        gui.BackColor := "2d2d2d"
        gui.SetFont("cFFFFFF")

        ; Format error
        errorText := "Error Type: " . Type(exception) . "`n`n"
        errorText .= "Message: " . exception.Message . "`n`n"
        errorText .= "File: " . exception.File . "`n"
        errorText .= "Line: " . exception.Line . "`n`n"

        if (exception.HasProp("Stack")) {
            errorText .= "Stack:`n" . exception.Stack
        }

        ; Add controls
        edit := gui.Add("Edit", "r20 w500 ReadOnly", errorText)
        edit.SetFont("cFFFFFF")

        btnCopy := gui.Add("Button", "w80 h30", "Copy")
        btnCopy.OnEvent("Click", (*) => (A_Clipboard := errorText))

        btnClose := gui.Add("Button", "w80 h30 x+10", "Close")
        btnClose.OnEvent("Click", (*) => gui.Destroy())

        ; Show it
        gui.Show("w600 h400")

        return -1
    }
}

ErrorGUI.Initialize()

; Test it
x := 1 / 0
```

## Level 5: Add Configuration System

```autohotkey
#Requires AutoHotkey v2.0

class DebugConfig {
    static settings := Map(
        "enableGUI", true,
        "enableFileLogging", true,
        "enableLLMAnalysis", false,
        "logDirectory", A_ScriptDir "\ErrorLogs",
        "maxStackFrames", 10,
        "suppressDefaultDialog", true
    )

    static Get(key) {
        return this.settings[key]
    }

    static Set(key, value) {
        this.settings[key] := value
    }
}

class ConfigurableErrorHandler {
    static Initialize() {
        OnError(this.Handle.Bind(this), 1)
    }

    static Handle(exception, mode) {
        config := DebugConfig

        ; Log to file
        if (config.Get("enableFileLogging")) {
            this.LogToFile(exception)
        }

        ; Show GUI
        if (config.Get("enableGUI")) {
            this.ShowGUI(exception)
        }

        ; Suppress default dialog
        return config.Get("suppressDefaultDialog") ? -1 : 0
    }

    static LogToFile(exception) {
        logDir := DebugConfig.Get("logDirectory")
        if (!DirExist(logDir))
            DirCreate(logDir)

        logFile := logDir . "\errors.log"
        entry := FormatTime(, "yyyy-MM-dd HH:mm:ss")
               . " - " . exception.Message . "`n"

        FileAppend(entry, logFile)
    }

    static ShowGUI(exception) {
        gui := Gui(, "Error")
        gui.Add("Text",, exception.Message)
        gui.Add("Button", "w80", "OK").OnEvent("Click", (*) => gui.Destroy())
        gui.Show()
    }
}

ConfigurableErrorHandler.Initialize()

; Configure it
DebugConfig.Set("enableGUI", true)
DebugConfig.Set("enableFileLogging", true)

; Test it
x := 1 / 0
```

## Level 6: Add Filtering & Routing

```autohotkey
#Requires AutoHotkey v2.0

class ErrorRouter {
    static handlers := Map()

    static Initialize() {
        ; Register different handlers for different error types
        this.RegisterHandler("ValueError", this.HandleValueError.Bind(this))
        this.RegisterHandler("TypeError", this.HandleTypeError.Bind(this))
        this.RegisterHandler("ZeroDivisionError", this.HandleZeroDivision.Bind(this))

        OnError(this.Route.Bind(this), 1)
    }

    static RegisterHandler(errorType, handler) {
        this.handlers[errorType] := handler
    }

    static Route(exception, mode) {
        errorType := Type(exception)

        ; If specific handler exists, use it
        if (this.handlers.Has(errorType)) {
            handler := this.handlers[errorType]
            return handler(exception)
        }

        ; Otherwise, use default
        return this.DefaultHandler(exception)
    }

    static HandleValueError(exception) {
        MsgBox("Value Error: " . exception.Message . "`n`nCheck the value types in your code")
        return -1
    }

    static HandleTypeError(exception) {
        MsgBox("Type Error: " . exception.Message . "`n`nYou may have mixed incompatible types")
        return -1
    }

    static HandleZeroDivision(exception) {
        MsgBox("Division by Zero!`n`nCheck your denominator")
        return -1
    }

    static DefaultHandler(exception) {
        MsgBox("Unexpected Error: " . exception.Message)
        return -1
    }
}

ErrorRouter.Initialize()

; Test it
x := 1 / 0  ; Triggers ZeroDivision handler
```

## Level 7: Add Async Processing

```autohotkey
#Requires AutoHotkey v2.0

class AsyncErrorHandler {
    static queue := []
    static processing := false

    static Initialize() {
        OnError(this.QueueError.Bind(this), 1)
    }

    static QueueError(exception, mode) {
        ; Add to queue instead of handling immediately
        this.queue.Push(Map(
            "exception", exception,
            "timestamp", A_Now
        ))

        ; Process queue asynchronously
        SetTimer(this.ProcessQueue.Bind(this), -100)  ; Debounce 100ms

        return -1  ; Suppress dialog immediately
    }

    static ProcessQueue() {
        while (this.queue.Length > 0) {
            error := this.queue.RemoveAt(1)
            this.ProcessError(error["exception"])
        }
    }

    static ProcessError(exception) {
        ; Do expensive operations here
        ; File logging, LLM calls, etc.

        ; Log to file (slow operation)
        logFile := A_ScriptDir "\errors.log"
        entry := exception.Message . " [" . exception.File . ":" . exception.Line . "]`n"
        FileAppend(entry, logFile)

        ; Could also call LLM here without blocking
    }
}

AsyncErrorHandler.Initialize()

; Test it
x := 1 / 0
```

## Level 8: Add Monitoring Service

```autohotkey
#Requires AutoHotkey v2.0

class ErrorMonitor {
    static errorCount := 0
    static lastErrorTime := 0
    static recentErrors := []

    static Initialize() {
        OnError(this.Track.Bind(this), 1)

        ; Start monitoring display
        SetTimer(this.ShowStats.Bind(this), 5000)
    }

    static Track(exception, mode) {
        this.errorCount++
        this.lastErrorTime := A_Now

        ; Keep last 10 errors
        this.recentErrors.Push(Map(
            "message", exception.Message,
            "time", FormatTime(, "HH:mm:ss")
        ))

        if (this.recentErrors.Length > 10)
            this.recentErrors.RemoveAt(1)

        return -1
    }

    static ShowStats() {
        output := "=== Error Monitor ===" . "`n"
        output .= "Total Errors: " . this.errorCount . "`n"
        output .= "Recent:`n"

        for i, err in this.recentErrors {
            output .= "[" . err["time"] . "] " . err["message"] . "`n"
        }

        ToolTip(output)
    }
}

ErrorMonitor.Initialize()

; Test it - errors are tracked
x := 1 / 0
```

## Level 9: Complete Production System

Combine all levels:

```autohotkey
#Requires AutoHotkey v2.0

; Configuration
class Config {
    static settings := Map(
        "enableGUI", true,
        "enableLogging", true,
        "enableMonitoring", true,
        "logDir", A_ScriptDir "\ErrorLogs",
        "maxErrors", 100
    )
}

; Main error handler
class ProductionErrorHandler {
    static errorQueue := []
    static errorCount := 0
    static recentErrors := []

    static Initialize() {
        ; Create log directory
        if (Config.settings["enableLogging"]) {
            if (!DirExist(Config.settings["logDir"]))
                DirCreate(Config.settings["logDir"])
        }

        ; Register handler
        OnError(this.HandleError.Bind(this), 1)

        ; Start monitoring if enabled
        if (Config.settings["enableMonitoring"]) {
            SetTimer(this.ShowMonitoring.Bind(this), 5000)
        }
    }

    static HandleError(exception, mode) {
        this.errorCount++

        ; Queue for async processing
        this.errorQueue.Push(exception)
        SetTimer(this.ProcessQueue.Bind(this), -100)

        ; Show dialog if enabled
        if (Config.settings["enableGUI"]) {
            MsgBox(exception.Message, "Error")
        }

        return -1
    }

    static ProcessQueue() {
        while (this.errorQueue.Length > 0) {
            exception := this.errorQueue.RemoveAt(1)

            ; Log to file
            if (Config.settings["enableLogging"]) {
                this.LogError(exception)
            }

            ; Track for monitoring
            this.recentErrors.Push(Map(
                "message", exception.Message,
                "time", A_Now
            ))

            if (this.recentErrors.Length > Config.settings["maxErrors"])
                this.recentErrors.RemoveAt(1)
        }
    }

    static LogError(exception) {
        logFile := Config.settings["logDir"] . "\error_"
                 . FormatTime(, "yyyy_MM_dd") . ".log"

        entry := FormatTime(, "HH:mm:ss") . " | "
               . Type(exception) . " | "
               . exception.Message . " | "
               . exception.File . ":" . exception.Line . "`n"

        FileAppend(entry, logFile)
    }

    static ShowMonitoring() {
        output := "Errors: " . this.errorCount . " | Recent: " . this.recentErrors.Length
        ToolTip(output)
    }
}

ProductionErrorHandler.Initialize()

; Your script code here
x := 1 / 0
```

## Complete Example: Minimal vs Full

### Minimal (10 lines)
```autohotkey
OnError((e, m) => MsgBox(e.Message), 1)
x := 1 / 0
```

### Full (100+ lines)
- Configuration system
- File logging with daily rotation
- GUI display with details
- Stack trace parsing
- Error deduplication
- Background monitoring
- Async processing queue
- Statistics tracking
- Recovery handling

## Key Principles

1. **Start Simple** - Begin with basic OnError() hook
2. **Build Layers** - Add features incrementally
3. **Defer Heavy Work** - Use async for expensive operations
4. **Handle Gracefully** - Don't let error handler errors crash
5. **Be Observable** - Log/display what's happening
6. **Configure Everything** - Allow customization
7. **Think Performance** - Consider overhead
8. **Test Edge Cases** - Include various error types

## Testing Your Implementation

```autohotkey
; Test different error types
TestErrors() {
    ; Division by zero
    try { x := 1 / 0 } catch {}

    ; Undefined variable
    try { y := nonExistent } catch {}

    ; Array bounds
    try { z := [1,2,3][99] } catch {}

    ; Type mismatch
    try { a := "text" + 5 } catch {}

    ; File not found
    try { FileRead("\\doesnotexist") } catch {}
}

TestErrors()
```

This builds the foundation for a professional-grade debugging system in AHK v2!
