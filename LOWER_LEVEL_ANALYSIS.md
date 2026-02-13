# Lower-Level AHK v2 Debugging Interception System Analysis

## Overview of the System Architecture

The AutoHotkey repository contains a sophisticated **three-layer error interception and analysis system**:

```
Layer 3: LLM Analysis (AI-Powered)
         ├─ LLMAnalyzer.ahk
         │  └─ Sends errors to Claude API for intelligent analysis
         │
Layer 2: Error Interception (Core)
         ├─ ErrorInterceptor.ahk (Primary handler)
         ├─ RunWithErrorHandler.ahk (Wrapper executor)
         │
Layer 1: Monitoring & Aggregation (Background)
         └─ GlobalErrorMonitor.ahk
            └─ Watches logs, shows notifications
```

## Layer 1: Core Error Interception (ErrorInterceptor.ahk)

### The Foundation: OnError() Hook

```autohotkey
class GlobalErrorInterceptor {
    static Initialize() {
        ; Register global error handler with mode 1
        OnError(GlobalErrorInterceptor.HandleError.Bind(GlobalErrorInterceptor), 1)
        ;         ↑
        ;         The lowest-level hook in AHK v2
        ;
        ; Mode 1 = Call handler AND CONTINUE execution (don't exit)
        ; Mode -1 = Suppress standard error dialog
        ; .Bind() = Bind the method to the class instance for proper context
    }
}
```

**Critical Detail**: The mode parameter (second arg):
- **1** = Call handler, continue (allows recovery)
- **-1** = Continue (suppress dialog)
- Default = Call handler, exit script

### Lower-Level Implementation Details

#### 1. Exception Object Extraction

The error handler receives an `Error` object with these properties:

```autohotkey
static HandleError(exception, mode) {
    errorType := Type(exception)           ; Error class name
    errorMessage := exception.Message       ; Human-readable message
    errorWhat := exception.What             ; Function/property causing error
    errorFile := exception.File             ; Source file path
    errorLine := exception.Line             ; Line number (1-indexed)
    errorExtra := exception.Extra           ; Custom data
    errorStack := exception.Stack           ; Full stack trace
}
```

**How to Access**: Exception is an object with properties—AHK v2 automatically passes it.

#### 2. Stack Trace Parsing

```autohotkey
static FormatStackTrace(stackTrace) {
    lines := StrSplit(stackTrace, "`n", "`r")  ; Split by newline
    frameCount := 0

    for index, line in lines {
        if (line == "" || frameCount >= ErrorConfig.maxStackDepth)
            continue

        ; Format each frame with frame number
        formatted .= Format("  #{:02d} {}`n", frameCount + 1, Trim(line))
        frameCount++
    }

    return formatted
}
```

**What it does**: Converts raw stack trace into numbered frames.

**Stack trace format from AHK v2**:
```
Called from "FunctionName" (filename.ahk:123)
Called from "CallerFunction" (filename.ahk:456)
...
```

### Lower-Level Mechanisms

#### Windows API Integration for Dark Mode

```autohotkey
; Windows 10 theme attribute (immersive dark mode)
DWMWA_USE_IMMERSIVE_DARK_MODE := 19  ; Before build 18985
; or
DWMWA_USE_IMMERSIVE_DARK_MODE := 20  ; Build 18985+

; Apply dark mode to window
DllCall("dwmapi\DwmSetWindowAttribute",
    "Ptr", errorGui.hwnd,           ; Window handle
    "Int", DWMWA_USE_IMMERSIVE_DARK_MODE,  ; Attribute type
    "Int*", true,                   ; Enable dark mode
    "Int", 4)                       ; Size of value
```

**Lower-Level Detail**: Uses Windows Desktop Window Manager (DWM) API to apply OS-level theming.

#### Edit Control Coloring via SendMessage

```autohotkey
static EM_SETBKGNDCOLOR := 0x0443  ; Edit control message

bgColorBGR := ((darkGrey & 0xFF) << 16) |  ; BGR format (not RGB)
              (darkGrey & 0xFF00) |
              ((darkGrey & 0xFF0000) >> 16)

DllCall("SendMessage",
    "Ptr", editCtrl.hwnd,           ; Control handle
    "UInt", EM_SETBKGNDCOLOR,       ; Message ID
    "Ptr", 0,                       ; wParam (unused)
    "UInt", bgColorBGR)             ; lParam (color in BGR)
```

**Lower-Level Detail**: Windows messages use BGR (not RGB) for colors. Must swap bytes.

#### InvalidateRect & UpdateWindow

```autohotkey
; Force redraw of control
DllCall("InvalidateRect",
    "Ptr", editCtrl.hwnd,           ; Control to invalidate
    "Ptr", 0,                       ; Entire client area
    "Int", true)                    ; Erase background

