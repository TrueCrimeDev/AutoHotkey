# AutoHotkey v2 Low-Level Debugger Tool

**A complete debugging and analysis toolkit for AutoHotkey v2 scripts**

This tool leverages the built-in DBGp debugger protocol in AutoHotkey v2 to provide powerful script analysis, debugging, and security monitoring capabilities.

---

## 🎯 Quick Start (3 Steps)

### Step 1: Start the Debugger Client

```bash
cd debugger-tool/examples
python simple_client.py
```

### Step 2: Run Your AHK Script with Debugging

```bash
AutoHotkey.exe /Debug your_script.ahk
```

### Step 3: Control Execution

The debugger client can now:
- ✓ Step through code line-by-line
- ✓ Inspect variables in real-time
- ✓ Set breakpoints at specific lines
- ✓ View call stacks and exceptions
- ✓ Modify values during execution

**That's it!** The debugger is already built into AutoHotkey v2.

---

## 📚 Documentation

| Document | Description | Start Here |
|----------|-------------|------------|
| **[QUICK_START_GUIDE.md](QUICK_START_GUIDE.md)** | Complete beginner tutorial with working examples | ⭐ **New users** |
| **[IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md)** | Advanced techniques, custom commands, security analysis | ⭐ **Advanced users** |
| **[examples/README.md](examples/README.md)** | Runnable code examples and tutorials | ⭐ **Hands-on learners** |

---

## 🚀 What Can You Build?

### 1. **IDE Integration**
Create debugger extensions for VSCode, Vim, or any editor

### 2. **Automated Testing**
```python
client.run()
assert client.get_variable("result") == "expected"
```

### 3. **Performance Profiler**
Track function execution times, identify bottlenecks, generate flame graphs

### 4. **Security Analyzer**
Detect malicious patterns: keyloggers, persistence mechanisms, process injection

### 5. **Behavior Monitor**
Watch variable changes, log execution traces, analyze program flow

---

## 📦 What's Included

```
debugger-tool/
├── README.md                    ← You are here
├── QUICK_START_GUIDE.md         ← Beginner tutorials
├── IMPLEMENTATION_GUIDE.md      ← Advanced implementation
├── examples/
│   ├── README.md                ← Quick reference
│   ├── simple_client.py         ← Minimal debugger (30 sec)
│   ├── tutorial1_client.py      ← Step-through debugger (2 min)
│   ├── test_script.ahk          ← Test script
│   └── tutorial1.ahk            ← Tutorial script
└── advanced/
    └── (Coming soon: behavior analyzer, profiler, etc.)
```

---

## 🔧 Requirements

- **AutoHotkey v2** (installed or built from `../source/`)
- **Python 3.7+** (no external dependencies - uses standard library only!)
- **Port 9000** available on localhost

---

## 💡 How It Works

### Architecture

```
┌────────────────────────┐         ┌──────────────────────┐
│   Python Client        │  DBGp   │   AutoHotkey.exe     │
│   (Debugger)           │◄───────►│   with /Debug flag   │
│                        │  TCP    │                      │
│   Listens on :9000     │         │   Connects as client │
│   Sends commands       │         │   Sends status       │
│   Receives responses   │         │   Executes script    │
└────────────────────────┘         └──────────────────────┘
```

### DBGp Protocol (Same as Xdebug)

**Commands you send:**
```
run -i 1\0              → Continue execution
step_into -i 2\0        → Step to next line
breakpoint_set ...      → Set breakpoint
property_get -n var\0   → Get variable value
```

**Responses you get:**
```xml
<response command="step_into" status="break" reason="ok"/>
<property name="myVar" type="String">Hello</property>
```

### Integration Points in C++

The debugger hooks into AutoHotkey at these key points:

**Every script line:**
```cpp
// source/script.cpp:10027
if (g_Debugger.IsConnected())
    g_Debugger.PreExecLine(this);
```

**Every function call:**
```cpp
// source/script_expression.cpp:2065
DEBUGGER_STACK_PUSH(&recurse);
```

**Every exception:**
```cpp
// source/error.cpp:136
if (g_Debugger.PreThrow(exception)) { ... }
```

---

## 🎓 Learning Path

### Beginner (30 minutes)
1. ✓ Run `examples/simple_client.py` with `test_script.ahk`
2. ✓ Run `examples/tutorial1_client.py` to see stepping
3. ✓ Read **QUICK_START_GUIDE.md** sections 1-3

