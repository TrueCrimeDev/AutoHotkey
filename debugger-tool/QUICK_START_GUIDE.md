# AutoHotkey v2 Debugger - Quick Start Guide

**Last Updated:** 2025-10-23
**Purpose:** Step-by-step guide to use the built-in AHK v2 debugger

---

## Table of Contents

1. [What You Need](#what-you-need)
2. [5-Minute Quick Start](#5-minute-quick-start)
3. [Understanding the Debugger](#understanding-the-debugger)
4. [Step-by-Step Tutorial](#step-by-step-tutorial)
5. [Common Workflows](#common-workflows)
6. [Troubleshooting](#troubleshooting)

---

## What You Need

### Prerequisites

✓ **AutoHotkey v2** installed (or built from this repo)
✓ **Python 3.7+** (for the client examples)
✓ **A text editor** for AHK scripts
✓ **Port 9000 available** on localhost

### Check Your Setup

```bash
# Check if AutoHotkey v2 is installed
AutoHotkey.exe --version

# Check if Python is available
python --version

# Check if port 9000 is free
netstat -an | grep 9000  # Linux/Mac
netstat -an | findstr 9000  # Windows
```

---

## 5-Minute Quick Start

### Step 1: Create a Test Script

**File:** `test_script.ahk`

```autohotkey
; Simple AHK v2 test script for debugging
#Requires AutoHotkey v2.0

myVar := "Hello"
myNumber := 0

Loop 5 {
    myNumber := A_Index
    MsgBox "Iteration " myNumber
}

MsgBox "Done! myVar = " myVar
```

### Step 2: Create Simple Python Client

**File:** `simple_client.py`

```python
#!/usr/bin/env python3
import socket
import xml.etree.ElementTree as ET

def receive_message(sock):
    """Receive DBGp message: [length]\0[XML]\0"""
    # Read length
    length_buf = b''
    while b'\0' not in length_buf:
        length_buf += sock.recv(1)

    length = int(length_buf.rstrip(b'\0'))

    # Read data
    data = b''
    while len(data) < length + 1:
        data += sock.recv(length + 1 - len(data))

    return data.rstrip(b'\0').decode('utf-8')

def send_command(sock, cmd, trans_id):
    """Send DBGp command"""
    message = f"{cmd} -i {trans_id}\0"
    sock.send(message.encode('utf-8'))

# Main
print("[*] Listening on localhost:9000...")
server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('localhost', 9000))
server.listen(1)

print("[*] Waiting for AutoHotkey to connect...")
client, addr = server.accept()
print(f"[+] Connected from {addr}")

# Receive init message
init = receive_message(client)
print(f"\n[+] Init message received:")
print(init[:300] + "...")

# Send run command
print("\n[*] Sending 'run' command...")
send_command(client, "run", 1)
response = receive_message(client)
print(f"[+] Response: {response[:200]}")

print("\n[*] Script is running. Close the MsgBox windows to see it complete.")

# Wait for completion
while True:
    try:
        msg = receive_message(client)
        print(f"\n[+] Received: {msg[:200]}")
        if 'status="stopped"' in msg:
            print("\n[+] Script execution completed!")
            break
    except:
        break

client.close()
server.close()
```

### Step 3: Run It!

**Terminal 1 - Start the debugger client:**
```bash
python simple_client.py
```

**Terminal 2 - Start AutoHotkey with debugging:**
```bash
AutoHotkey.exe /Debug test_script.ahk
```

**Expected Output:**

Terminal 1 (Python):
```
[*] Listening on localhost:9000...
[*] Waiting for AutoHotkey to connect...
[+] Connected from ('127.0.0.1', 58392)

[+] Init message received:
<?xml version="1.0" encoding="UTF-8"?>
<init appid="AutoHotkey" idekey="..." session="..." .../>

[*] Sending 'run' command...
[+] Response: <?xml version="1.0"...status="running"...

[*] Script is running. Close the MsgBox windows to see it complete.

[+] Received: ...status="stopped"...
[+] Script execution completed!
```

Terminal 2 (AHK):
```
[MsgBox windows appear showing iterations 1-5]
[Final MsgBox shows "Done! myVar = Hello"]
```

**Congratulations! You just used the AHK debugger!** 🎉

---

## Understanding the Debugger

### Architecture

```
┌──────────────────────┐         ┌──────────────────────┐
│   Your Python        │  DBGp   │   AutoHotkey.exe     │
│   Debugger Client    │◄───────►│   with /Debug flag   │
│   (localhost:9000)   │  TCP    │                      │
└──────────────────────┘         └──────────────────────┘
         │                                  │
         │ Sends Commands:                 │ Sends Responses:
         │ - run                            │ - status updates
         │ - step_into                      │ - variable values
         │ - breakpoint_set                 │ - stack traces
         │ - property_get                   │ - execution state
         └──────────────────────────────────┘
```

### Command-Line Flag

**Syntax:**
```bash
AutoHotkey.exe /Debug[=host:port] script.ahk
```

**Examples:**
```bash
# Default: localhost:9000
AutoHotkey.exe /Debug script.ahk

# Custom port
AutoHotkey.exe /Debug=localhost:9001 script.ahk

# Specific host (use with caution!)
AutoHotkey.exe /Debug=192.168.1.100:9000 script.ahk
```

**What happens:**
1. AutoHotkey starts with debugger enabled
2. It connects to the specified host:port as a **client**
3. Your debugger tool listens as a **server**
4. AHK sends an `<init>` message
5. Your tool sends commands, AHK responds
6. Script execution is controlled by your tool

### DBGp Protocol Basics

**Message Format:**
```
[length]\0<?xml version="1.0" encoding="UTF-8"?>[XML payload]\0
```

**Example Command:**
```
step_into -i 1\0
```

**Example Response:**
```
119\0<?xml version="1.0" encoding="UTF-8"?>
<response command="step_into" transaction_id="1" status="break" reason="ok"/>\0
```

**Status Values:**
- `starting` - Debugger initialized, waiting for first command
- `running` - Script executing normally
- `break` - Script paused (breakpoint, step, exception)
- `stopped` - Script finished
- `stopping` - Script terminating

---

## Step-by-Step Tutorial

### Tutorial 1: Basic Step-Through Execution

**Goal:** Step through script line-by-line and inspect variables

**Script:** `tutorial1.ahk`

```autohotkey
#Requires AutoHotkey v2.0

name := "Alice"
age := 30
city := "New York"

greeting := "Hello, " name "!"
info := name " is " age " years old and lives in " city

MsgBox greeting
MsgBox info
```

**Client:** `tutorial1_client.py`

```python
#!/usr/bin/env python3
"""
Tutorial 1: Basic stepping and variable inspection
"""
import socket
import xml.etree.ElementTree as ET
import base64

class DebugClient:
    def __init__(self, port=9000):
        self.port = port
        self.trans_id = 0

    def connect(self):
        """Listen for AHK connection"""
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(('localhost', self.port))
        server.listen(1)

        print(f"[*] Listening on localhost:{self.port}...")
        self.sock, addr = server.accept()
        print(f"[+] AHK connected from {addr}")

        # Receive init
        init = self._receive()
        root = self._parse_xml(init)
        print(f"[+] Session: {root.get('session')}")
        print(f"[+] File: {root.get('fileuri')}")

    def _receive(self):
        """Receive DBGp message"""
        # Read length
        length_buf = b''
        while b'\0' not in length_buf:
            length_buf += self.sock.recv(1)
        length = int(length_buf.rstrip(b'\0'))

        # Read data
        data = b''
        while len(data) < length + 1:
            data += self.sock.recv(length + 1 - len(data))

        return data.rstrip(b'\0').decode('utf-8')

    def _send(self, cmd):
        """Send command"""
        self.trans_id += 1
        message = f"{cmd} -i {self.trans_id}\0"
        self.sock.send(message.encode('utf-8'))
        return self.trans_id

    def _parse_xml(self, xml_str):
        """Parse XML response"""
        if xml_str.startswith('<?xml'):
            xml_str = xml_str[xml_str.index('>') + 1:]
        return ET.fromstring(xml_str)

    def _command(self, cmd):
        """Send command and get response"""
        self._send(cmd)
        response = self._receive()
        return self._parse_xml(response)

    def step_into(self):
        """Step into next line"""
        resp = self._command("step_into")
        status = resp.get('status')
        print(f"[→] step_into: status={status}")
        return resp

    def get_stack(self):
        """Get current stack"""
        resp = self._command("stack_get")
        frames = []
        for stack in resp.findall('stack'):
            frames.append({
                'level': int(stack.get('level')),
                'where': stack.get('where', ''),
                'filename': stack.get('filename', ''),
                'lineno': int(stack.get('lineno', 0))
            })
        return frames

    def get_variable(self, name):
        """Get variable value"""
        resp = self._command(f"property_get -n {name}")
        prop = resp.find('property')
        if prop is not None:
            value = prop.text or ''
            if prop.get('encoding') == 'base64':
                value = base64.b64decode(value).decode('utf-8')
            return value
        return None

    def get_all_variables(self):
        """Get all local variables"""
        resp = self._command("context_get")
        variables = {}
        for prop in resp.findall('.//property'):
            name = prop.get('name')
            value = prop.text or ''
            if prop.get('encoding') == 'base64':
                value = base64.b64decode(value).decode('utf-8')
            variables[name] = value
        return variables

# Main script
def main():
    client = DebugClient()
    client.connect()

    print("\n" + "="*60)
    print("TUTORIAL 1: Basic Stepping")
    print("="*60)

    # Step through first few lines
    for step_num in range(1, 8):
        print(f"\n--- Step {step_num} ---")

        # Step into next line
        client.step_into()

        # Get current location
        stack = client.get_stack()
        if stack:
            frame = stack[0]
            print(f"Location: Line {frame['lineno']}")

        # Get all variables
        variables = client.get_all_variables()
        if variables:
            print("Variables:")
            for name, value in variables.items():
                print(f"  {name} = {value}")

    print("\n" + "="*60)
    print("Tutorial complete! Press Ctrl+C to exit.")
    print("="*60)

    # Let script finish
    client._command("run")

if __name__ == '__main__':
    main()
```

**Run Tutorial 1:**

```bash
# Terminal 1
python tutorial1_client.py

# Terminal 2
AutoHotkey.exe /Debug tutorial1.ahk
```

**Expected Output:**

```
[*] Listening on localhost:9000...
[+] AHK connected from ('127.0.0.1', 58493)
[+] Session: 12345...
[+] File: file:///C:/path/to/tutorial1.ahk

============================================================
TUTORIAL 1: Basic Stepping
============================================================

--- Step 1 ---
[→] step_into: status=break
Location: Line 3
Variables:

--- Step 2 ---
[→] step_into: status=break
Location: Line 4
Variables:
  name = Alice

--- Step 3 ---
[→] step_into: status=break
Location: Line 5
Variables:
  name = Alice
  age = 30

--- Step 4 ---
[→] step_into: status=break
Location: Line 6
Variables:
  name = Alice
  age = 30
  city = New York

--- Step 5 ---
[→] step_into: status=break
Location: Line 8
Variables:
  name = Alice
  age = 30
  city = New York
  greeting = Hello, Alice!

--- Step 6 ---
[→] step_into: status=break
Location: Line 9
Variables:
  name = Alice
  age = 30
  city = New York
  greeting = Hello, Alice!
  info = Alice is 30 years old and lives in New York

--- Step 7 ---
[→] step_into: status=break
Location: Line 11
Variables:
  [same as above]

============================================================
Tutorial complete! Press Ctrl+C to exit.
============================================================
```

### Tutorial 2: Breakpoints

**Goal:** Set breakpoints and run until hit

**Script:** `tutorial2.ahk`

```autohotkey
#Requires AutoHotkey v2.0

counter := 0

Loop 10 {
    counter := A_Index

    if (counter = 5) {
        MsgBox "Halfway there!"  ; Line 9 - set breakpoint here
    }

    Sleep 100
}

MsgBox "Done! Counter = " counter
```

**Client:** `tutorial2_client.py`

```python
#!/usr/bin/env python3
"""
Tutorial 2: Breakpoints
"""
import socket
import xml.etree.ElementTree as ET
import base64

class DebugClient:
    # ... (same helper methods as Tutorial 1)

    def set_breakpoint(self, filename, line):
        """Set line breakpoint"""
        # Convert filename to file URI
        file_uri = filename.replace('\\', '/')
        if not file_uri.startswith('file:///'):
            file_uri = f"file:///{file_uri}"

        resp = self._command(f"breakpoint_set -t line -f {file_uri} -n {line}")
        bp_id = resp.get('id')
        print(f"[+] Breakpoint {bp_id} set at line {line}")
        return bp_id

    def run(self):
        """Continue execution"""
        resp = self._command("run")
        status = resp.get('status')
        reason = resp.get('reason', '')
        print(f"[→] run: status={status}, reason={reason}")
        return resp

# Main
def main():
    client = DebugClient()
    client.connect()

    print("\n" + "="*60)
    print("TUTORIAL 2: Breakpoints")
    print("="*60)

    # Get script filename from init
    # (In production, parse from init message)
    script_file = "C:/path/to/tutorial2.ahk"  # Update this path!

    # Set breakpoint at line 9 (the MsgBox line)
    print("\n[*] Setting breakpoint at line 9...")
    client.set_breakpoint(script_file, 9)

    # Run until breakpoint
    print("\n[*] Running script until breakpoint...")
    client.run()

    # Check where we are
    stack = client.get_stack()
    if stack:
        frame = stack[0]
        print(f"\n[!] Stopped at line {frame['lineno']}")

    # Get counter value
    counter = client.get_variable("counter")
    print(f"[!] counter = {counter}")

    # Continue execution
    print("\n[*] Continuing execution...")
    client.run()

    print("\n" + "="*60)
    print("Tutorial complete!")
    print("="*60)

if __name__ == '__main__':
    main()
```

**Run Tutorial 2:**

```bash
# Terminal 1
python tutorial2_client.py

# Terminal 2
AutoHotkey.exe /Debug tutorial2.ahk
```

### Tutorial 3: Watch Variables Change

**Goal:** Monitor variable changes in real-time

**Script:** `tutorial3.ahk`

```autohotkey
#Requires AutoHotkey v2.0

total := 0
iteration := 0

Loop 20 {
    iteration := A_Index
    total := total + iteration

    if (Mod(iteration, 5) = 0) {
        MsgBox "Progress: " iteration " iterations, total = " total
    }
}

MsgBox "Final total: " total
```

**Client:** `tutorial3_client.py`

```python
#!/usr/bin/env python3
"""
Tutorial 3: Variable Watching
"""

class DebugClient:
    # ... (same as before)
    pass

def main():
    client = DebugClient()
    client.connect()

    print("\n" + "="*60)
    print("TUTORIAL 3: Variable Watching")
    print("="*60)

    print("\nWatching variables: total, iteration")
    print("Press Ctrl+C to stop\n")

    step_count = 0
    last_total = None
    last_iteration = None

    while step_count < 100:  # Safety limit
        # Step into
        resp = client.step_into()

        if resp.get('status') == 'stopped':
            print("\n[+] Script completed")
            break

        # Get variables
        try:
            total = client.get_variable("total")
            iteration = client.get_variable("iteration")

            # Check if changed
            if total != last_total or iteration != last_iteration:
                stack = client.get_stack()
                line = stack[0]['lineno'] if stack else '?'

                changes = []
                if total != last_total:
                    changes.append(f"total: {last_total} → {total}")
                if iteration != last_iteration:
                    changes.append(f"iteration: {last_iteration} → {iteration}")

                print(f"[Line {line:2}] {', '.join(changes)}")

                last_total = total
                last_iteration = iteration
        except:
            pass

        step_count += 1

    print("\n" + "="*60)
    print("Tutorial complete!")
    print("="*60)

if __name__ == '__main__':
    main()
```

---

## Common Workflows

### Workflow 1: Debug Infinite Loop

**Problem:** Script hangs, need to find where

**Solution:**

```python
# 1. Connect to hanging script
client = DebugClient()
client.connect()

# 2. Break execution
client._command("break")

# 3. Check stack
stack = client.get_stack()
print("Current location:")
for frame in stack:
    print(f"  {frame['where']} at line {frame['lineno']}")

# 4. Step a few times to see if it's looping
for i in range(10):
    client.step_into()
    stack = client.get_stack()
    print(f"Step {i}: line {stack[0]['lineno']}")
```

### Workflow 2: Find Variable Corruption

**Problem:** Variable has wrong value, need to find when it changes

**Solution:**

```python
# Use conditional breakpoint (if supported) or step-watch pattern
watch_var = "myVariable"
expected_value = "correct_value"

while True:
    client.step_into()

    value = client.get_variable(watch_var)

    if value != expected_value:
        stack = client.get_stack()
        print(f"[!] Variable corrupted at line {stack[0]['lineno']}")
        print(f"    Expected: {expected_value}")
        print(f"    Got: {value}")
        break
```

### Workflow 3: Profile Function Performance

**Problem:** Need to know which function is slow

**Solution:**

```python
import time

function_times = {}

while True:
    # Get current function
    stack = client.get_stack()
    if not stack:
        break

    func_name = stack[0]['where']

    # Time the step
    start = time.time()
    resp = client.step_into()
    elapsed = time.time() - start

    # Track time
    if func_name not in function_times:
        function_times[func_name] = []
    function_times[func_name].append(elapsed)

    if resp.get('status') == 'stopped':
        break

# Report
print("\nSlowest functions:")
for func, times in sorted(function_times.items(),
                         key=lambda x: sum(x[1]),
                         reverse=True)[:10]:
    print(f"{func}: {sum(times):.3f}s ({len(times)} steps)")
```

---

## Troubleshooting

### Issue: "Connection refused"

**Symptoms:**
```
ConnectionRefusedError: [Errno 111] Connection refused
```

**Causes:**
1. AHK started before debugger client
2. Wrong port
3. Firewall blocking

**Solutions:**
```bash
# 1. Always start debugger client FIRST
python client.py   # Terminal 1 - waits
AutoHotkey.exe /Debug script.ahk  # Terminal 2 - connects

# 2. Check port matches
# Client: DebugClient(port=9000)
# AHK: /Debug=localhost:9000

# 3. Check firewall
netstat -an | grep 9000  # Should show LISTENING
```

### Issue: "Socket timeout"

**Symptoms:**
Script hangs, no response from debugger

**Solutions:**
```python
# Add timeout to socket
self.sock.settimeout(30.0)  # 30 second timeout

try:
    response = self._receive()
except socket.timeout:
    print("[!] Timeout waiting for response")
    # Force break
    self._send("break")
```

### Issue: "Variables not visible"

**Symptoms:**
`property_get` returns empty or error

**Causes:**
1. Variable not in scope
2. Variable not initialized yet
3. Wrong stack depth

**Solutions:**
```python
# 1. Check stack depth
stack = client.get_stack()
print(f"Current depth: {len(stack)}")

# 2. Try different context (local vs global)
# Local (context_id=0)
client._command("context_get -c 0")

# Global (context_id=1)
client._command("context_get -c 1")

# 3. Use fullname for nested properties
client.get_variable("myObject.property")
```

### Issue: "Script runs too fast"

**Symptoms:**
Can't see intermediate states

**Solutions:**
```python
# Option 1: Set breakpoints at key lines
client.set_breakpoint(file, 10)
client.set_breakpoint(file, 20)
client.run()  # Runs to next breakpoint

# Option 2: Step with delays
import time
for i in range(100):
    client.step_into()
    time.sleep(0.1)  # Slow down

# Option 3: Conditional stepping
while True:
    client.step_into()
    stack = client.get_stack()

    # Only break at interesting functions
    if 'myFunction' in stack[0]['where']:
        print(f"Entered myFunction at line {stack[0]['lineno']}")
        break
```

---

## Next Steps

### Learn More

1. **Full DBGp Protocol:**
   - Read: https://xdebug.org/docs/dbgp
   - Specification: All supported commands documented

2. **Advanced Examples:**
   - See `DEBUGGER_INTERCEPTOR_GUIDE.md` for:
     - Behavior analyzer (malware detection)
     - Execution tracer
     - Variable monitor

3. **Build Custom Tools:**
   - IDE integration (VSCode extension)
   - Automated testing harness
   - Performance profiler

### Practice Exercises

**Exercise 1:** Build a simple IDE
- Text editor with syntax highlighting
- Show current line during execution
- Display variables in sidebar

**Exercise 2:** Create test runner
- Run script and verify output
- Set breakpoints at assertions
- Report pass/fail

**Exercise 3:** Make performance profiler
- Track function call times
- Generate flamegraph
- Identify bottlenecks

---

## Reference

### Useful Commands Cheat Sheet

```python
# Execution Control
client._command("run")              # Continue execution
client._command("step_into")        # Step into function
client._command("step_over")        # Step over function
client._command("step_out")         # Step out of function
client._command("break")            # Pause execution
client._command("stop")             # Terminate script

# Breakpoints
client._command("breakpoint_set -t line -f file:///script.ahk -n 42")
client._command("breakpoint_list")
client._command("breakpoint_remove -d 1")  # Remove breakpoint ID 1

# Stack & Context
client._command("stack_depth")
client._command("stack_get")
client._command("stack_get -d 2")   # Get frame at depth 2

# Variables
client._command("context_get")              # Local variables
client._command("context_get -c 1")         # Global variables
client._command("property_get -n myVar")    # Get specific variable
client._command("property_set -n myVar -- base64_encoded_value")

# Information
client._command("status")
client._command("feature_get -n max_depth")
client._command("source")           # Get script source
```

### File Paths

- **Debugger Implementation:** `/home/user/AutoHotkey/source/Debugger.cpp`
- **Debugger Header:** `/home/user/AutoHotkey/source/Debugger.h`
- **Integration Point:** `/home/user/AutoHotkey/source/script.cpp:10027`

---

**Document Version:** 1.0
**Author:** Claude Code Review System
**License:** Use freely for AutoHotkey debugging