; Wait for paint message to process
DllCall("UpdateWindow", "Ptr", editCtrl.hwnd)
```

**Why needed**: GUI elements may not immediately reflect color changes; force OS to repaint.

## Layer 2: Error Logging Infrastructure

### Structured Error Reporting

```autohotkey
static BuildErrorReport(exception) {
    report := "╔════════════════════════════════════════════════════════╗`n"
    report .= "║          RUNTIME ERROR INTERCEPTED                     ║`n"
    report .= "╚════════════════════════════════════════════════════════╝`n`n"

    report .= "Error Type: " . Type(exception) . "`n"
    report .= "Message: " . exception.Message . "`n"
    report .= "What: " . exception.What . "`n"
    report .= "File: " . exception.File . "`n"
    report .= "Line: " . exception.Line . "`n"

    ; Include stack trace if available
    if (ErrorConfig.showStackTrace && exception.HasProp("Stack")) {
        report .= "`n── Stack Trace ───────────────────────────────────────`n"
        report .= this.FormatStackTrace(exception.Stack)
    }

    report .= "`n── Timestamp ─────────────────────────────────────────`n"
    report .= FormatTime(, "yyyy-MM-dd HH:mm:ss") . "`n"

    return report
}
```

### File Logging with Timestamped Entries

```autohotkey
static LogToFile(report) {
    try {
        ; Create daily log file
        logFile := ErrorConfig.logDirectory
            . "\error_log_"
            . FormatTime(, "yyyy-MM-dd")
            . ".txt"

        ; Format with separators for readability
        logEntry := "`n"
            . "════════════════════════════════════════════════════════`n"
            . report
            . "════════════════════════════════════════════════════════`n"

        ; Append to file (creates if doesn't exist)
        FileAppend(logEntry, logFile, "UTF-8")

    } catch Error as e {
        MsgBox("Warning: Failed to write error log`n`n"
            . "Log file: " logFile "`n"
            . "Error: " e.Message, "Logger Warning")
    }
}
```

**Key Features**:
- Uses daily rotation (one file per day)
- UTF-8 encoding for proper character support
- Separators for readability
- Graceful error handling if write fails

## Layer 3: Wrapper Execution Pattern

### RunWithErrorHandler.ahk - The Key Innovation

This script demonstrates a **critical pattern**:

```autohotkey
#Requires AutoHotkey v2.0

; Step 1: Include error handler BEFORE target script
#Include ErrorInterceptor.ahk

; Step 2: Get target script from arguments
targetScript := A_Args[1]

; Step 3: Execute target script in same process
#Include %targetScript%
```

**Why this works**:
- `#Include` is processed at script load time
- ErrorInterceptor.ahk runs first, sets up `OnError()` hook
- When target script runs, hook is already active
- Any errors in target script get caught

**Process Flow**:

```
RunWithErrorHandler.ahk starts
    ↓
#Include ErrorInterceptor.ahk (FIRST)
    ↓
GlobalErrorInterceptor.Initialize()
    └─ OnError() hook installed
    ↓
#Include %targetScript% (SECOND)
    ↓
Target script runs with error handler active
    ↓
If error occurs → Hook catches it → Report displayed
```

### Command-Line Usage Pattern

```bash
AutoHotkey64.exe RunWithErrorHandler.ahk "C:\Path\To\YourScript.ahk" arg1 arg2
```

**How arguments are passed**:

```autohotkey
; Original A_Args
A_Args[1] = "C:\Path\To\YourScript.ahk"
A_Args[2] = "arg1"
A_Args[3] = "arg2"

; After processing by RunWithErrorHandler
A_Args[1] = "arg1"  ; Script path removed
A_Args[2] = "arg2"  ; Remaining args passed to target
```

## Layer 4: Background Monitoring (GlobalErrorMonitor.ahk)

### File-Based Polling System

```autohotkey
CheckForNewErrors() {
    if (!isMonitoring)
        return

    ; Check all log files in directory
    Loop Files, MonitorConfig.logDirectory "\error_log_*.txt" {
        logFile := A_LoopFileFullPath

        ; Check if file was modified since last check
        if (A_LoopFileTimeModified > lastLogCheck) {
            ProcessLogFile(logFile)
        }
    }

    lastLogCheck := A_Now
}
```

**Polling Strategy**:
- Timer-based checking (every 2 seconds)
- Only re-processes modified files (faster)
- Stores processed error hashes to avoid duplicates

### Error Hash Deduplication

```autohotkey
GetErrorHash(text) {
    ; Hash first 200 characters to create unique ID
    hashText := SubStr(text, 1, 200)
    hash := 0

    Loop Parse hashText {
        ; Simple rolling hash algorithm
        hash := (hash * 31 + Ord(A_LoopField)) & 0xFFFFFFFF
    }

    return hash
}
```

**Why hashing**: Prevents showing same error notification multiple times.

### Tray Icon Integration

```autohotkey
; Use Windows built-in icon from imageres.dll
TraySetIcon("imageres.dll", 234)  ; Shield icon (security-related)

A_TrayMenu.Add("Open Log Directory", (*) => Run(MonitorConfig.logDirectory))
A_TrayMenu.Add("View Recent Errors", (*) => ShowRecentErrors())
A_TrayMenu.Add("Pause Monitoring", (*) => ToggleMonitoring())
```

## Layer 5: AI-Powered Analysis (LLMAnalyzer.ahk)

### HTTP-Based API Communication

```autohotkey
static CallClaudeAPI(prompt) {
    ; Create COM object for HTTP requests
    http := ComObject("WinHttp.WinHttpRequest.5.1")

    try {
        ; Open async connection
        http.Open("POST", "https://api.anthropic.com/v1/messages", false)

        ; Set headers
        http.SetRequestHeader("Content-Type", "application/json")
        http.SetRequestHeader("x-api-key", this.apiKey)
        http.SetRequestHeader("anthropic-version", "2023-06-01")

        ; Build request body
        requestBody := this.BuildRequestBody(prompt)

        ; Send synchronously (false = blocking)
        http.Send(requestBody)

        ; Check response status
        if (http.Status != 200)
            return ""

        ; Parse JSON response
        response := this.ParseResponse(http.ResponseText)
        return response

    } finally {
        http := ""  ; Cleanup COM object
    }
}
```

**Lower-Level Details**:
- Uses WinHttp COM object (Windows native)
- Synchronous call (blocks until response)
- HTTP 200 = success
- Other status codes treated as failure

### JSON Escaping for Proper Payload

```autohotkey
static EscapeJson(str) {
    ; Must escape for valid JSON
    quote := Chr(34)  ; "
    str := StrReplace(str, "\", "\\")
    str := StrReplace(str, quote, "\" . quote)
    str := StrReplace(str, "`n", "\n")
    str := StrReplace(str, "`r", "\r")
    str := StrReplace(str, "`t", "\t")
    return str
}
```

**Critical**: Without proper escaping, JSON becomes invalid.

### Response Parsing

```autohotkey
static ParseResponse(responseText) {
    ; Extract "text" field from Claude's JSON response
    if (RegExMatch(responseText, '"text"\s*:\s*"([^"]*(?:\\.[^"]*)*)"', &match)) {
        text := match[1]
        ; Unescape JSON escapes
        text := StrReplace(text, "\n", "`n")
        text := StrReplace(text, "\" . Chr(34), Chr(34))
        return Trim(text)
    }

    return ""
}
```

## Complete Data Flow

```
User Script Encounters Error
    │
    ├─ AHK v2 Runtime detects error
    │
    ├─ Throws Error object with:
    │  ├─ Message
    │  ├─ File
    │  ├─ Line
    │  ├─ What (function/property)
    │  └─ Stack (call chain)
    │
    └─ OnError() hook fires
        │
        ├─ GlobalErrorInterceptor.HandleError()
        │  │
        │  ├─ BuildErrorReport()
        │  │  ├─ Extract exception properties
        │  │  ├─ FormatStackTrace()
        │  │  └─ Add timestamp
        │  │
        │  ├─ DisplayErrorDialog()
        │  │  ├─ Format GUI with dark mode
        │  │  ├─ Check for LLM analysis
        │  │  │  └─ Call LLMAnalyzer.GetErrorAnalysis()
        │  │  │     ├─ Build prompt
        │  │  │     ├─ Call Claude API (HTTP)
        │  │  │     └─ Parse response
        │  │  └─ Show in window
        │  │
        │  └─ LogToFile()
        │     └─ Append to daily log file
        │
        └─ GlobalErrorMonitor.ahk (background)
           │
           ├─ Timer checks log files every 2 seconds
           ├─ Hashes errors to deduplicate
           ├─ Shows tray notifications
           └─ Maintains recent error list
```

## Key Lower-Level Mechanisms

### 1. OnError() Hook with Mode Control

```autohotkey
OnError(callbackFn, mode)
; mode 1 = Call & Continue (allows recovery)
; mode -1 = Silent (suppress dialog)
```

**AHK v2 Specific**: This is the **only way to intercept all errors** in v2.

### 2. Exception Object Properties

**Always Available**:
- `exception.Message` - Error message string
- `exception.File` - Source file path
- `exception.Line` - Line number
- `exception.What` - Function/property name

**Sometimes Available**:
- `exception.Stack` - Call stack (may be empty)
- `exception.Extra` - Custom error data
- `exception.HasProp()` - Check property existence

### 3. Windows API Integration

**Key APIs Used**:
- `dwmapi\DwmSetWindowAttribute` - Dark theme
- `SendMessage` - GUI control messages
- `InvalidateRect` - Force repaint
- `UpdateWindow` - Process paint messages
- `uxtheme\SetWindowTheme` - Theme application

### 4. COM Object HTTP Requests

```autohotkey
ComObject("WinHttp.WinHttpRequest.5.1")
; Built into Windows, no external dependencies
```

**Why**: No need for external libraries; Windows provides HTTP directly.

### 5. File Timestamp Comparison

```autohotkey
A_LoopFileTimeModified  ; YYYYMMDDHH24MISS format
; Can be compared with > < operators
```

**Allows**: Efficient polling without re-reading unchanged files.

## Creating Your Own Lower-Level Interceptor

### Minimal Implementation (10 lines)

```autohotkey
#Requires AutoHotkey v2.0

OnError(GlobalErrorHandler, 1)  ; Hook + continue

GlobalErrorHandler(exception, mode) {
    msg := "Error: " . exception.Message
         . "`nFile: " . exception.File
         . "`nLine: " . exception.Line

    MsgBox(msg)
    return -1  ; Suppress default dialog
}

; Your code here
x := 1 / 0  ; Will be caught
```

### Production Implementation (100+ lines)

Add these layers:
1. Configuration system
2. File logging
3. Stack trace parsing
4. GUI display
5. LLM analysis
6. Background monitoring
7. Error deduplication
8. Log rotation

## Performance Considerations

### OnError() Hook
- **Cost**: Negligible (only runs on error)
- **Placement**: Should be at script start
- **Scope**: Global (affects all errors in script)

### Stack Trace Generation
- **Cost**: Depends on call depth
- **Typical**: <10ms for 10 levels deep
- **Limit**: ErrorConfig.maxStackDepth to control

### LLM Analysis
- **Cost**: 5-10 seconds (HTTP request)
- **Timeout**: 5000ms to prevent blocking
- **Optional**: Can be disabled

### File Logging
- **Cost**: Depends on disk speed
- **Async**: Consider async writes for high volume
- **Rotation**: Daily files prevent huge files

### Background Monitoring
- **Cost**: 2 second check interval
- **Memory**: Stores ~50 recent errors
- **CPU**: <1% while waiting

## Best Practices for Lower-Level Debugging

1. **Always include error handler at script start**
   ```autohotkey
   #Requires AutoHotkey v2.0
   OnError(MyErrorHandler, 1)  ; First thing!
   ```

2. **Use try/catch for known risky operations**
   ```autohotkey
   try {
       result := FileRead(path)
   } catch as err {
       ; Handle gracefully
   }
   ```

3. **Return -1 to suppress default dialog**
   ```autohotkey
   return -1  ; Cleaner than letting error dialog appear
   ```

4. **Include stack traces in logs**
   ```autohotkey
   if (exception.HasProp("Stack")) {
       logEntry .= exception.Stack
   }
   ```

5. **Use mode 1 to allow recovery**
   ```autohotkey
   OnError(handler, 1)  ; Continues instead of exiting
   ```

## Limitations & Workarounds

### Can't Catch Syntax Errors
- **Issue**: Syntax errors occur at load time
- **Workaround**: Use `#Include` pattern (RunWithErrorHandler)

### Can't Catch Some AHK Internal Errors
- **Issue**: Some errors terminate immediately
- **Workaround**: Wrap script execution, catch at wrapper level

### Stack Trace May Be Incomplete
- **Issue**: Deep recursion truncates stack
- **Workaround**: Limit recursion depth or use maxStackDepth

### LLM Analysis Has Latency
- **Issue**: HTTP requests take time
- **Workaround**: Show basic dialog immediately, add AI analysis async

## Complete Example: Production-Ready Handler

```autohotkey
#Requires AutoHotkey v2.0

class DebugHandler {
    static config := Map(
        "logDir", A_ScriptDir "\logs",
        "showUI", true,
        "llmEnabled", false
    )

    static Initialize() {
        if (!DirExist(this.config["logDir"]))
            DirCreate(this.config["logDir"])

        OnError(this.HandleError.Bind(this), 1)
    }

    static HandleError(exception, mode) {
        ; Build report
        report := "=" . exception.Message
                . "`nFile: " . exception.File
                . "`nLine: " . exception.Line

        ; Log to file
        FileAppend(report . "`n`n",
            this.config["logDir"] . "\errors.log")

        ; Show UI
        if (this.config["showUI"])
            MsgBox(report, "Error")

        return -1
    }
}

DebugHandler.Initialize()

; Your script
x := 1 / 0
```

This is the foundation of production-grade debugging in AHK v2!
