# CloudAHK-Style Error Capture for AI Agents

This guide explains how to capture AHK v2 runtime errors for AI agent consumption, similar to the CloudAHK sandbox service.

## The Problem

In AHK v2, `/ErrorStdOut` only captures **load-time** errors. Runtime errors display a dialog that hangs headless execution:

```
Script runs → Error occurs → Dialog appears → Nobody to click OK → Timeout
```

## Solutions

### Option 1: DBGp Error Agent (Recommended - No AHK Modifications)

Use the headless error agent that connects via the debugger protocol:

```bash
# Terminal 1: Start error agent
cd debugger-tool/ahk-error-agent
npm install && npm run build
node dist/index.js -f json -o errors.json -w -v

# Terminal 2: Run script with debug flag
AutoHotkey.exe /Debug your_script.ahk
```

**Output (errors.json):**
```json
{
  "timestamp": "2024-01-15T10:30:45.123Z",
  "script": "your_script.ahk",
  "error": {
    "type": "RuntimeException",
    "message": "This value has no property named \"email\"",
    "line": 47,
    "file": "your_script.ahk"
  },
  "stackTrace": [...],
  "variables": {
    "local": [...],
    "global": [...]
  },
  "context": {
    "surroundingCode": [
      "    45: id := userData.id",
      ">>> 47: email := userData.email",
      "    48: return email"
    ]
  }
}
```

### Option 2: OnError Handler with /include

Inject an error handler that outputs to stderr:

```bash
AutoHotkey.exe /include include/cloudahk-error-handler.ahk /ErrorStdOut your_script.ahk 2>&1
```

**Included files:**
- `include/cloudahk-error-handler.ahk` - Basic version (works with stock AHK v2)
- `include/cloudahk-error-handler-enhanced.ahk` - Enhanced version (needs `_ScriptGetLines`)

**Output:**
```
UnsetError: This variable has not been assigned a value.

File: your_script.ahk
Line: 47
What:

Stack:
> Auto-execute

Thread will exit
```

### Option 3: Build AHK with _ScriptGetLines

For full context lines like CloudAHK v1 had, build the `linecontext` branch:

```bash
# Clone and checkout linecontext branch
git clone https://github.com/AutoHotkey/AutoHotkey.git ahk-linecontext
cd ahk-linecontext
git fetch origin linecontext
git checkout linecontext

# Build with Visual Studio (Windows)
# Open AutoHotkeyx.sln and build
```

Then use the enhanced handler:

```bash
AutoHotkey_linecontext.exe /include include/cloudahk-error-handler-enhanced.ahk your_script.ahk
```

**Output with context:**
```
## Runtime Error

**Type:** UnsetError
**Message:** This variable has not been assigned a value.
**File:** your_script.ahk
**Line:** 3
**What:**

### Source Context
```
  001: MsgBox("a")
  002: MsgBox("b")
> 003: MsgBox(Uninitialized)
  004: MsgBox("c")
```
```

## Comparison

| Feature | DBGp Agent | OnError Handler | linecontext Build |
|---------|------------|-----------------|-------------------|
| Works with stock AHK v2 | ✅ | ✅ | ❌ |
| Context lines | ✅ (via debugger) | ❌ | ✅ |
| Variable inspection | ✅ | ❌ | ❌ |
| Stack trace | ✅ | ✅ (basic) | ✅ |
| JSON output | ✅ | With code | With code |
| No network required | ❌ | ✅ | ✅ |

## For Docker/Sandbox Environments

The DBGp approach works well in containers:

```dockerfile
FROM windows/servercore

# Install Node.js and AHK
# ...

# Start error agent in background
CMD ["powershell", "-Command", \
     "Start-Job { node /app/error-agent/dist/index.js -f json -o /output/errors.json -w }; \
      AutoHotkey.exe /Debug /script/input.ahk; \
      Get-Content /output/errors.json"]
```

## API Integration Example

```python
import subprocess
import json

def run_ahk_with_errors(script_content: str) -> dict:
    # Write script to temp file
    with open('/tmp/script.ahk', 'w') as f:
        f.write(script_content)

    # Run with debug flag
    proc = subprocess.run(
        ['AutoHotkey.exe', '/Debug', '/tmp/script.ahk'],
        capture_output=True,
        timeout=30
    )

    # Read error report (if error agent captured anything)
    try:
        with open('/tmp/errors.json') as f:
            return json.load(f)
    except FileNotFoundError:
        return {"success": True, "stdout": proc.stdout.decode()}
```

## References

- [Forum Discussion: _ScriptGetLines](https://www.autohotkey.com/boards/viewtopic.php?f=37&t=109519)
- [DBGp Protocol](https://xdebug.org/docs/dbgp)
- [CloudAHK GitHub](https://github.com/G33kDude/CloudAHK)
