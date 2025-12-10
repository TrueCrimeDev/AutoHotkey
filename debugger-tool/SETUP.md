# Setup Guide

Quick setup for all debugging methods. Pick one based on your needs.

## Quick Comparison

| Method | Time | Build | AutoHotkey Flag | Best For |
|--------|------|-------|-----------------|----------|
| **Python** | 30s | ❌ No | `/Debug` | Quick start, beginners |
| **C++ DBGp** | 2m | ✅ Yes | `/Debug` | Native code, no dependencies |
| **Debug API** | 3m | ✅ Yes | ❌ No | System debugging, attach to any process |
| **Memory Read** | 3m | ✅ Yes | ❌ No | Forensics, analysis |
| **Shared Mem** | 30m+ | ✅ Yes | `/Debug` | 100x faster, requires AHK source mods |

---

## Method 1: Python (Easiest)

```bash
cd debugger-tool/examples
python simple_client.py
```

In another terminal:
```bash
AutoHotkey.exe /Debug test_script.ahk
```

**Interactive mode:** `python tutorial1_client.py`

---

## Method 2: C++ DBGp Sockets

```bash
cd debugger-tool/examples

# Build
build_msvc.bat     # MSVC
build_mingw.bat    # MinGW

# Run
winapi_simple_client.exe
```

Then: `AutoHotkey.exe /Debug test_script.ahk`

**Interactive:** `winapi_interactive_client.exe`

Commands: `step`, `context`, `stack`, `break <line>`, `run`, `quit`

---

## Method 3: Windows Debug API

**No /Debug flag needed!**

```bash
# Build
cl winapi_debug_api.cpp                    # MSVC
g++ winapi_debug_api.cpp -o winapi_debug_api.exe   # MinGW

# Run AutoHotkey normally
AutoHotkey.exe your_script.ahk

# Get PID
tasklist | findstr AutoHotkey
# Or just let the debugger find it

# Attach
winapi_debug_api.exe [PID]
```

Shows: exceptions, DLL loads, crashes, debug output.

---

## Method 4: Direct Memory Reading

```bash
# Build
cl winapi_memory_reader.cpp /link psapi.lib        # MSVC
g++ winapi_memory_reader.cpp -lpsapi -o winapi_memory_reader.exe  # MinGW

# Run AutoHotkey
AutoHotkey.exe your_script.ahk

# Scan memory
winapi_memory_reader.exe [PID]
```

Reads: PE headers, searches patterns, inspects modules.

---

## Method 5: Shared Memory (Advanced)

### Step 1: Modify AutoHotkey Source

**In `source/Debugger.h`:**

```cpp
struct DebugState {
    volatile DWORD magic, pid, status, current_line;
    char current_file[260];
    // Add more fields as needed
};

extern DebugState* gDebugState;
extern HANDLE gDebugSharedMem;
```

**In `source/Debugger.cpp`:**

```cpp
DebugState* gDebugState = NULL;
HANDLE gDebugSharedMem = NULL;

// In init function:
gDebugSharedMem = CreateFileMapping(INVALID_HANDLE_VALUE, NULL,
    PAGE_READWRITE, 0, sizeof(DebugState), "AhkDebugState");
gDebugState = (DebugState*)MapViewOfFile(gDebugSharedMem,
    FILE_MAP_ALL_ACCESS, 0, 0, sizeof(DebugState));
gDebugState->magic = 0x41484B44;
gDebugState->pid = GetCurrentProcessId();

// In PreExecLine:
if (gDebugState) {
    gDebugState->current_line = aLine->mLineNumber;
    gDebugState->status = mCurrBreak ? 2 : 1;
}

// In destructor:
if (gDebugState) UnmapViewOfFile(gDebugState);
if (gDebugSharedMem) CloseHandle(gDebugSharedMem);
```

### Step 2: Rebuild AutoHotkey

```bash
cd source
# Use existing build instructions
```

### Step 3: Build and Run Reader

```bash
cl winapi_shared_memory_reader.cpp
.\winapi_shared_memory_reader.exe
```

100x faster than sockets. Real-time monitoring at 100+ Hz.

---

## Troubleshooting

**Port 9000 in use:**
```bash
netstat -ano | findstr :9000
taskkill /PID <pid> /F
```

**Build fails:**
- MSVC: Use "Developer Command Prompt for VS"
- MinGW: Add to PATH or use full path

**Permission denied:**
- Run as Administrator
- Or disable antivirus temporarily

**AutoHotkey not found:**
```bash
# Add to PATH or use full path:
"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /Debug script.ahk
```

---

## What's Next?

- **Tutorials:** `QUICK_START_GUIDE.md`
- **API Reference:** `WINAPI_REFERENCE.md`
- **Advanced:** `CUSTOM_WINAPI_DEBUGGING.md`
- **Examples:** `examples/README.md`
