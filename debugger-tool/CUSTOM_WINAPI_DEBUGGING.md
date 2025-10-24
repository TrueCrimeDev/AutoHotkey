# Custom WinAPI Debugging Methods

This guide shows **all the ways** you can use Windows API to debug AutoHotkey without using the standard DBGp socket approach.

## Overview of Methods

| Method | Complexity | Speed | Requires AHK Mods | Admin Required |
|--------|-----------|-------|-------------------|----------------|
| **DBGp Sockets** | Low | Medium | No | No |
| **Windows Debug API** | Medium | Medium | No | Sometimes |
| **Shared Memory** | Medium | **Very Fast** | Yes | No |
| **Direct Memory Read** | High | Fast | No | Sometimes |
| **Named Pipes** | Low | Fast | Yes | No |
| **DLL Injection** | Very High | **Very Fast** | No | Yes |

## Method 1: Windows Debug API (DebugActiveProcess)

**What it is:** The same API Visual Studio uses to debug programs.

**Advantages:**
- ✓ No modifications to AutoHotkey needed
- ✓ Intercept ALL exceptions, breakpoints, DLL loads
- ✓ Read/write any memory
- ✓ Control threads
- ✓ Works even without `/Debug` flag

**Disadvantages:**
- ✗ Lower level (harder to use)
- ✗ No AutoHotkey-specific information (line numbers, variables)
- ✗ May require admin privileges
- ✗ Only one debugger can attach at a time

### Example Code

See: `examples/winapi_debug_api.cpp`

```cpp
#include <windows.h>

int main() {
    DWORD pid = /* AutoHotkey PID */;

    // Attach as debugger
    DebugActiveProcess(pid);

    // Event loop
    DEBUG_EVENT debugEvent;
    while (WaitForDebugEvent(&debugEvent, INFINITE)) {
        switch (debugEvent.dwDebugEventCode) {
            case EXCEPTION_DEBUG_EVENT:
                printf("Exception at: 0x%p\n",
                    debugEvent.u.Exception.ExceptionRecord.ExceptionAddress);
                break;

            case LOAD_DLL_DEBUG_EVENT:
                printf("DLL loaded at: 0x%p\n",
                    debugEvent.u.LoadDll.lpBaseOfDll);
                break;

            case OUTPUT_DEBUG_STRING_EVENT:
                // Read debug output from AutoHotkey
                break;
        }

        ContinueDebugEvent(debugEvent.dwProcessId,
                          debugEvent.dwThreadId,
                          DBG_CONTINUE);
    }
}
```

### Key Functions

- `DebugActiveProcess(pid)` - Attach to process
- `WaitForDebugEvent(&event, timeout)` - Wait for debug event
- `ContinueDebugEvent(pid, tid, status)` - Resume execution
- `DebugActiveProcessStop(pid)` - Detach debugger
- `ReadProcessMemory()` - Read target memory
- `WriteProcessMemory()` - Modify target memory

### Use Cases

- Crash analysis (catch access violations)
- DLL load monitoring (security analysis)
- Low-level debugging when DBGp isn't available
- Exception tracking

## Method 2: Shared Memory (CreateFileMapping)

**What it is:** A region of memory shared between AutoHotkey and your debugger.

**Advantages:**
- ✓ **100x faster than sockets** (microseconds vs milliseconds)
- ✓ Can poll at 100+ Hz for real-time monitoring
- ✓ No network stack overhead
- ✓ Simple to use

**Disadvantages:**
- ✗ Requires modifying AutoHotkey source
- ✗ Must synchronize access (use volatiles or mutexes)
- ✗ Windows-only

### Example Code

See: `examples/winapi_shared_memory_reader.cpp`

**Your debugger:**
```cpp
// Open shared memory
HANDLE hMapFile = OpenFileMapping(
    FILE_MAP_READ,
    FALSE,
    "AhkDebugState"
);

DebugState* state = (DebugState*)MapViewOfFile(
    hMapFile,
    FILE_MAP_READ,
    0, 0,
    sizeof(DebugState)
);

// Read state instantly - no sockets!
printf("Current line: %d\n", state->current_line);
printf("Status: %s\n", GetStatus(state->status));
```

**AutoHotkey modifications (in `source/Debugger.cpp`):**
```cpp
// Create shared memory
HANDLE hSharedMem = CreateFileMapping(
    INVALID_HANDLE_VALUE,
    NULL,
    PAGE_READWRITE,
    0,
    sizeof(DebugState),
    "AhkDebugState"
);

gDebugState = (DebugState*)MapViewOfFile(
    hSharedMem,
    FILE_MAP_ALL_ACCESS,
    0, 0,
    sizeof(DebugState)
);

// Update in PreExecLine()
gDebugState->current_line = aLine->mLineNumber;
gDebugState->status = STATUS_BREAK;
gDebugState->last_update = GetTickCount();
```

### Shared Structure Example

