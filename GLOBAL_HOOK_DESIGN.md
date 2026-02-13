# Global AHK v2 Debugging Hook - Design Document

## Problem Statement

**Requirement**: Capture errors from ANY AHK v2 script WITHOUT modifying the target script (no `#Include` statements).

**Current Limitation**: The existing `ErrorInterceptor.ahk` system requires including the interceptor in every script you want to monitor. This is:
- Invasive (modifies target scripts)
- Inconvenient (must be added to every test script)
- Not scalable (can't monitor third-party scripts)

## Solution Overview

Create a **global debugging hook** that attaches to running AHK v2 processes and intercepts errors via:
1. **TCP/Socket-based IPC** for real-time error reporting
2. **Shared memory** for high-performance data transfer
3. **File-based fallback** for compatibility

---

## Architecture: Three Approaches

### Approach 1: DLL Injection (Advanced)
**How it works**:
- Global monitor injects a DLL into target AHK process
- DLL hooks into AHK v2 runtime's `OnError()` at native level
- Errors broadcast via named pipe or TCP socket

**Pros**:
- Zero script modification needed
- Real-time capture
- Works on any AHK v2 script

**Cons**:
- Requires C++ DLL development
- Complex implementation
- May trigger antivirus
- Requires admin privileges

**Feasibility**: HIGH complexity, LOW maintainability

---

### Approach 2: AutoHotkey_H Thread Injection (Medium)
**How it works**:
- Use AutoHotkey_H's threading capabilities
- Inject error handler into target process via `ahkExec()`
- Target script runs in separate thread with global error handler

**Pros**:
- Pure AHK solution (no C++)
- Can inject code dynamically
- Works across multiple scripts

**Cons**:
- Requires AutoHotkey_H (not standard AHKv2)
- Still requires some target script cooperation
- Threading complexities

**Feasibility**: MEDIUM complexity, MEDIUM maintainability

---

### Approach 3: TCP Server + Lightweight Client (Recommended)
**How it works**:
1. **Global Monitor** (`GlobalDebugServer.ahk`):
   - Runs as background service
   - Listens on TCP port (e.g., 9999)
   - Receives error reports from clients
   - Displays/logs errors centrally

2. **Lightweight Client** (`DebugClient.ahk`):
   - Single line: `#Include DebugClient.ahk`
   - Auto-connects to TCP server on startup
   - Captures errors via `OnError()`
   - Sends to server asynchronously

3. **Auto-Injection Wrapper** (`AutoDebug.ahk`):
   - Launches target script with client pre-included
   - Example: `AutoDebug.ahk YourScript.ahk`
   - Transparent to user

**Pros**:
- Pure AHK v2 solution
- Network-based (can monitor remote scripts)
- Minimal client footprint (~50 lines)
- Easy to maintain
- Works across machines

**Cons**:
- Still requires minimal modification (1 line) OR wrapper launcher
- Network dependency (but can use localhost)
- Slight latency (negligible for error handling)

**Feasibility**: LOW complexity, HIGH maintainability

---

## Recommended Implementation: TCP Server Approach

### Component 1: GlobalDebugServer.ahk

**Responsibilities**:
- Start TCP server on port 9999
- Accept connections from multiple clients
- Receive error packets (JSON format)
- Display errors in dark-mode GUI
- Log to centralized file
- Send tray notifications
- Track error statistics

**Key Features**:
```autohotkey
class DebugServer {
    static port := 9999
    static clients := Map()
    static errorQueue := []

    static Start() {
        ; Create TCP server socket
        ; Listen for connections
        ; Handle incoming error packets
        ; Display in unified GUI
    }

    static ReceiveError(errorPacket) {
        ; Parse JSON
        ; Extract: script name, error type, message, stack, timestamp
        ; Display in GUI + log to file
        ; Send notification
    }
}
```

**Protocol (JSON over TCP)**:
```json
{
    "type": "error",
    "script": "MyScript.ahk",
    "pid": 12345,
    "timestamp": "2025-10-22T14:30:45",
    "error": {
        "type": "ValueError",
        "message": "Division by zero",
        "file": "C:\\Scripts\\MyScript.ahk",
        "line": 42,
        "what": "Divide",
        "stack": "...",
        "extra": "..."
    }
}
```

---

### Component 2: DebugClient.ahk (Lightweight)

**Responsibilities**:
- Connect to server on startup
- Register `OnError()` handler
- Capture all errors
- Serialize to JSON
- Send to server asynchronously
- Fallback to file if server unavailable

**Code (Minimal Footprint)**:
```autohotkey
#Requires AutoHotkey v2.0

class DebugClient {
    static serverHost := "127.0.0.1"
    static serverPort := 9999
    static socket := ""

    static Initialize() {
        ; Connect to server
        this.Connect()

        ; Register error handler
        OnError(this.CaptureError.Bind(this), 1)
    }

    static Connect() {
        try {
            ; Create TCP socket and connect
            this.socket := this.CreateSocket()
        } catch {
            ; Server not available - fallback to file logging
            this.socket := ""
        }
    }

    static CaptureError(exception, mode) {
        errorPacket := this.BuildPacket(exception)

        if (this.socket) {
            ; Send to server
            this.SendToServer(errorPacket)
        } else {
            ; Fallback to file
            this.LogToFile(errorPacket)
        }

        return -1  ; Suppress default dialog
    }

    static BuildPacket(exception) {
        return JSON.Stringify(Map(
            "type", "error",
            "script", A_ScriptName,
            "pid", DllCall("GetCurrentProcessId"),
            "timestamp", FormatTime(, "yyyy-MM-ddTHH:mm:ss"),
            "error", Map(
                "type", Type(exception),
                "message", exception.Message,
                "file", exception.File,
                "line", exception.Line,
                "what", exception.What,
                "stack", exception.HasProp("Stack") ? exception.Stack : "",
                "extra", exception.HasProp("Extra") ? exception.Extra : ""
            )
        ))
    }
}

; Auto-initialize
DebugClient.Initialize()
```

**Usage in target script**:
```autohotkey
#Requires AutoHotkey v2.0
#Include DebugClient.ahk  ; <-- ONE LINE

; Your script here
x := 1 / 0  ; Error automatically sent to server
```

---

### Component 3: AutoDebug.ahk (Wrapper Launcher)

**Purpose**: Launch scripts with debug client pre-injected (no script modification)

**How it works**:
1. User runs: `AutoDebug.ahk TargetScript.ahk`
2. Creates temporary script: `_debug_TargetScript.ahk`
3. Prepends: `#Include DebugClient.ahk`
4. Appends: `#Include TargetScript.ahk`
5. Executes temporary script
6. Cleans up on exit

**Code**:
```autohotkey
#Requires AutoHotkey v2.0

; Usage: AutoDebug.ahk TargetScript.ahk

if (A_Args.Length < 1) {
    MsgBox("Usage: AutoDebug.ahk <ScriptPath>")
    ExitApp()
}

targetScript := A_Args[1]

if (!FileExist(targetScript)) {
    MsgBox("Script not found: " targetScript)
    ExitApp()
}

; Create temporary wrapper script
tempScript := A_Temp "\_debug_" A_ScriptName
wrapper := "#Requires AutoHotkey v2.0`n"
wrapper .= "#Include " A_ScriptDir "\DebugClient.ahk`n"
wrapper .= "#Include " targetScript "`n"

FileDelete(tempScript)
FileAppend(wrapper, tempScript)

; Execute wrapper
Run("AutoHotkey64.exe " tempScript)

; Note: Temp file cleanup can be done by DebugClient on exit
```

**Usage**:
```bash
# No script modification needed!
AutoDebug.ahk MyScript.ahk
```

---

## Advanced: Named Pipe Alternative

For even lower latency, use Windows Named Pipes instead of TCP:

**Server side**:
```autohotkey
; Create named pipe: \\.\pipe\AHKDebug
pipe := DllCall("CreateNamedPipe", "Str", "\\.\pipe\AHKDebug", ...)
```

**Client side**:
```autohotkey
; Connect to named pipe
hPipe := DllCall("CreateFile", "Str", "\\.\pipe\AHKDebug", ...)
```

**Benefits**:
- Faster than TCP (no network stack)
- More secure (local only)
- Lower overhead

**Drawback**:
- Can't monitor remote machines
- More complex API

---

## Alternative: File-Watch Hybrid (No Code in Target)

If you want ZERO modification to target scripts:

### Approach: Shared Memory + File Monitor

1. **Global Monitor** watches a shared directory
2. Target scripts run normally (no modification)
3. **AHK v2 runtime** has built-in error logging to `stderr`
4. Wrapper redirects `stderr` to file in shared directory
5. Monitor detects new error files and displays them

**Launcher**:
```autohotkey
; RunWithMonitor.ahk
#Requires AutoHotkey v2.0

targetScript := A_Args[1]
errorFile := A_Temp "\ahk_errors_" A_ScriptName ".txt"

; Run script with stderr redirected
Run("AutoHotkey64.exe /ErrorStdOut " targetScript " 2> " errorFile)

; File will be monitored by GlobalDebugServer.ahk
```

**Server watches**: `A_Temp "\ahk_errors_*.txt"`

**Pros**:
- ZERO modification to target scripts
- Simple implementation
- Works with any AHK v2 script

**Cons**:
- Requires wrapper launcher
- File I/O overhead
- Slight delay in detection

---

## Comparison Matrix

| Feature | DLL Injection | AutoHotkey_H | TCP Server | Named Pipe | File Watch |
|---------|---------------|--------------|------------|------------|------------|
| **Zero script modification** | ✅ Yes | ⚠️ Partial | ❌ 1 line | ❌ 1 line | ✅ Yes* |
| **Real-time capture** | ✅ Instant | ✅ Instant | ✅ <10ms | ✅ <5ms | ⚠️ 100ms+ |
| **Pure AHK v2** | ❌ C++ DLL | ⚠️ AHK_H | ✅ Yes | ✅ Yes | ✅ Yes |
| **Remote monitoring** | ❌ No | ❌ No | ✅ Yes | ❌ No | ⚠️ Via share |
| **Complexity** | 🔴 High | 🟡 Medium | 🟢 Low | 🟡 Medium | 🟢 Low |
| **Maintenance** | 🔴 Hard | 🟡 Medium | 🟢 Easy | 🟢 Easy | 🟢 Easy |
| **Antivirus issues** | ⚠️ Likely | ⚠️ Maybe | ✅ Safe | ✅ Safe | ✅ Safe |
| **Admin required** | ✅ Yes | ⚠️ Maybe | ❌ No | ❌ No | ❌ No |

*Requires wrapper launcher

---

## Recommended Implementation Plan

### Phase 1: TCP Server (Weeks 1-2)
1. Implement `GlobalDebugServer.ahk` with TCP listener
2. Build `DebugClient.ahk` (lightweight, <100 lines)
3. Create JSON protocol
4. Test with multiple concurrent clients

### Phase 2: Auto-Injection Wrapper (Week 3)
1. Implement `AutoDebug.ahk` launcher
2. Test transparent script wrapping
3. Handle edge cases (includes, working directory)

### Phase 3: File-Watch Fallback (Week 4)
1. Add file-based monitoring to server
2. Implement `stderr` redirection in launcher
3. Create unified monitoring (TCP + files)

### Phase 4: Advanced Features (Week 5+)
- Named pipe support for local scripts
- Variable monitoring integration (Dim Echo Box over TCP)
- LLM analysis integration
- Statistics dashboard
- Remote debugging UI

---

## File Structure

```
DebuggerInterceptor/
├── GlobalDebugServer.ahk       (Main server - 500 lines)
├── DebugClient.ahk              (Lightweight client - 100 lines)
├── AutoDebug.ahk                (Wrapper launcher - 50 lines)
├── JSON.ahk                     (JSON library)
├── Socket.ahk                   (TCP socket wrapper)
├── GLOBAL_HOOK_DESIGN.md        (This file)
└── Examples/
    ├── BasicUsage.ahk           (Shows #Include method)
    └── WrapperUsage.bat         (Shows AutoDebug launcher)
```

---

## Usage Examples

### Example 1: Manual Include (Minimal)
```autohotkey
#Requires AutoHotkey v2.0
#Include DebugClient.ahk

x := 1 / 0  ; Error sent to server
```

### Example 2: Wrapper Launcher (Zero modification)
```bash
# Terminal
AutoDebug.ahk MyScript.ahk

# Errors from MyScript.ahk appear in GlobalDebugServer
```

### Example 3: Remote Monitoring
```autohotkey
; On Machine A (developer workstation)
GlobalDebugServer.ahk

; On Machine B (test machine)
; DebugClient.ahk configured with:
static serverHost := "192.168.1.100"  ; Machine A's IP
```

---

## Security Considerations

1. **Local-only by default**: Server binds to `127.0.0.1` (localhost)
2. **Authentication optional**: Add API key header if exposing to network
3. **Encryption**: Use TLS for sensitive environments
4. **Firewall**: Windows Firewall may prompt for network access

---

## Performance Profile

| Metric | TCP Server | Named Pipe | File Watch |
|--------|------------|------------|------------|
| **Error capture** | <1ms | <0.5ms | ~10ms |
| **Network latency** | 5-10ms | N/A | N/A |
| **File I/O** | None | None | 50-100ms |
| **CPU overhead** | <0.1% | <0.1% | <0.5% |
| **Memory** | ~5MB | ~3MB | ~2MB |

---

## Conclusion

**Best Solution**: **TCP Server + AutoDebug Wrapper**

This provides:
- ✅ Near-zero modification (1 line include OR wrapper launcher)
- ✅ Pure AHK v2 (no C++, no AutoHotkey_H)
- ✅ Real-time capture (<10ms latency)
- ✅ Remote monitoring capability
- ✅ Low complexity, high maintainability
- ✅ Fallback to file-based monitoring

**Next Steps**: Implement Phase 1 (TCP Server + Client)
