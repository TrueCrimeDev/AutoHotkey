# AutoHotkey v2 Debugger Examples

This directory contains working examples for using the AHK v2 debugger.

## Quick Start

### Example 1: Simple Client

**The simplest possible debugger client**

```bash
# Terminal 1 - Start debugger client (waits for connection)
python simple_client.py

# Terminal 2 - Start AHK with debugging
AutoHotkey.exe /Debug test_script.ahk
```

**What it does:**
- Connects to AHK
- Sends "run" command
- Shows status messages
- Waits for completion

### Example 2: Tutorial 1 - Stepping

**Learn how to step through code and inspect variables**

```bash
# Terminal 1
python tutorial1_client.py

# Terminal 2
AutoHotkey.exe /Debug tutorial1.ahk
```

**What it does:**
- Steps through script line-by-line
- Shows current line number
- Displays all variables at each step
- Demonstrates basic debugging workflow

### Example 3: Native WinAPI Simple Client (C++)

**Pure WinAPI debugger - no Python required!**

```bash
# Build with MSVC
build_msvc.bat

# OR build with MinGW
build_mingw.bat

# Run the debugger
winapi_simple_client.exe

# In another terminal
AutoHotkey.exe /Debug test_script.ahk
```

**What it does:**
- Native C++ using Windows Sockets API
- Demonstrates automated debugging workflow
- Sets breakpoints and steps through code
- Shows how to use DBGp protocol directly

### Example 4: Interactive WinAPI Client (C++)

**Full-featured interactive debugger in pure C++**

```bash
# Build (if not already built)
build_msvc.bat   # or build_mingw.bat

# Run
winapi_interactive_client.exe

# In another terminal
AutoHotkey.exe /Debug your_script.ahk

# In the debugger, type commands:
dbg> step        # Step one line
dbg> context     # Show variables
dbg> stack       # Show call stack
dbg> break 10    # Set breakpoint at line 10
dbg> run         # Continue execution
dbg> quit        # Exit
```

**What it does:**
- Interactive command-line debugger
- Real-time stepping and variable inspection
- Native Windows performance
- Shows advanced DBGp protocol usage

## Advanced Custom WinAPI Methods

### Example 5: Windows Debug API (Native Debugger)

**Attach to AutoHotkey using the same API Visual Studio uses!**

```bash
# Build
cl winapi_debug_api.cpp

# Start AutoHotkey normally (no /Debug needed!)
AutoHotkey.exe your_script.ahk

# In another terminal, attach to it
winapi_debug_api.exe <PID>
```

**What it does:**
- Attaches as a native Windows debugger (like Visual Studio)
- Intercepts ALL exceptions, breakpoints, DLL loads
- Read/write process memory directly
- No /Debug flag or DBGp protocol needed!
- System-level debugging

### Example 6: Shared Memory Reader (100x Faster!)

**Read AutoHotkey's state from shared memory - microsecond latency!**

```bash
# Build
cl winapi_shared_memory_reader.cpp

# Modify AutoHotkey source (see comments in file)
# Rebuild AutoHotkey with shared memory support

# Run modified AutoHotkey
AutoHotkey.exe your_script.ahk

# Run the reader
winapi_shared_memory_reader.exe
```

**What it does:**
- 100x faster than sockets (microseconds vs milliseconds)
- Real-time state monitoring at 100+ Hz
- Direct memory access (no network stack)
- Perfect for performance profiling
- Requires AutoHotkey source modification

### Example 7: Direct Memory Reader (Forensics)

**Read AutoHotkey's memory without any cooperation!**

```bash
# Build
cl winapi_memory_reader.cpp /link psapi.lib

# Run AutoHotkey
AutoHotkey.exe your_script.ahk

# Scan its memory
winapi_memory_reader.exe <PID>
```

**What it does:**
- Reads process memory directly using ReadProcessMemory
- Searches for patterns and strings
- Inspects PE headers and loaded modules
- No AutoHotkey modifications needed
- Useful for reverse engineering and analysis

## Files

### Python Clients
| File | Description |
|------|-------------|
| `simple_client.py` | Minimal Python debugger client |
| `tutorial1_client.py` | Step-through Python debugger |

### Native C++ Clients (Standard DBGp)
| File | Description |
|------|-------------|
| `winapi_simple_client.cpp` | Automated C++ debugger using sockets |
| `winapi_interactive_client.cpp` | Interactive C++ debugger using sockets |
| `build_msvc.bat` | Build script for Visual Studio |
| `build_mingw.bat` | Build script for MinGW/GCC |

### Advanced WinAPI Methods (Custom Debugging)
| File | Description |
|------|-------------|
| `winapi_debug_api.cpp` | Windows Debug API (like Visual Studio) |
| `winapi_shared_memory_reader.cpp` | Ultra-fast shared memory debugging |
| `winapi_memory_reader.cpp` | Direct memory reading without cooperation |

### Test Scripts
| File | Description |
|------|-------------|
| `test_script.ahk` | Simple test script |
| `tutorial1.ahk` | Tutorial script with variables |

## Requirements

### For Python Examples
- Python 3.7+ (no external dependencies needed!)

### For C++ Examples
- **MSVC:** Visual Studio 2017+ or Build Tools
- **MinGW:** MinGW-w64 or TDM-GCC
- Windows Sockets library (ws2_32.lib - included with Windows)

### For All Examples
- AutoHotkey v2 installed or built from this repo
- Port 9000 available

## How It Works

```
┌──────────────────┐         ┌──────────────────┐
│  Python Client   │  DBGp   │  AutoHotkey.exe  │
│  (Server mode)   │◄───────►│  (Client mode)   │
│  localhost:9000  │  TCP    │  with /Debug     │
└──────────────────┘         └──────────────────┘
```

1. **Start Python client first** - it listens on port 9000
2. **Start AHK with /Debug** - it connects to the client
3. **AHK sends init message** - contains session info
4. **Client sends commands** - run, step, breakpoint, etc.
5. **AHK sends responses** - status, variables, stack traces

## Common Issues

### "Connection refused"
**Fix:** Always start Python client FIRST, then AHK

### "Port already in use"
**Fix:** Kill other processes on port 9000:
```bash
# Linux/Mac
lsof -ti:9000 | xargs kill

# Windows
netstat -ano | findstr :9000
taskkill /PID <pid> /F
```

### "Variables not showing"
**Fix:** Variables only exist after they're assigned. Step past the assignment line.

## Next Steps

1. Read `../QUICK_START_DEBUGGER.md` for full tutorial
2. See `../DEBUGGER_INTERCEPTOR_GUIDE.md` for advanced topics
3. Build your own debugging tools!

## Examples Coming Soon

- Tutorial 2: Breakpoints
- Tutorial 3: Variable watching
- Tutorial 4: Call stack inspection
- Tutorial 5: Exception handling

## License

Use freely for AutoHotkey debugging and analysis.