```cpp
struct DebugState {
    volatile DWORD magic;        // Validation
    volatile DWORD current_line;
    volatile DWORD status;
    char current_file[260];

    struct Variable {
        char name[64];
        char value[256];
    } variables[32];
    volatile DWORD variable_count;
};
```

### Performance Comparison

| Operation | Sockets | Shared Memory | Speedup |
|-----------|---------|---------------|---------|
| Read current line | ~1ms | ~10μs | **100x** |
| Read 32 variables | ~5ms | ~20μs | **250x** |
| Poll rate | ~10 Hz | >1000 Hz | **100x** |

### Use Cases

- Real-time profiling
- High-frequency performance monitoring
- Live variable watching
- Hot path analysis

## Method 3: Direct Memory Reading (ReadProcessMemory)

**What it is:** Read AutoHotkey's memory directly without its cooperation.

**Advantages:**
- ✓ No modifications to AutoHotkey needed
- ✓ Can inspect any data structure
- ✓ Works on already-running processes
- ✓ Useful for analysis/reverse engineering

**Disadvantages:**
- ✗ Need to know exact memory addresses
- ✗ Requires symbols (.pdb) or reverse engineering
- ✗ Fragile (breaks with different builds)
- ✗ May require admin privileges

### Example Code

See: `examples/winapi_memory_reader.cpp`

```cpp
// Open process
HANDLE hProcess = OpenProcess(
    PROCESS_VM_READ | PROCESS_QUERY_INFORMATION,
    FALSE,
    pid
);

// Read memory at specific address
DWORD value;
SIZE_T bytesRead;
ReadProcessMemory(
    hProcess,
    (LPCVOID)0x12345678,  // Address (must know this!)
    &value,
    sizeof(value),
    &bytesRead
);

// Search for patterns
const BYTE pattern[] = {0x48, 0x89, 0x5C, 0x24, 0x08};  // mov [rsp+8], rbx
LPVOID found = FindPattern(hProcess, baseAddr, size, pattern, sizeof(pattern));
```

### Finding Addresses

**Method A: Use PDB Symbols**
```cpp
#include <dbghelp.h>

SymInitialize(hProcess, NULL, TRUE);
SymLoadModuleEx(hProcess, NULL, "AutoHotkey.exe", NULL, baseAddr, size, NULL, 0);

SYMBOL_INFO* symbol = (SYMBOL_INFO*)malloc(sizeof(SYMBOL_INFO) + 256);
symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
symbol->MaxNameLen = 255;

if (SymFromName(hProcess, "g_script", symbol)) {
    printf("g_script at: 0x%llx\n", symbol->Address);
}
```

**Method B: Signature Scanning**
```cpp
// Find unique byte patterns from disassembly
// Example: Look for the function that updates current line
BYTE signature[] = {
    0x89, 0x0D, 0xFF, 0xFF, 0xFF, 0xFF,  // mov [g_current_line], ecx
    // FF FF FF FF = wildcard (address varies)
};

LPVOID addr = SignatureScan(hProcess, baseAddr, size, signature, sizeof(signature));
```

**Method C: Manual Reverse Engineering**
- Use x64dbg or IDA Pro to find addresses manually
- Set breakpoints on interesting functions
- Note addresses and automate reading them

### Use Cases

- Analyzing closed-source AutoHotkey builds
- Extracting data without modifying source
- Security research
- Memory forensics

## Method 4: Named Pipes (CreateNamedPipe)

**What it is:** Windows IPC mechanism, faster than TCP sockets for local communication.

**Advantages:**
- ✓ **2-3x faster than sockets**
- ✓ Windows-native
- ✓ Better for local communication
- ✓ Supports message mode (vs byte stream)

**Disadvantages:**
- ✗ Requires modifying AutoHotkey source
- ✗ Windows-only
- ✗ No network transparency

### Example Code

**Your debugger (server):**
```cpp
// Create named pipe
HANDLE hPipe = CreateNamedPipe(
    "\\\\.\\pipe\\AhkDebugger",
    PIPE_ACCESS_DUPLEX,
    PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
    1,              // Max instances
    8192,           // Output buffer
    8192,           // Input buffer
    0,              // Default timeout
    NULL
);

// Wait for AutoHotkey to connect
ConnectNamedPipe(hPipe, NULL);

// Send command
DWORD written;
WriteFile(hPipe, "step_into -i 1\0", 16, &written, NULL);

// Receive response
char buffer[8192];
DWORD read;
ReadFile(hPipe, buffer, sizeof(buffer), &read, NULL);
```

**AutoHotkey modifications (in `source/Debugger.cpp`):**
```cpp
// Connect to debugger via named pipe
HANDLE hPipe = CreateFile(
    "\\\\.\\pipe\\AhkDebugger",
    GENERIC_READ | GENERIC_WRITE,
    0,
    NULL,
    OPEN_EXISTING,
    0,
    NULL
);

// Use hPipe instead of socket for all communication
// Same DBGp protocol, different transport!
```

