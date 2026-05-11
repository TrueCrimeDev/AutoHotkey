# AutoHotkey Debugger MCP Server

## Overview

This MCP server connects Claude to the AutoHotkey v2 debugger via DBGp protocol. It enables autonomous debugging: capture errors, analyze them, and auto-apply fixes.

## Available Tools

### Error Capture & Analysis

| Tool | Description |
|------|-------------|
| `capture_error` | Wait for the next error. Returns full context: source lines, stack trace, variables. |
| `analyze_error` | Build an analysis prompt from captured error. Use this to understand the bug. |
| `apply_fix` | Apply a code fix directly to a file. Auto-applies without confirmation. |
| `get_source_context` | Get source lines around a specific line in any file. |
| `list_errors` | List all queued errors without removing them. |
| `clear_errors` | Clear the error queue. |

### Debug Control

| Tool | Description |
|------|-------------|
| `debug_run` | Continue execution until next breakpoint or error. |
| `debug_step_into` | Step into function (line by line, enter functions). |
| `debug_step_over` | Step over function (line by line, skip function calls). |
| `debug_step_out` | Step out of current function. |
| `debug_stop` | Stop the debug session. |
| `debug_status` | Get current debugger status. |

### Breakpoints

| Tool | Description |
|------|-------------|
| `breakpoint_set` | Set breakpoint at file:line with optional condition. |
| `breakpoint_remove` | Remove a breakpoint by ID. |
| `breakpoint_list` | List all active breakpoints. |

### Inspection

| Tool | Description |
|------|-------------|
| `variables_get` | Get all variables in current scope (0=local, 1=global). |
| `evaluate` | Evaluate an expression in current context. |
| `stack_trace` | Get current call stack. |

## Debugging Workflow

### Autonomous Error Fix Loop

When user asks to debug a script:

```
1. User runs: AutoHotkey64.exe /Debug script.ahk
2. Claude calls: debug_run (start execution)
3. Error occurs → Claude calls: capture_error
4. Claude receives full error context
5. Claude analyzes and generates fix
6. Claude calls: apply_fix with the fix
7. User re-runs script → fixed!
```

### Step-by-Step Example

**User**: "Debug my script, it's crashing"

**Claude**:
1. First, check if AHK is connected:
   ```
   Call: debug_status
   ```

2. If not connected, tell user:
   > Run your script with: `C:\Users\uphol\Documents\Design\Coding\AutoHotkey\bin\AutoHotkey64.exe /Debug your_script.ahk`

3. Once connected, run and wait for error:
   ```
   Call: debug_run
   Call: capture_error (timeout: 30000)
   ```

4. Analyze the captured error:
   ```json
   {
     "error_type": "UnsetError",
     "message": "This value has no property named 'value'",
     "file": "C:\\scripts\\test.ahk",
     "line": 6,
     "source_context": [
       {"line": 5, "text": "    ; accessing property"},
       {"line": 6, "text": "    result := data.value", "is_error_line": true},
       {"line": 7, "text": "    return result"}
     ],
     "local_variables": [
       {"name": "data", "value": "{name: \"test\"}", "type": "Object"}
     ]
   }
   ```

5. Generate and apply fix:
   ```
   Call: apply_fix
   Args: {
     "file": "C:\\scripts\\test.ahk",
     "line": 6,
     "original": "    result := data.value",
     "replacement": "    result := data.HasProp('value') ? data.value : 0"
   }
   ```

6. Tell user: "Fixed! The code now checks if 'value' exists. Re-run your script."

## Tool Parameters

### capture_error
```json
{
  "timeout": 30000  // Optional, milliseconds to wait (default: 30000)
}
```

### analyze_error
```json
{
  "error": { /* error object from capture_error */ },
  "use_api": false  // Optional, if true attempts Claude API call (not implemented)
}
```

### apply_fix
```json
{
  "file": "C:\\path\\to\\script.ahk",
  "line": 6,
  "original": "    buggy line here",      // Must match exactly (trimmed)
  "replacement": "    fixed line here"
}
```

### breakpoint_set
```json
{
  "file": "C:\\path\\to\\script.ahk",
  "line": 10,
  "condition": "x > 5"  // Optional
}
```

### variables_get
```json
{
  "context": 0  // 0 = local, 1 = global
}
```

### evaluate
```json
{
  "expression": "myVar.Length"
}
```

### get_source_context
```json
{
  "file": "C:\\path\\to\\script.ahk",
  "line": 10,
  "radius": 5  // Lines before/after (default: 5)
}
```

## Common Patterns

### Quick Fix Pattern
```
capture_error → analyze → apply_fix → done
```

### Interactive Debug Pattern
```
breakpoint_set → debug_run → (hits breakpoint) → variables_get → evaluate → debug_step_over → ...
```

### Inspect Crash Pattern
```
capture_error → stack_trace → variables_get(0) → variables_get(1) → analyze
```

## Important Notes

1. **Connection Required**: AHK must be running with `/Debug` flag to connect.

2. **One Client**: Only one debugger can connect at a time. If another is connected, this will fail.

3. **Port 9000**: Default DBGp port. AHK connects here when started with `/Debug`.

4. **apply_fix Safety**: The tool verifies the original line matches before replacing. If mismatch, it fails safely.

5. **Auto-Apply**: `apply_fix` does NOT ask for confirmation. Use carefully.

## Example Prompts Users Might Give

- "Debug my script" → Use capture_error workflow
- "Set a breakpoint on line 10" → breakpoint_set
- "What's the value of myVar?" → evaluate or variables_get
- "Step through this function" → debug_step_into repeatedly
- "Fix this error" → After capture_error, analyze and apply_fix
- "Show me the call stack" → stack_trace
- "Run until it crashes" → debug_run then capture_error
