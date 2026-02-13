# DebuggerInterceptor - Complete File Index

A comprehensive AutoHotkey v2 error logging and monitoring system. All error handling code organized in one place.

## Files in This Folder

### Core Implementation
- **ErrorLogger.ahk** (380 lines)
  - Main error interception class
  - Hooks into `OnError()` to catch all exceptions
  - Logs to file with full context (stack traces, code, system info)
  - Manages log rotation and archival
  - Auto-copies errors to clipboard
  - Supports 5 log levels: DEBUG, INFO, WARN, ERROR, FATAL

- **LogViewer.ahk** (550 lines)
  - GUI interface for browsing error logs
  - Real-time log display with auto-refresh
  - Filter by severity level
  - Full-text search across logs
  - Color-coded by severity (red for errors, orange for warnings)
  - Dark mode interface
  - Context menu for detailed viewing and analysis

- **Initialize.ahk** (60 lines)
  - Quick setup and initialization
  - Helper functions: `DebugLog()`, `DebugError()`, `DebugWarning()`
  - Configuration utility: `ConfigureInterceptor()`
  - Hotkey registration (Ctrl+Alt+L for log viewer)
  - Global instance management

### Documentation
- **README.md** (600+ lines)
  - Complete system documentation
  - Feature overview
  - Configuration reference (20+ options)
  - Log file format explanation
  - Best practices and examples
  - Troubleshooting guide
  - Advanced usage patterns

- **QUICKSTART.md** (250+ lines)
  - Fast setup guide (30 seconds)
  - Three usage methods
  - Configuration presets
  - Common tasks
  - Keyboard shortcuts
  - Basic troubleshooting

- **INDEX.md** (this file)
  - File inventory
  - What each file does
  - How to use the system

### Examples & Configuration
- **Example.ahk** (350+ lines)
  - Complete working example
  - Test GUI with 6 test scenarios
  - Demonstrates logging functions
  - Shows error handling patterns
  - Real-world use cases
  - Explanatory comments

- **ConfigExample.ahk** (200+ lines)
  - 8 pre-configured setups
  - Development mode (verbose)
  - Production mode (quiet)
  - Testing mode (balanced)
  - Minimal mode (performance)
  - Custom directory setup
  - Custom clipboard options
  - Full custom configuration

## Quick Start

### 1. Minimal Setup (2 lines)
```autohotkey
#Include DebuggerInterceptor/Initialize.ahk
InitializeDebuggerInterceptor()
```

### 2. Run the Example
```bash
AutoHotkey64.exe DebuggerInterceptor/Example.ahk
```

### 3. Open Documentation
- Quick info: Read **QUICKSTART.md**
- Full info: Read **README.md**
- Examples: Check **Example.ahk** or **ConfigExample.ahk**

## File Organization

```
DebuggerInterceptor/
├── ErrorLogger.ahk          # Core error handling class
├── LogViewer.ahk            # GUI viewer interface
├── Initialize.ahk           # Setup and helpers
├── Example.ahk              # Working example (run this to demo)
├── ConfigExample.ahk        # Configuration examples
├── README.md                # Complete documentation
├── QUICKSTART.md            # Fast setup guide
└── INDEX.md                 # This file (what you're reading)
```

## How It Works

1. **Include the system**: `#Include DebuggerInterceptor/Initialize.ahk`
2. **Initialize**: `InitializeDebuggerInterceptor()`
3. **All errors are now logged** automatically
4. **View logs**: Press Ctrl+Alt+L anytime
5. **Manual logging**: Use `DebugLog()`, `DebugError()`, `DebugWarning()`

## What Gets Logged

### Automatic (No code needed)
- ✅ All unhandled exceptions
- ✅ Error type and message
- ✅ File path and line number
- ✅ Full stack trace
- ✅ Code context (surrounding lines)
- ✅ System information
- ✅ Timestamp

### Manual (Your code)
```autohotkey
DebugLog("Information message")          ; INFO level
DebugWarning("Warning message")          ; WARN level
DebugError("Error message", exception)   ; ERROR level
```

## Key Features

| Feature | Details |
|---------|---------|
| **Automatic Error Interception** | Catches all unhandled exceptions |
| **File Logging** | Daily log files in ErrorLogs/ folder |
| **Real-time GUI** | View logs as they happen (Ctrl+Alt+L) |
| **Filtering** | Filter by level or search text |
| **Clipboard** | Auto-copy errors to clipboard |
| **Log Rotation** | Auto-archives logs when too large |
| **Code Context** | Shows the actual problematic line |
| **Stack Traces** | Full function call chain |
| **Dark Mode** | Professional dark theme GUI |
| **Zero Config** | Works out of the box |

