# DebuggerInterceptor System

A comprehensive error logging and interception system for AutoHotkey v2 scripts. Automatically captures all unhandled exceptions with full context and provides a GUI viewer for monitoring and analyzing errors in real-time.

## Features

### ErrorLogger Class
- **Automatic Error Interception**: Hooks into `OnError()` to catch all unhandled exceptions
- **Comprehensive Context**: Records error type, message, file path, line number, and stack traces
- **Code Context Display**: Shows the actual problematic code with surrounding lines
- **Log File Management**: Organizes logs by date with automatic archival when size limits reached
- **Clipboard Integration**: Automatically copies error details to clipboard in simple or detailed format
- **Configurable Levels**: DEBUG, INFO, WARN, ERROR, FATAL with level-based filtering
- **System Information**: Includes AHK version, script path, and working directory in error logs

### LogViewer GUI
- **Real-time Monitoring**: Auto-refreshes log display every 2 seconds (configurable)
- **Advanced Filtering**: Filter by log level or search across all fields
- **Dark Mode UI**: Professional dark theme with color-coded severity levels
- **Error Details**: Double-click to view full error context in dedicated window
- **Context Menu**: Copy, filter, search similar errors
- **Log Management**: Browse log files, clear logs, view error archives
- **Hotkey**: Ctrl+Alt+L to toggle log viewer

## Structure

```
DebuggerInterceptor/
├── ErrorLogger.ahk       # Core error interception class
├── LogViewer.ahk         # GUI interface for log viewing
├── Initialize.ahk        # Quick setup and helper functions
└── README.md             # This file
```

## Quick Start

### Basic Integration

```autohotkey
#Requires AutoHotkey v2.1-alpha.17

; Include the initialization script
#Include DebuggerInterceptor/Initialize.ahk

; Initialize the interceptor (creates test GUI)
InitializeDebuggerInterceptor()

; Your script code here
; All errors will be automatically logged and displayed
```

### Minimal Integration (No Test GUI)

```autohotkey
#Requires AutoHotkey v2.1-alpha.17

#Include DebuggerInterceptor/Initialize.ahk

; Initialize without showing test GUI
InitializeDebuggerInterceptor(false)

; Open log viewer with Ctrl+Alt+L
```

## Usage Examples

### Logging Messages

```autohotkey
; Log information
DebugLog("Starting application initialization")

; Log warnings
DebugWarning("Configuration file not found, using defaults")

; Log errors (with or without exception object)
DebugError("Failed to connect to server")

; Or use the class directly
ErrorLogger.Info("Server connected successfully")
ErrorLogger.Error("Connection lost", exception)
```

### Handling Exceptions

```autohotkey
try {
    result := 10 / 0  ; This will trigger error interception
} catch as err {
    DebugError("Division operation failed", err)
}
```

### Customizing Configuration

```autohotkey
#Include DebuggerInterceptor/Initialize.ahk

; Customize settings before initialization
ErrorLogger.Config["logLevel"] := "DEBUG"  ; Show all messages
ErrorLogger.Config["copyToClipboard"] := false  ; Disable auto-copy
ErrorLogger.Config["suppressErrorDialog"] := true  ; Hide system error dialogs
ErrorLogger.Config["newestLogsAtTop"] := true  ; Newest entries first

InitializeDebuggerInterceptor()
```

## Configuration Options

### ErrorLogger Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `logDirectory` | String | `ErrorLogs` | Directory for log files |
| `logFilePrefix` | String | `ErrorLog_` | Prefix for log filenames |
| `logFileExtension` | String | `.log` | Extension for log files |
| `maxLogSize` | Integer | 5MB | Max size before auto-archive |
| `logLevel` | String | `INFO` | Minimum log level to record |
| `includeStackTrace` | Boolean | true | Include full stack traces |
| `includeSystemInfo` | Boolean | true | Include system info in errors |
| `suppressErrorDialog` | Boolean | true | Hide system error dialogs |
| `newestLogsAtTop` | Boolean | true | Log order (newest first) |
| `copyToClipboard` | Boolean | true | Auto-copy errors to clipboard |
| `clipboardFormat` | String | `simple` | Format: "simple" or "detailed" |
| `logToConsole` | Boolean | false | Also output to debugger console |

### LogViewer Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `defaultLogFile` | String | `ahk_error_log.txt` | Default log file path |
| `refreshInterval` | Integer | 2000 | Refresh rate in milliseconds |
| `maxEntries` | Integer | 5000 | Maximum log entries to display |
| `defaultWidth` | Integer | 900 | Initial window width |
| `defaultHeight` | Integer | 600 | Initial window height |
| `errorLogsDir` | String | `ErrorLogs` | Directory for error logs |

## Log File Format

Logs are stored in human-readable text format:

```
[YYYY-MM-DD HH:MM:SS] [ERROR] ===== ERROR [YYYY-MM-DD HH:MM:SS] =====
Type: ErrorType
Message: Error description
File: C:\path\to\script.ahk
Line: 42
Code: actual code line that caused error

Context:
   40: previous line
   41: context line
→  42: error line
   43: following line
   44: another line

Stack Trace:
[stack trace details...]

This is error #1 since script start.

===== System Information =====
AHK Version: 2.1-alpha.17
Script: script.ahk
Script Path: C:\path\to\script.ahk
Working Dir: C:\path\to\
```

## Log Viewer Controls

