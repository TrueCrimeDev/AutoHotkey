# Interactive LLM Debugger Design

## Overview

A unified MCP-based debugging system that captures AutoHotkey errors, analyzes them with an LLM, and auto-applies fixes. Uses `_ScriptGetLines` for rich source context.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     MCP Server (Enhanced)                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ DBGp Client │  │ Error Queue │  │ Claude API (optional)│  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
│         │                │                     │             │
│  ┌──────┴────────────────┴─────────────────────┴──────────┐ │
│  │                    Tool Handlers                        │ │
│  │  • capture_error    • analyze_error    • apply_fix     │ │
│  │  • get_source_context (uses _ScriptGetLines OR file)   │ │
│  │  • [existing: debug_*, breakpoint_*, variables_*]      │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        Claude Desktop    Cursor/IDE    Headless Script
```

## Core Loop

```
capture_error → analyze_error → apply_fix → (repeat)
```

## New MCP Tools

### capture_error

Wait for the next error from the debugger and return full context.

**Returns:**
```json
{
  "error_type": "UnsetError",
  "message": "This variable has not been assigned a value.",
  "file": "C:\\scripts\\example.ahk",
  "line": 42,
  "source_context": [
    {"line": 40, "text": "data := LoadConfig()"},
    {"line": 41, "text": "if data.valid {"},
    {"line": 42, "text": "    result := data.value", "is_error_line": true},
    {"line": 43, "text": "}"},
    {"line": 44, "text": "return result"}
  ],
  "stack_trace": [...],
  "local_variables": {...},
  "global_variables": {...}
}
```

### analyze_error

Analyze an error and suggest fixes.

**Parameters:**
- `error`: Error object from `capture_error`
- `use_api`: boolean (default: false) - If true, call Claude API directly. If false, return structured data for client LLM.

**Returns (when use_api=false):**
```json
{
  "error": {...},
  "analysis_prompt": "Structured prompt for LLM analysis",
  "suggested_context": ["relevant files", "patterns to check"]
}
```

**Returns (when use_api=true):**
```json
{
  "diagnosis": "The variable 'data.value' may be unset when data.valid is false",
  "root_cause": "Missing null check before accessing property",
  "suggested_fix": {
    "file": "C:\\scripts\\example.ahk",
    "line": 42,
    "original": "    result := data.value",
    "replacement": "    result := data.HasProp('value') ? data.value : ''"
  },
  "confidence": 0.92
}
```

### apply_fix

Apply a code fix directly to a file.

**Parameters:**
- `file`: Path to the file
- `line`: Line number to replace
- `original`: Original text (for verification)
- `replacement`: New text

**Behavior:**
- Auto-applies immediately (no confirmation)
- Returns success/failure
- If original doesn't match, fails safely

**Returns:**
```json
{
  "success": true,
  "file": "C:\\scripts\\example.ahk",
  "line": 42,
  "applied": "    result := data.HasProp('value') ? data.value : ''"
}
```

## _ScriptGetLines Integration

### Source

Merge from lexikos' `linecontext` branch:
- https://github.com/AutoHotkey/AutoHotkey/tree/linecontext

### Function Signature

```autohotkey
lines := _ScriptGetLines(file, line, count)
; file: Script file path (or A_LineFile)
; line: Center line number
; count: Positive = lines starting at line; Negative = lines before and after
; Returns: Array of {file, number, text} objects
```

### Usage in CloudAHK Handler

```autohotkey
OnError(ErrorHandler, -1)

ErrorHandler(err, mode) {
    context := _ScriptGetLines(err.File, err.Line, -3)  ; 3 lines before/after

    for line in context {
        prefix := line.Number == err.Line ? ">>> " : "    "
        FileAppend(prefix . Format("{:03}", line.Number) . ": " . line.Text . "`n", "*")
    }

    return -1  ; Continue thread
}
```

## Implementation Steps

### Phase 1: Merge _ScriptGetLines

1. Fetch lexikos' linecontext branch
2. Cherry-pick or merge relevant commits into source/
3. Build custom AutoHotkey with _ScriptGetLines enabled
4. Test with cloudahk-error-handler-enhanced.ahk

### Phase 2: Enhance MCP Server

1. Add error queue (buffer errors from DBGp exception events)
2. Implement `capture_error` tool
3. Implement `analyze_error` tool (hybrid mode)
4. Implement `apply_fix` tool
5. Add `get_source_context` tool (reads file or calls _ScriptGetLines via eval)

### Phase 3: Integration

1. Update cloudahk handlers to work with MCP server
2. Test with Claude Desktop
3. Test headless mode with Claude API
4. Update documentation

## Configuration

```json
{
  "mcp_server": {
    "port": 9000,
    "claude_api_key": "optional - for headless mode",
    "auto_capture": true,
    "error_queue_size": 100
  }
}
```

## Client Interaction Examples

### Claude Desktop Session

```
User: Debug my script

Claude: I'll start monitoring for errors.
[calls capture_error]

Claude: Caught an error on line 42 - UnsetError accessing data.value
[calls analyze_error with use_api=false, then analyzes itself]

Claude: The issue is that data.value isn't always set. I'll fix it.
[calls apply_fix]

Claude: Fixed! The line now checks if the property exists before accessing it.
```

### Headless/Automated

```javascript
// CI script or automated testing
const error = await mcp.call('capture_error');
const analysis = await mcp.call('analyze_error', { error, use_api: true });

if (analysis.confidence > 0.8) {
  await mcp.call('apply_fix', analysis.suggested_fix);
  console.log('Auto-fixed:', analysis.diagnosis);
}
```

## Files to Create/Modify

| File | Action |
|------|--------|
| `source/script.cpp` | Merge _ScriptGetLines from linecontext |
| `debugger-tool/mcp-server/src/index.ts` | Add new tools |
| `debugger-tool/mcp-server/src/error-queue.ts` | New: error buffering |
| `debugger-tool/mcp-server/src/claude-api.ts` | New: Claude API client |
| `debugger-tool/mcp-server/src/file-editor.ts` | New: apply_fix implementation |
| `debugger-tool/ahk-error-agent/include/cloudahk-error-handler-enhanced.ahk` | Update for _ScriptGetLines |

## Success Criteria

- [ ] `_ScriptGetLines` works in custom AHK build
- [ ] `capture_error` returns full error context with source lines
- [ ] `analyze_error` works in both modes (client LLM and API)
- [ ] `apply_fix` successfully modifies files
- [ ] Full loop works: error → analyze → fix → re-run
- [ ] Claude Desktop can autonomously debug AHK scripts