### Intermediate (2 hours)
1. ✓ Complete all tutorials in **QUICK_START_GUIDE.md**
2. ✓ Create your own test scripts
3. ✓ Experiment with breakpoints and variable watching

### Advanced (1 day)
1. ✓ Read **IMPLEMENTATION_GUIDE.md** fully
2. ✓ Build a custom debugger client for your use case
3. ✓ Integrate with your IDE or testing framework

### Expert (Ongoing)
1. ✓ Modify `../source/Debugger.cpp` to add custom commands
2. ✓ Build automated security analysis tools
3. ✓ Create performance profiling system

---

## 🛠️ Common Use Cases

### Debug Infinite Loops
```python
client.connect()
client._command("break")  # Pause execution
stack = client.get_stack()  # See where it's stuck
```

### Find Variable Corruption
```python
while True:
    client.step_into()
    value = client.get_variable("myVar")
    if value != expected:
        print(f"Corrupted at line {stack[0]['lineno']}")
        break
```

### Profile Performance
```python
import time
for _ in range(1000):
    start = time.time()
    client.step_into()
    elapsed = time.time() - start
    # Track slowest operations
```

### Detect Malware
```python
# Check for suspicious patterns
source_line = client.get_source_line()
if "Download" in source_line and ".exe" in source_line:
    alert("Potential malware detected!")
```

---

## 🔒 Security Considerations

### Safe by Default
- Debugger **only listens on localhost** (not exposed to network)
- Requires **explicit /Debug flag** to enable
- Uses standard DBGp protocol (same as Xdebug)

### Security Analysis Features
- Detect registry persistence mechanisms
- Identify download-and-execute patterns
- Monitor keylogging behavior
- Track process injection attempts
- Flag anti-analysis techniques

See **IMPLEMENTATION_GUIDE.md** for complete behavior analyzer implementation.

---

## 🐛 Troubleshooting

### "Connection refused"
**Fix:** Always start Python client FIRST, then AHK

```bash
# Correct order:
python simple_client.py    # Terminal 1 - waits
AutoHotkey.exe /Debug script.ahk  # Terminal 2 - connects
```

### "Port already in use"
**Fix:** Kill process on port 9000

```bash
# Linux/Mac
lsof -ti:9000 | xargs kill

# Windows
netstat -ano | findstr :9000
taskkill /PID <pid> /F
```

### "Variables not showing"
**Fix:** Variables only exist after assignment. Step past the line that creates them.

---

## 📖 Additional Resources

### Official Documentation
- **DBGp Protocol Spec:** https://xdebug.org/docs/dbgp
- **AutoHotkey v2 Docs:** https://www.autohotkey.com/docs/v2/

### Related Files in Repository
- **C++ Debugger Implementation:** `../source/Debugger.cpp` (3,255 lines)
- **Debugger Header:** `../source/Debugger.h`
- **Codebase Review:** `../CODEBASE_REVIEW.md`

---

## 🤝 Contributing

This tool is part of the AutoHotkey v2 codebase analysis project. Contributions welcome!

### Ideas for Contributions
- Additional example scripts
- IDE integration plugins
- Performance profiling tools
- Security analysis patterns
- Documentation improvements

---

## 📝 License

This debugging tool documentation and examples are provided for educational and analysis purposes.

AutoHotkey itself is licensed under GNU GPL v2.

---

## ✨ Quick Examples

### Example 1: Minimal Debugger (30 seconds)
```bash
cd examples
python simple_client.py &
AutoHotkey.exe /Debug test_script.ahk
```

### Example 2: Step Through Code (2 minutes)
```bash
cd examples
python tutorial1_client.py &
AutoHotkey.exe /Debug tutorial1.ahk
```

### Example 3: Watch Variables Change
```python
from debugger_client import DebugClient
client = DebugClient()
client.connect()

while True:
    client.step_into()
    value = client.get_variable("counter")
    print(f"counter = {value}")
```

---

## 🎉 Get Started Now!

```bash
cd debugger-tool/examples
python simple_client.py
```

Then in another terminal:
```bash
AutoHotkey.exe /Debug test_script.ahk
```

**Happy Debugging!** 🚀

---

**Last Updated:** 2025-10-23
**Version:** 1.0
**Maintainer:** Claude Code Review System
