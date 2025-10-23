# Global Error Interception Setup Guide

This guide explains how to intercept errors from ANY AutoHotkey v2 script without manually including the error handler.

---

## 📋 **Available Approaches**

### **Approach 1: Wrapper Script (Recommended ⭐)**

Run scripts through a wrapper that automatically includes the error handler.

**Pros:**
- ✅ Zero modification to existing scripts
- ✅ Works immediately
- ✅ Easy to enable/disable per script
- ✅ Centralized configuration

**Cons:**
- ❌ Requires wrapper invocation
- ❌ Need to change how you launch scripts

---

### **Approach 2: File Association (Convenient 🎯)**

Modify Windows file association to always use the wrapper.

**Pros:**
- ✅ Double-click scripts work automatically
- ✅ No manual invocation needed
- ✅ Transparent to user

**Cons:**
- ❌ Affects ALL `.ahk` files globally
- ❌ Can break IDE debugging

---

### **Approach 3: Background Monitor (Passive 👀)**

Monitor error logs in real-time with notifications.

**Pros:**
- ✅ Non-intrusive
- ✅ Centralized error dashboard
- ✅ Works alongside any approach

**Cons:**
- ❌ Requires scripts to use error handler
- ❌ Reactive (not preventive)

---

### **Approach 4: DBGp Debugger Interception (Advanced 🚀)**

Intercept at the debugger protocol level.

**Pros:**
- ✅ Most powerful
- ✅ Works with ANY script (no modification)
- ✅ Stack traces, variable inspection
- ✅ Post-mortem analysis

**Cons:**
- ❌ Requires modified AutoHotkey build
- ❌ Complex setup (Node.js server)
- ❌ Performance overhead

---

## 🚀 **Quick Start: Wrapper Method**

### **Step 1: Files Created**

You now have these files:
- `ErrorInterceptor.ahk` - Core error handler
- `RunWithErrorHandler.ahk` - Wrapper script
- `RunAHKWithErrors.bat` - Convenience batch file
- `GlobalErrorMonitor.ahk` - Background monitor

### **Step 2: Basic Usage**

**Option A: Using the Batch File**
```batch
# Run any script with error handling
RunAHKWithErrors.bat MyScript.ahk

# With arguments
RunAHKWithErrors.bat MyScript.ahk arg1 arg2
```

**Option B: Direct Wrapper Usage**
```bash
# WSL
"/mnt/c/Program Files/AutoHotkey/v2/AutoHotkey64.exe" RunWithErrorHandler.ahk "MyScript.ahk"

# PowerShell
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" RunWithErrorHandler.ahk "MyScript.ahk"

# CMD
"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" RunWithErrorHandler.ahk "MyScript.ahk"
```

### **Step 3: Add to PATH (Optional)**

Add the directory to your PATH for convenience:

**Windows PowerShell (Admin):**
```powershell
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
$newPath = "C:\Users\uphol\Documents\Design\Coding\AHK\!Running\AutoHotkey"
[Environment]::SetEnvironmentVariable("Path", "$currentPath;$newPath", "User")
```

Then use from anywhere:
```batch
RunAHKWithErrors.bat C:\Any\Path\Script.ahk
```

---

## 🔧 **Setup: File Association Method**

Make double-clicking `.ahk` files use the error handler automatically.

### **Method 1: Registry Edit (Recommended)**

Create `SetupAHKWithErrors.reg`:

```registry
Windows Registry Editor Version 5.00

[HKEY_CLASSES_ROOT\AutoHotkeyScript\Shell\Open\Command]
@="\"C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe\" \"C:\\Users\\uphol\\Documents\\Design\\Coding\\AHK\\!Running\\AutoHotkey\\RunWithErrorHandler.ahk\" \"%1\" %*"
```

**To apply:**
1. Save the above as `SetupAHKWithErrors.reg`
2. Double-click to import
3. Confirm the registry change

**To revert:**
```registry
Windows Registry Editor Version 5.00

[HKEY_CLASSES_ROOT\AutoHotkeyScript\Shell\Open\Command]
@="\"C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe\" \"%1\" %*"
```

### **Method 2: Manual File Association**

1. Right-click any `.ahk` file
2. Select "Open with" → "Choose another app"
3. Click "More apps" → "Look for another app on this PC"
4. Navigate to `RunWithErrorHandler.ahk`
5. Check "Always use this app"
6. Click OK

**Note:** This changes the association for the current user only.

---

## 👀 **Setup: Background Monitor**

Run a persistent monitor that watches all error logs.

### **Step 1: Start the Monitor**

```bash
"/mnt/c/Program Files/AutoHotkey/v2/AutoHotkey64.exe" GlobalErrorMonitor.ahk
```

The monitor will:
- ✅ Start minimized to system tray
- ✅ Watch `logs/wrapped_scripts/` directory
- ✅ Show notifications for new errors
- ✅ Provide error dashboard

### **Step 2: Use the Monitor**

**Tray Icon Actions:**
- Left-click: View recent errors
- Right-click: Open menu
  - "Open Log Directory" - Browse error logs
  - "View Recent Errors" - Show error list
  - "Pause Monitoring" - Temporarily disable
  - "Exit" - Close monitor

### **Step 3: Auto-Start on Boot (Optional)**

Create shortcut in startup folder:

