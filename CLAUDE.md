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

# Syntax-check / test with the engine (exit 13 = check fail, 14 = test fail)
bin/AutoHotkey64.exe check /ErrorStdOut ScriptName.ahk
bin/AutoHotkey64.exe test /ErrorStdOut ScriptName.ahk

# Regression suite (exit code = failing assertions + crashes)
bin/AutoHotkey64.exe /ErrorStdOut 'qa\run.ahk'

# In-process MCP server (mcp.ahk runs INSIDE the engine; registered as ahk-mcp)
bin/AutoHotkey64.exe debugger-tool/mcp-ahk/mcp.ahk

# Native MCP server verb (compiled into the engine — source/mcp_server.cpp;
# same tools/protocol as mcp.ahk, verified by tests/conformance_native.py)
bin/AutoHotkey64.exe mcp

# Same tools from the shell, no MCP client needed
debugger-tool/mcp-ahk/ahkmcp list
debugger-tool/mcp-ahk/ahkmcp ast_outline 'C:\path\x.ahk'

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

Two servers matter day to day (both use WSL-style command paths in config —
Windows-style `node C:\...` commands silently fail to spawn under the WSL CLI):

**`ahk` (global, `~/.claude.json`)** — the main toolbox: `AHK_Run`, `AHK_Lint`,
`AHK_Diagnostics`, the `uia_*` UI-automation funnel, and `AHK_Debug_DBGp`,
which packs the whole DBGp loop into one tool (actions: start/stop/status, run,
step_into/over/out, capture_error, analyze_error, apply_fix,
breakpoint_set/remove/list, variables_get, evaluate, stack_trace).

**`ahk-mcp` (project, `.mcp.json`)** — `mcp.ahk` running inside the fork engine:

| Tool | Description |
|------|-------------|
| `ast_outline` | Tree-sitter AST outline (classes/functions/methods/properties + line ranges & byte spans); real parse, not regex. Uses the TSParse engine. |
| `get_source_context` | Get source lines around file:line |
| `workspace_symbols` | Scan .ahk files for definitions by name |
| `server_status` | Server/engine info |

Same tools from the shell: `debugger-tool\mcp-ahk\ahkmcp <tool> [args]`.
The legacy Node server (`debugger-tool/mcp-server`) still exists but is no
longer registered; `AHK_Debug_DBGp` replaced it.

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
- **`TSParse(Source)`** — parse AHK source with the bundled tree-sitter grammar; returns a snapshot tree of plain AHK objects. Lazily loads `bin/tree-sitter-ahk.dll` on first call. Returns `{ Root, Source, HasError }`; each node has `Type`, `StartByte`/`EndByte`, `StartRow`/`StartCol`/`EndRow`/`EndCol`, `Text`, `IsNamed`/`IsMissing`/`IsError`/`IsExtra`/`HasError`, `FieldName`, `Children`, `NamedChildren`, `Truncated`. For **structure only** — the grammar is incomplete (false `HasError` on valid code); use `check` for validity. Full docs: `docs/TREE_SITTER.md`.

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

---

# Current State & Open Items (updated 2026-08-26)

- `bin/AutoHotkey64.exe` = TSParse-enabled CI build, `2.1-alpha.30+Console`.
  The engine **cannot be built in WSL** (MSVC-only for CI; canonical local
  route is `build.bat` via mingw-w64/`C:\msys64` from Windows). To verify
  source/ changes, use the GitHub Actions PR build and `gh run download`.
- `qa/` is the fork regression suite (subprocess-per-test; see `qa/README.md`).
  Keep it green: `bin\AutoHotkey64.exe /ErrorStdOut qa\run.ahk` → exit 0.
- `WORKLOG.md` tracks the verification-layer backlog (struct/language/docs
  tests) and per-session findings.

Open items:
- [ ] Fix the **10 stale example files** using removed alpha.30 Struct
  type-strings (`i32`/`u32`/`u8`/`uptr` → `Int32`/`UInt32`/`UInt8`/`UIntPtr`):
  `examples/AlphaNN_Example.ahk`, `examples/alpha_tricks.ahk`,
  `examples/combined_alpha22_23.ahk` (+ `examples/particle_gui.ahk` via
  `#Include`). Removed by upstream commits `7427d3bc` / `34b17011`.
- [ ] Faster tree-sitter path: build `tree-sitter-ahk.wasm` + `web-tree-sitter`
  for in-process, incremental parsing in a Node host. Needs the grammar
  **source** — only the `.dll` is vendored.
- [ ] `FileRead` on a zero-byte file returns **no value** on this alpha
  (see WORKLOG 2026-08-26) — pin intended behavior with a qa test.
