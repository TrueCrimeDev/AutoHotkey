#!/bin/bash
# Injects AHK debugger ecosystem context into Claude Code sessions.
# Fired on SessionStart (startup, resume, compact) and UserPromptSubmit (debug-related).

cat <<'CONTEXT'
## AutoHotkey Debugger MCP Ecosystem

You have an MCP server (`autohotkey-debug`) that bridges you to the AutoHotkey v2 debugger via DBGp protocol.

### Architecture
```
Claude Code  ←MCP stdio→  MCP Server (Node.js)  ←DBGp TCP:9000→  AutoHotkey.exe /Debug
```

### Available MCP Tools (22 total)

**Execution control:**
- `debug_run` — continue until breakpoint/error
- `debug_step_into` / `debug_step_over` / `debug_step_out` — line stepping
- `debug_stop` / `debug_status` — session control
- `debug_command` — raw DBGp passthrough

**Breakpoints:**
- `breakpoint_set(file, line, condition?)` → returns ID
- `breakpoint_remove(id)` / `breakpoint_list`

**Inspection:**
- `variables_get(context: 0=local, 1=global)` — scope variables
- `evaluate(expression)` — eval in current context
- `stack_trace` — call stack

**Source intelligence:**
- `get_source_context(file, line, radius?)` — read surrounding lines
- `source_outline(file)` — extract functions/classes/hotkeys/labels
- `workspace_symbols(root?, query?, max_results?)` — scan all .ahk files

**Error capture & analysis (core loop):**
- `capture_error(timeout?)` — BLOCKING wait for next exception (default 30s)
- `analyze_error(error, use_api?)` — build analysis prompt or call Claude API directly
- `apply_fix(file, line, original, replacement)` — verified code replacement

**Variable watches (auto-tracked during stepping):**
- `watch_add(name)` / `watch_remove(name)` / `watch_list`
- Step commands auto-snapshot all watches and return `{ name, value, previous, changed }` array

**Queue management:**
- `list_errors` / `clear_errors`

### Critical Workflow Rules

1. **Connection order**: MCP server must be running BEFORE AHK connects. Tell user:
   `bin\AutoHotkey64.exe /Debug script.ahk`

2. **capture_error is blocking** — call `debug_run` first to start execution, then `capture_error` to wait for the exception.

3. **Error fix loop**: `capture_error` → `analyze_error` → `apply_fix` → user re-runs

4. **Step + watch pattern**: `watch_add("varName")` → then every `debug_step_*` response includes watch changes automatically. No need to call `watch_list` after each step.

5. **analyze_error modes**:
   - `use_api: false` (default) — returns the analysis prompt for YOU to analyze
   - `use_api: true` — calls Anthropic API directly (needs ANTHROPIC_API_KEY in env), returns `{ status: "analyzed", analysis: { diagnosis, root_cause, suggested_fix, confidence } }`

6. **apply_fix safety**: Verifies original line matches (trimmed) before replacing. If mismatch, it fails safely with the actual line content.

7. **File paths**: AHK uses Windows paths (`C:\...`). All MCP tools handle this natively.

### Custom AHK Engine Features

The project's `bin\AutoHotkey64.exe` is a custom build with:
- `/Headless` — suppress all dialogs
- `/Diag=json` — structured JSON diagnostics to stdout
- `check script.ahk` — syntax validation (exit 0=ok, 13=fail)
- `test script.ahk` — test runner (exit 0=pass, 14=fail)
- `_ScriptGetLines()` — programmatic source context
- `/Debug` — connect to DBGp debugger on port 9000

### AHK v2 Syntax Reminders
- Always `:=` for assignment (never `=`)
- Arrays are 1-indexed
- `ComObject()` not `ComObjCreate()`
- ByRef uses `&var` syntax
- GUI: `Gui()` object syntax, not commands
CONTEXT
