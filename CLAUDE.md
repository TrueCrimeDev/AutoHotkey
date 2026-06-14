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
| `ast_outline` | Tree-sitter AST outline (classes/functions/methods/properties + line ranges & byte spans); real parse, not regex. Shells to the TSParse engine. |
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

# ⏳ Session Handoff — Pick Up Here (updated 2026-06-14)

Tree-sitter for AHK is integrated end-to-end. **Delete this whole section once you're caught up.**

## Merged this session (all on `alpha`)
- **#15** — moved root tests/examples into `tests/` and `examples/`.
- **#20** — moved root docs to `docs/`; `DarkMode.ahk` → `Lib/DarkMode.ahk` (alpha.30 typed-Struct lib).
- **#21** — vendored `bin/tree-sitter-ahk.dll` (self-contained AHK grammar + runtime, ABI 15) + `tests/test_treesitter_dll.ahk` + `docs/TREE_SITTER.md`.
- **#22** — native `TSParse()` BIF in the engine (`source/error.cpp` + `source/lib/functions.h`). CI-verified x64+Win32; runtime-verified.
- **#23** — `ast_outline` MCP tool (`debugger-tool/mcp-server`) + `scripts/ast_outline.ahk`.

## Binary state
- `bin/AutoHotkey64.exe` = the TSParse-enabled build (installed from the CI artifact; `A_AhkVersion` = `2.1-alpha.30+Console`).
- Previous (REPL, no-TSParse) build backed up at `bin/AutoHotkey64.exe.pre-tsparse.bak` — safe to delete once happy.
- **Can't build the MSVC engine in WSL.** Use the GitHub Actions PR build as the compiler; `gh run download` the artifact. (See memory `engine_build_verify_via_ci`.)

## ⚠️ Do this first after restart
1. **MCP server / port 9000:** the `autohotkey-debug` server hard-binds port 9000 and **only one instance can run**. A stale 1.3-day session was holding it and was killed — port is now free.
2. You had **~6 old `claude` sessions** lingering. Close them so they don't re-grab 9000.
3. `ast_outline` only shows up after the MCP server restarts with the rebuilt `build/` (already rebuilt; `build/` is gitignored). Restart the CLI, or `/mcp` → reconnect `autohotkey-debug`.
4. **Verify:** ask *"Do you have an `ast_outline` tool?"*, then *"Use `ast_outline` on `Lib\DarkMode.ahk`"* (expect ~73 symbols).

## Open decisions (offered, not yet done — pick any)
- [ ] **(recommended)** Make the port-9000 bind **non-fatal** so `ast_outline`/`source_outline`/`workspace_symbols` keep working during a port conflict. Today a clash crashes the *entire* MCP server, taking down tools that don't even use 9000.
- [ ] Fix the **10 stale example files** using removed alpha.30 Struct type-strings (`i32`/`u32`/`u8`/`uptr` → `Int32`/`UInt32`/`UInt8`/`UIntPtr`): all `examples/AlphaNN_Example.ahk`, `examples/alpha_tricks.ahk`, `examples/combined_alpha22_23.ahk`. (`examples/particle_gui.ahk` `#Include`s Alpha22, so it fails too.) Removed by upstream commits `7427d3bc` / `34b17011`.
- [ ] Faster tree-sitter path: build `tree-sitter-ahk.wasm` + `web-tree-sitter` in the Node MCP server (in-process, incremental). Needs the grammar **source** — only the `.dll` is vendored.

## Caveats to remember
- The tree-sitter AHK grammar is **incomplete for this fork**: reports `HasError=1` on *valid* code (typed Structs, fat-arrow methods, hotkeys like `^j::`). Treat output as **structure only** (the symbols/tree); for "does it parse?" use the `check` subcommand — it's ~5× faster *and* correct.
- `ast_outline` doesn't use port 9000 at all (it shells to the engine) — which is why decoupling it from the DBGp listener (first open item) is worth doing.
