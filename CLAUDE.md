# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

An MCP-based debugging ecosystem for AutoHotkey v2 with LLM integration. Captures errors, analyzes them with AI, and auto-applies fixes.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     MCP Server                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ DBGp Client │  │ Error Queue │  │ Claude API (optional)│  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│                                                              │
│  Tools: capture_error, analyze_error, apply_fix              │
│         debug_*, breakpoint_*, variables_*, get_source_context│
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        Claude Desktop    Cursor/IDE    Headless Script
```

**Core Loop:** `capture_error → analyze_error → apply_fix`

## Running Scripts

```bash
# Run any AHK script (from PowerShell) with the custom console build
& "C:\Users\uphol\Documents\Design\Coding\AutoHotkey\bin\AutoHotkey64.exe" ScriptName.ahk

# Run any AHK script (from WSL) with the custom console build
/mnt/c/Users/uphol/Documents/Design/Coding/AutoHotkey/bin/AutoHotkey64.exe ScriptName.ahk

# Run with debugger enabled (from PowerShell)
& "C:\Users\uphol\Documents\Design\Coding\AutoHotkey\bin\AutoHotkey64.exe" /Debug ScriptName.ahk

# Run with debugger enabled (from WSL, connects to MCP server on port 9000)
/mnt/c/Users/uphol/Documents/Design/Coding/AutoHotkey/bin/AutoHotkey64.exe /Debug ScriptName.ahk

# Preferred from MCP: launch_script tool spawns the engine itself over /Debug=stdio (no port 9000)

# Run a generated snippet from stdin without a temp file
echo 'Print("hi")' | bin/AutoHotkey64.exe /ErrorStdOut *

# Start MCP server
cd debugger-tool/mcp-server && npm run build && node build/index.js

# Start error agent (alternative to MCP)
cd debugger-tool/ahk-error-agent && npm run build && node dist/index.js -v -w
```

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `debugger-tool/mcp-server/` | MCP server for Claude/Cursor integration |
| `debugger-tool/ahk-error-agent/` | Headless error capture agent |
| `debugger-tool/examples/` | Python & C++ debugger examples |
| `source/` | AutoHotkey C++ source (fork with _ScriptGetLines) |
| `Dim_Echo_Box/` | Real-time variable monitoring |
| `training/` | AHK v2 learning examples |

## MCP Tools

| Tool | Description |
|------|-------------|
| `capture_error` | Wait for next error, return full context |
| `analyze_error` | Analyze error (client LLM or Claude API) |
| `apply_fix` | Auto-apply code fix to file |
| `get_source_context` | Get source lines around file:line |
| `debug_run/step_*/stop` | Execution control |
| `breakpoint_set/remove/list` | Breakpoint management |
| `variables_get` | Get variables in scope |
| `stack_trace` | Get call stack |

## _ScriptGetLines

Custom AHK build includes `_ScriptGetLines()` for source context:

```autohotkey
lines := _ScriptGetLines(A_LineFile, A_LineNumber, -3)  ; 3 lines before/after
for line in lines {
    MsgBox Format("{:03}: {}", line.Number, line.Text)
}
```

Merged from lexikos' `linecontext` branch.

## CloudAHK Error Handlers

```bash
# Basic (stock AHK v2)
AutoHotkey.exe /include include/cloudahk-error-handler.ahk script.ahk

# Enhanced (requires _ScriptGetLines build)
AutoHotkey_custom.exe /include include/cloudahk-error-handler-enhanced.ahk script.ahk
```

## AHK v2 Syntax Rules

- Always use `:=` for assignment (never `=`)
- Arrays are 1-indexed
- Use `ComObject()` not `ComObjCreate()`
- ByRef uses `&var` syntax
- GUI uses object syntax: `Gui()` not commands
- Escape backslashes in paths: `\\` or use `/`
- **Always use parentheses on every function call**: `Print("text")` not `Print "text"`, `MsgBox("hi")` not `MsgBox "hi"`, `Eval(expr)` not `Eval expr`. Applies to ALL functions — built-ins, BIFs, user-defined, fork additions. No command-style calls.
- **Backticks are escape characters inside double-quoted strings.** `"`a"` is alert/bell, not a literal backtick. To quote code/identifiers inside Print strings, use single quotes: `Print("'i32' is removed")`. Backticks in `;` comments and `/* */` blocks are fine.

## Fork-only BIFs (always available)

These do not exist in upstream AutoHotkey. Use them directly — no `#include`, no helpers.

- **`Print(Fmt?, Values*)`** — stdout println with built-in `Format` dispatch.
  - `Print()` → blank line
  - `Print("plain text")` → write as-is (single-arg form never goes through Format, so literal `{ }` survive)
  - `Print("x={}, y={}", x, y)` → calls `Format(Fmt, Values*)` then writes
  - **Don't write `Print(Format("...", x))`** — pass the args directly to `Print` instead.
  - Silent no-op when no console is attached.
- **`Eval(Expression)`** — runtime expression eval. Gated by `#EnableEval` directive or `/Eval` CLI flag. Throws `SyntaxError` on parse failure. See `updates.md` section 1.
- **`SyntaxError`** — exception class for parse errors. Has `Message`, `What`, `Extra`, `Line`, `Column`.

Full reference: `updates.md` in the repo root.

## Design Documents

- `docs/plans/2026-01-11-interactive-llm-debugger-design.md` - Current architecture

## DBGp Protocol

AutoHotkey debugger uses DBGp protocol on port 9000:

```bash
# AHK connects TO the debugger (server must be listening first)
1. Start MCP server (listens on 9000)
2. Run: AutoHotkey.exe /Debug script.ahk
3. AHK connects to localhost:9000
```

Key commands: `run`, `step_into`, `step_over`, `breakpoint_set`, `property_get`, `stack_get`