## Configuration Options

The system has 30+ configuration options. Examples:

```autohotkey
ErrorLogger.Config["logLevel"] := "DEBUG"           ; Show all messages
ErrorLogger.Config["maxLogSize"] := 10 * 1024 * 1024  ; 10MB before rotate
ErrorLogger.Config["suppressErrorDialog"] := true   ; Hide error dialogs
ErrorLogger.Config["copyToClipboard"] := true      ; Auto-copy errors
ErrorLogger.Config["includeStackTrace"] := true    ; Include stack info
LogViewer.Config["refreshInterval"] := 1000        ; Update every 1 second
```

See **README.md** for complete list.

## Common Tasks

### Log a message
```autohotkey
DebugLog("Operation started")
```

### Log an error
```autohotkey
try {
    ; code
} catch as err {
    DebugError("Operation failed", err)
}
```

### View logs
Press **Ctrl+Alt+L** anytime

### Change log level
```autohotkey
ErrorLogger.Config["logLevel"] := "ERROR"  ; Only errors
```

### View in test GUI
```autohotkey
InitializeDebuggerInterceptor(true)  ; Show test window
```

### Access logs directly
Logs are plain text in: `ErrorLogs/ErrorLog_YYYY_MM_DD.log`

## System Requirements

- **AutoHotkey**: v2.1-alpha.17 or later
- **OS**: Windows
- **Dependencies**: None (all native AHK functions)

## File Sizes

| File | Lines | Size |
|------|-------|------|
| ErrorLogger.ahk | 380 | ~12 KB |
| LogViewer.ahk | 550 | ~19 KB |
| Initialize.ahk | 60 | ~2 KB |
| Example.ahk | 350 | ~11 KB |
| ConfigExample.ahk | 200 | ~7 KB |
| README.md | 600+ | ~25 KB |
| QUICKSTART.md | 250+ | ~10 KB |
| **Total** | **~2390** | **~86 KB** |

## Hotkeys

| Hotkey | Action |
|--------|--------|
| Ctrl+Alt+L | Toggle log viewer |
| Double-click | View error details |
| Right-click | Context menu |
| Escape | Close log viewer |

## Next Steps

1. **Learn quickly**: Read **QUICKSTART.md** (5 minutes)
2. **Try it**: Run **Example.ahk** (test the demo)
3. **Use it**: Add to your script (2 lines of code)
4. **Configure**: Read **ConfigExample.ahk** (if needed)
5. **Master it**: Read **README.md** (for advanced features)

## Examples

### Quickest Setup
```autohotkey
#Requires AutoHotkey v2.1-alpha.17
#Include DebuggerInterceptor/Initialize.ahk
InitializeDebuggerInterceptor()
; Your script here
```

### Development Setup
```autohotkey
#Include DebuggerInterceptor/Initialize.ahk
ErrorLogger.Config["logLevel"] := "DEBUG"
InitializeDebuggerInterceptor(true)  ; Show test GUI
```

### Production Setup
```autohotkey
#Include DebuggerInterceptor/Initialize.ahk
ErrorLogger.Config["logLevel"] := "ERROR"
InitializeDebuggerInterceptor(false)  ; No test GUI
```

## Troubleshooting

### Script won't load
- Check `#Include` path is correct
- Verify file exists in DebuggerInterceptor folder
- Check AutoHotkey version (must be v2.1-alpha.17+)

### Hotkey doesn't work
- Make sure script is running
- Give window focus before pressing Ctrl+Alt+L
- Check for hotkey conflicts with other scripts

### Logs not appearing
- Check ErrorLogs folder exists
- Verify write permissions
- Check that error actually occurs
- Try opening test GUI to verify system works

### Log viewer won't open
- Check log file exists in ErrorLogs folder
- Use Browse button to select file manually
- Close and reopen viewer

## Support

For detailed information:
- **Quick questions**: See **QUICKSTART.md**
- **How-to**: See **README.md**
- **Examples**: See **Example.ahk** or **ConfigExample.ahk**

## Summary

This is a **complete, production-ready error logging system** for AutoHotkey v2:

✅ **All code organized** in one folder
✅ **Zero external dependencies**
✅ **Works out of the box**
✅ **Fully documented**
✅ **Multiple examples included**
✅ **Tested and reliable**
✅ **Professional GUI included**
✅ **Highly configurable**

Just include and use. Happy debugging! 🐛