```powershell
$startup = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$target = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$scriptPath = "C:\Users\uphol\Documents\Design\Coding\AHK\!Running\AutoHotkey\GlobalErrorMonitor.ahk"

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$startup\AHK Error Monitor.lnk")
$Shortcut.TargetPath = $target
$Shortcut.Arguments = "`"$scriptPath`""
$Shortcut.WindowStyle = 7  # Minimized
$Shortcut.Save()
```

---

## 🚀 **Advanced: DBGp Debugger Interception**

For maximum control, intercept at the debugger level (see `notes/DEBUGGER_ARCHITECTURE.md`).

### **Overview**

This approach:
1. Modifies AutoHotkey source (`source/Debugger.cpp`)
2. Adds logging to `ReceiveCommand()` and `SendResponse()`
3. Runs a Node.js MCP server as proxy
4. Intercepts DBGp protocol XML messages
5. Extracts error information from protocol

### **Setup Summary**

**1. Build Modified AutoHotkey:**
```cpp
// In source/Debugger.cpp, add:
void LogDebugEvent(const char* type, const char* data, size_t size) {
    FILE* logFile = fopen("ahk_debugger_events.log", "a");
    fprintf(logFile, "[%s] %.*s\n", type, (int)size, data);
    fclose(logFile);
}

// In ReceiveCommand() after line 2389:
LogDebugEvent("RECV", mCommandBuf.mData, u);

// In SendResponse() after line 2427:
LogDebugEvent("SEND", mResponseBuf.mData + aStartOffset,
              mResponseBuf.mDataUsed - aStartOffset);
```

**2. Set Environment Variables:**
```bash
# Redirect debugger to proxy
set AHK_DEBUGGER_PROXY_HOST=127.0.0.1
set AHK_DEBUGGER_PROXY_PORT=9002
```

**3. Run Scripts in Debug Mode:**
```bash
AutoHotkey.exe /Debug YourScript.ahk
```

**4. Start MCP Server:**
```bash
node notes/ahk-debugger-mcp-server.js
```

**Benefits:**
- 🎯 Intercepts ALL errors (even unhandled)
- 🎯 Full stack traces with variable states
- 🎯 Breakpoint information
- 🎯 Post-mortem analysis capability
- 🎯 No script modification required

**Drawbacks:**
- ❌ Requires C++ compilation
- ❌ Complex setup
- ❌ Performance overhead
- ❌ Scripts must run with `/Debug` flag

---

## 📊 **Comparison Matrix**

| Feature | Wrapper | File Assoc | Monitor | DBGp |
|---------|---------|------------|---------|------|
| **Ease of Setup** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐ |
| **No Script Mods** | ✅ | ✅ | ❌ | ✅ |
| **Auto-Apply** | ❌ | ✅ | ❌ | ✅ |
| **Detailed Errors** | ✅ | ✅ | ✅ | ⭐⭐⭐⭐⭐ |
| **Performance** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| **IDE Compatible** | ✅ | ❌ | ✅ | ⚠️ |

---

## 🎯 **Recommended Setup**

For most users, use **Wrapper + Monitor**:

1. **Use wrapper for new scripts:**
   ```batch
   RunAHKWithErrors.bat MyNewScript.ahk
   ```

2. **Run background monitor:**
   ```bash
   # Start once, runs in tray
   GlobalErrorMonitor.ahk
   ```

3. **Optional: Add to PATH**
   - Can run `RunAHKWithErrors.bat` from anywhere

4. **For production scripts:**
   - Consider DBGp approach for maximum visibility

---

## 📝 **Configuration**

### **ErrorInterceptor.ahk Settings**

Edit at top of `ErrorInterceptor.ahk`:

```ahkv2
class ErrorConfig {
    static enableLogging := true              ; Enable file logging
    static logDirectory := A_ScriptDir "\logs"  ; Log location
    static showStackTrace := true             ; Show stack in GUI
    static maxStackDepth := 10                ; Max stack frames
}
```

### **RunWithErrorHandler.ahk Settings**

Edit at top of `RunWithErrorHandler.ahk`:

```ahkv2
global ERROR_HANDLER_ENABLED := true
global ERROR_LOGGING_ENABLED := true
```

### **GlobalErrorMonitor.ahk Settings**

Edit at top of `GlobalErrorMonitor.ahk`:

```ahkv2
class MonitorConfig {
    static logDirectory := A_ScriptDir "\logs\wrapped_scripts"
    static checkInterval := 2000              ; Check every 2 sec
    static showNotifications := true
    static maxNotificationsPerMinute := 5
    static notificationTimeout := 10
}
```

---

## 🐛 **Troubleshooting**

### **Wrapper doesn't work**

**Check:**
1. Is `ErrorInterceptor.ahk` in the same directory?
2. Does the target script path exist?
3. Are there syntax errors in the target script?

**Debug:**
```ahkv2
; Add to RunWithErrorHandler.ahk after line 1:
#Warn All, OutputDebug
ListLines(1)
```

### **File association broke**

**Fix:**
```registry
; Restore default (save as RestoreAHK.reg)
Windows Registry Editor Version 5.00

[HKEY_CLASSES_ROOT\AutoHotkeyScript\Shell\Open\Command]
@="\"C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe\" \"%1\" %*"
```

### **Monitor not showing errors**

**Check:**
1. Is the log directory correct?
2. Are scripts using the wrapper?
3. Is monitoring paused? (Check tray menu)

**Debug:**
```ahkv2
; Check log directory
MsgBox(MonitorConfig.logDirectory)

; Force check
CheckForNewErrors()
```

---

## 📚 **Additional Resources**

- **ErrorInterceptor.ahk** - Core error handler implementation
- **notes/DEBUGGER_ARCHITECTURE.md** - DBGp protocol details
- **Module_Errors.md** - AHK v2 error handling patterns
- **AHK v2 Docs** - https://www.autohotkey.com/docs/v2/

---

**You're all set! Choose the approach that fits your workflow best.**