### Toolbar Buttons
- **Browse**: Select a different log file to view
- **Error Logs**: Quick menu to switch between archived error logs
- **Search**: Find entries by text
- **Refresh**: Manually refresh log display
- **Clear Log**: Clear the current log file
- **Auto Refresh**: Toggle automatic refresh on/off

### Filtering
- **Filter Level**: Show only errors of specific severity
- **Search Box**: Find entries containing specific text

### Right-Click Context Menu
- **Show Details**: View full error text in separate window
- **Copy to Clipboard**: Copy error details
- **Filter by Level**: Show only this error severity
- **Search for Similar Errors**: Find errors of same type

### Hotkeys
- **Ctrl+Alt+L**: Show/hide log viewer
- **Double-Click**: Show full error details
- **Escape**: Close log viewer

## Log Levels

From lowest to highest severity:

1. **DEBUG**: Detailed debugging information
2. **INFO**: General informational messages
3. **WARN**: Warning messages for potential issues
4. **ERROR**: Error conditions
5. **FATAL**: Critical errors

When `logLevel` is set to a level, all messages at that level and higher are recorded.

## Error Archival

When a log file exceeds `maxLogSize` (default 5MB):

1. Current log is copied to archive with timestamp suffix
2. Format: `ErrorLog_YYYYMMDD_HHMMSS_archive.log`
3. Original log file is cleared and reused
4. Archives are preserved in the same `ErrorLogs` directory

## Best Practices

### 1. Initialize Early
Place initialization at the top of your script, before other code:

```autohotkey
#Requires AutoHotkey v2.1-alpha.17
#Include DebuggerInterceptor/Initialize.ahk

InitializeDebuggerInterceptor(false)  ; Don't show test GUI in production

; Rest of your script
```

### 2. Use Appropriate Log Levels
```autohotkey
DebugLog("User clicked button")          ; DEBUG
DebugWarning("Config file missing")      ; WARN
DebugError("File operation failed", err) ; ERROR
```

### 3. Clean Up Old Logs
Periodically archive or delete old logs to save disk space:

```autohotkey
; View ErrorLogs folder and manually clean old archives
; Or implement automatic cleanup
Loop Files, A_ScriptDir "\ErrorLogs\*.log" {
    if (A_Now - FileGetTime(A_LoopFileFullPath) > 30 * 24 * 60 * 60)  ; 30 days
        FileDelete(A_LoopFileFullPath)
}
```

### 4. Disable in Production (Optional)
```autohotkey
#If !IsProduction()
    InitializeDebuggerInterceptor()
#If

IsProduction() {
    return FileExist("PRODUCTION.flag")
}
```

### 5. Customize for Your Needs
```autohotkey
ConfigureInterceptor(Map(
    "logLevel", "WARN",                ; Only log warnings and errors
    "suppressErrorDialog", true,        ; Hide system dialogs
    "copyToClipboard", false           ; Don't auto-copy
))
```

## Troubleshooting

### Logs not appearing
1. Check that `ErrorLogs` directory exists or is creatable
2. Verify write permissions to script directory
3. Ensure `ErrorLogger.Config["logToFile"]` is true
4. Check that error actually occurred (not caught in try/catch)

### LogViewer not showing
1. Press Ctrl+Alt+L to toggle
2. Verify log file path is correct
3. Check that log file exists in ErrorLogs folder
4. Try using "Browse" button to select log file manually

### Performance issues
1. Reduce `LogViewer.Config["refreshInterval"]` (currently 2000ms)
2. Use `DebugLog("Reduce frequency")` instead of high-volume logging
3. Clear old logs to reduce file size
4. Set `logLevel` higher to reduce entries

### Memory issues with large logs
1. Limit `maxLogSize` configuration
2. Enable auto-archival at smaller size
3. Use file rotation strategy
4. Clear logs regularly

## Advanced Usage

### Custom Error Handler
```autohotkey
; Add your own error handler alongside the interceptor
OnError((exception, mode) => {
    if (mode = 1)  ; 1 = unhandled error
        DebugError("Critical error occurred", exception)
    return 0  ; Continue normal error handling
})
```

### Log Multiple Threads
```autohotkey
; If your script uses threads, include thread ID
DebugLog("Thread operation started")
DebugLog("[Thread " A_TickCount "] Operation complete")
```

### Export Logs
```autohotkey
; Copy logs for external analysis
logFile := ErrorLogger.Instance.logFilePath
exportPath := A_ScriptDir "\exported_logs.txt"
FileCopy(logFile, exportPath)
```

## Performance Impact

- **Memory**: ~2-5MB for typical usage
- **CPU**: <1% overhead
- **Disk I/O**: Only on error occurrence
- **GUI**: Refresh every 2 seconds (configurable)

The system is designed to have minimal performance impact on running scripts.

## Version Requirements

- **AutoHotkey**: v2.1-alpha.17 or later
- **Dependencies**: None (uses only built-in AHK functions)

## Files

- `ErrorLogger.ahk` - Core error interception class (~380 lines)
- `LogViewer.ahk` - GUI viewer interface (~550 lines)
- `Initialize.ahk` - Setup and helper functions (~60 lines)
- `README.md` - This documentation

Total: ~1000 lines of code

## License

Part of the AutoHotkey v2 development environment.

## Notes

- Errors are logged **after** they occur (for awareness)
- Unhandled errors still exit the script (return 1 suppresses exit)
- All timestamps use system time
- Log files are UTF-8 encoded
- Paths use forward slashes internally but accept backslashes
