# DebuggerInterceptor Quick Start Guide

Get up and running in 30 seconds.

## The Fastest Setup

Copy this into your AHK v2 script:

```autohotkey
#Requires AutoHotkey v2.1-alpha.17
#Include DebuggerInterceptor/Initialize.ahk

InitializeDebuggerInterceptor()

; Your code here
MsgBox("Hello World")
```

**That's it.** All errors are now logged and monitored.

## Opening the Log Viewer

Press **Ctrl+Alt+L** to open the log viewer GUI at any time.

## Three Ways to Use It

### 1. Automatic (Recommended)
Errors are intercepted automatically:
```autohotkey
try {
    x := 10 / 0  ; Error caught automatically
} catch as err {
    ; Error is logged to file AND clipboard
}
```

### 2. Manual Logging
Log messages yourself:
```autohotkey
DebugLog("Starting operation")
DebugWarning("This might be an issue")
DebugError("Something failed")
```

### 3. Mixed Approach
Combine both:
```autohotkey
try {
    DebugLog("Attempting database connection")
    Connect()
    DebugLog("Connection successful")
} catch as err {
    DebugError("Connection failed", err)
}
```

## Configuration Presets

### Development (Verbose)
```autohotkey
ErrorLogger.Config["logLevel"] := "DEBUG"
ErrorLogger.Config["suppressErrorDialog"] := false
InitializeDebuggerInterceptor(true)  ; Show test GUI
```

### Production (Quiet)
```autohotkey
ErrorLogger.Config["logLevel"] := "ERROR"
ErrorLogger.Config["suppressErrorDialog"] := true
InitializeDebuggerInterceptor(false)  ; No test GUI
```

### Testing (Balanced)
```autohotkey
ErrorLogger.Config["logLevel"] := "WARN"
InitializeDebuggerInterceptor(true)
```

See `ConfigExample.ahk` for more presets.

## What Gets Logged

### Automatically
- All unhandled exceptions
- Error type and message
- File path and line number
- Full stack traces
- Surrounding code context
- System information

### When You Call Functions
```autohotkey
DebugLog("message")      ; INFO level
DebugWarning("message")  ; WARN level
DebugError("message")    ; ERROR level
```

## The Test GUI

When you call `InitializeDebuggerInterceptor(true)`, a test window appears with buttons to:

- Generate test errors (division by zero, array bounds, etc.)
- Open the current log file
- Toggle log ordering
- Toggle clipboard copy
- Toggle clipboard format
- View logs

Close it with Escape or the X button. It doesn't prevent your script from running.

## Log Files

Logs are saved to: `ErrorLogs/ErrorLog_YYYY_MM_DD.log`

Format:
```
[2025-10-22 14:30:45] [ERROR] ===== ERROR [2025-10-22 14:30:45] =====
Type: ZeroDivisionError
Message: Division by zero
File: C:\script.ahk
Line: 42
Code: result := 10 / 0
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **Ctrl+Alt+L** | Show/Hide log viewer |
| **Double-Click** | View full error details |
| **Right-Click** | Context menu (copy, filter, search) |
| **Escape** (in viewer) | Close log viewer |

## Common Tasks

### Suppress System Error Dialogs
```autohotkey
ErrorLogger.Config["suppressErrorDialog"] := true
InitializeDebuggerInterceptor()
```

### Disable Clipboard Auto-Copy
```autohotkey
ErrorLogger.Config["copyToClipboard"] := false
InitializeDebuggerInterceptor()
```

### Change Log Directory
```autohotkey
ErrorLogger.Config["logDirectory"] := "C:\MyLogs"
InitializeDebuggerInterceptor()
```

### Show Only Errors
```autohotkey
ErrorLogger.Config["logLevel"] := "ERROR"
InitializeDebuggerInterceptor()
```

### Get Detailed Clipboard Format
```autohotkey
ErrorLogger.Config["clipboardFormat"] := "detailed"
InitializeDebuggerInterceptor()
```

## Viewing Logs Without GUI

Logs are plain text files in `ErrorLogs/`:
- Open with Notepad
- Search with grep/ripgrep
- Analyze with your favorite tool
- Import into spreadsheet

## When Errors Happen

1. Error occurs in your script
2. ErrorLogger.OnError() handler fires
3. Error details logged to file
4. Details copied to clipboard (if enabled)
5. Log viewer updates automatically
6. You can press Ctrl+Alt+L anytime to see it

## Tips

- **Keep test GUI open while developing** - spot errors immediately
- **Use DebugLog() for progress tracking** - helps debug logic issues
- **Check clipboard when something fails** - error is already copied
- **Open log viewer when stuck** - see the last 100 errors
- **Export logs for others** - they can open with text editor

## Troubleshooting

### Ctrl+Alt+L doesn't work
- Make sure script is still running
- Try clicking the window first to give it focus
- Check if another script is using that hotkey

### No errors being logged
- Make sure error actually occurs (not caught in try/catch)
- Check that `ErrorLogs` directory exists or can be created
- Verify write permissions to script directory
- Increase log level: `Config["logLevel"] := "DEBUG"`

### Log viewer won't open
- Manually open file: `ErrorLogs/ErrorLog_YYYY_MM_DD.log`
- Use the "Browse" button in the test GUI
- Check that log file exists

### Performance is slow
- Disable stack traces: `Config["includeStackTrace"] := false`
- Reduce refresh rate: `LogViewer.Config["refreshInterval"] := 5000`
- Increase log level: `Config["logLevel"] := "ERROR"`

## Next Steps

1. ✅ **Add to your script** - `#Include DebuggerInterceptor/Initialize.ahk`
2. ✅ **Initialize** - `InitializeDebuggerInterceptor()`
3. ✅ **Press Ctrl+Alt+L** - See it in action
4. ✅ **Configure** - Tweak settings for your needs
5. ✅ **Use DebugLog()** - Add logging to your code

## Examples

See the `Example.ahk` script for a complete working example with multiple scenarios.

## Need More?

- **Configuration**: See `ConfigExample.ahk`
- **API Details**: See `README.md`
- **Full Documentation**: See `README.md`

## That's All!

You're ready to go. Happy debugging! 🐛