### Performance

| Transport | Latency | Throughput |
|-----------|---------|------------|
| TCP Socket | 1-2ms | ~50 MB/s |
| Named Pipe | 0.3-0.5ms | ~150 MB/s |
| Shared Memory | 0.01ms | >1 GB/s |

### Use Cases

- High-performance local debugging
- Replacing sockets when network isn't needed
- Better latency for interactive debugging

## Method 5: DLL Injection + Hooking (Advanced)

**What it is:** Inject a DLL into AutoHotkey, hook functions, read data directly.

**Advantages:**
- ✓ **Fastest possible access** (running in same process)
- ✓ Can hook any function
- ✓ Read local variables from stack
- ✓ Modify behavior at runtime

**Disadvantages:**
- ✗ Very complex
- ✗ Requires admin privileges
- ✗ Can destabilize target process
- ✗ May be flagged by antivirus

### High-Level Overview

```cpp
// 1. Inject DLL into AutoHotkey process
InjectDLL(pid, "DebuggerHook.dll");

// 2. Inside DebuggerHook.dll:
//    Hook Script::ExecLine using Detours or MinHook
void HookedExecLine(Line* aLine) {
    // We're now running INSIDE AutoHotkey!
    // Can access all variables directly
    printf("Executing line: %d\n", aLine->mLineNumber);

    // Call original function
    OriginalExecLine(aLine);
}

// 3. Install hook
DetourAttach(&(PVOID&)OriginalExecLine, HookedExecLine);
```

### Tools Needed

- **Microsoft Detours** - Function hooking library
- **MinHook** - Lightweight alternative
- **DLL Injector** - LoadLibrary injection or manual mapping

### Use Cases

- Game hacking / automation debugging
- Deep behavioral analysis
- When you need maximum control
- Advanced security research

## Comparison Table

| Feature | DBGp Sockets | Debug API | Shared Mem | Memory Read | Named Pipes | DLL Inject |
|---------|-------------|-----------|------------|-------------|-------------|------------|
| **Speed** | ⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Ease** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ | ⭐ |
| **Reliability** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| **AHK Mods** | No | No | Yes | No | Yes | No |
| **Admin** | No | Sometimes | No | Sometimes | No | Yes |
| **Platform** | Cross | Windows | Windows | Windows | Windows | Windows |

## Recommendations

### For Beginners
→ **Use DBGp Sockets** (`winapi_simple_client.cpp` or `simple_client.py`)
- Works out of the box
- Well documented
- IDE support

### For Performance
→ **Use Shared Memory** (`winapi_shared_memory_reader.cpp`)
- 100x faster than sockets
- Perfect for profiling
- Requires minor AHK source changes

### For System-Level Debugging
→ **Use Windows Debug API** (`winapi_debug_api.cpp`)
- No AHK modifications
- Catch crashes and exceptions
- Low-level control

### For Analysis
→ **Use Direct Memory Read** (`winapi_memory_reader.cpp`)
- Inspect running processes
- Useful for reverse engineering
- No cooperation needed

### For Production Tools
→ **Use Named Pipes** (modify `Debugger.cpp`)
- Better than sockets for local use
- 2-3x faster
- Windows-native

### For Research
→ **Use DLL Injection** (advanced)
- Maximum control
- In-process access
- Complex but powerful

## Code Examples

All working examples are in `examples/`:

1. `winapi_simple_client.cpp` - DBGp over sockets (easiest)
2. `winapi_interactive_client.cpp` - Interactive DBGp debugger
3. `winapi_debug_api.cpp` - Windows Debug API
4. `winapi_shared_memory_reader.cpp` - Shared memory (fastest)
5. `winapi_memory_reader.cpp` - Direct memory reading

Build any example:
```bash
# MSVC
cl example.cpp /link ws2_32.lib

# MinGW
g++ example.cpp -lws2_32 -o example.exe
```

## Further Reading

- **Windows Debug API**: https://docs.microsoft.com/en-us/windows/win32/debug/debugging
- **Shared Memory**: https://docs.microsoft.com/en-us/windows/win32/memory/creating-named-shared-memory
- **Named Pipes**: https://docs.microsoft.com/en-us/windows/win32/ipc/named-pipes
- **Process Memory**: https://docs.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-readprocessmemory
- **DBGp Protocol**: https://xdebug.org/docs/dbgp

## Summary

**Yes, you can absolutely use custom WinAPI interactions!** You have at least 6 different methods:

1. **DBGp Sockets** (standard, easy)
2. **Windows Debug API** (no modifications needed)
3. **Shared Memory** (100x faster)
4. **Direct Memory Read** (reverse engineering)
5. **Named Pipes** (faster local IPC)
6. **DLL Injection** (maximum power)

Choose based on your needs: ease of use, performance, or level of control required.
