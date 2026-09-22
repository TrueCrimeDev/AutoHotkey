# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A native AutoHotkey `2.1-alpha.31+Console` fork. The engine supplies shell
commands, structured diagnostics, Eval, JSON, Inspect, ProcessPipe, source
introspection, coverage, and an MCP server. The TypeScript debugger integrations
under `debugger-tool/` are separate consumers of the engine's DBGp protocol.

## Architecture

- `source/AutoHotkey.cpp` owns CLI dispatch and GUI/Console entrypoint behavior.
- `source/mcp_server.cpp` serves native MCP over stdio without loading an AHK
  helper script. Start it with `AutoHotkey64Console.exe mcp`.
- Runtime features are registered in `source/lib/functions.h`; consult their
  implementations and `updates.md` before inventing helper dependencies.
- `debugger-tool/mcp-ahk/mcp.ahk` is an alternate script implementation with a
  smaller tool surface. `debugger-tool/mcp-server/` and `ahk-error-agent/` are
  TypeScript DBGp clients/adapters; they are not the native server.
- CMake shares engine objects across GUI, Console, and optional Harness targets.
  Read `BUILD.md` for supported compiler routes and exact-artifact verification.

Do not infer the installed engine version or user-wide MCP registration from
this document. The checked-in `.mcp.json` currently starts the native `mcp` verb
using a WSL path; Windows hosts need a Windows executable path in their own
configuration. Inspect the active host's configuration before changing it.

## Running and testing

Use the exact fresh engine path. An isolated build need not replace `bin/` or
modify an installed alias:

```powershell
$engine = (Resolve-Path out/msvc/x64/AutoHotkey64Console.exe).Path
& $engine --version
& $engine --capabilities
& $engine run ScriptName.ahk
& $engine check /Diag=json ScriptName.ahk
& $engine test /Headless tests/run.ahk
& $engine /Headless '/Coverage=coverage/tests.lcov' test tests/run.ahk
& $engine mcp
python tests/run_console_gate.py $engine
python tools/check_all.py $engine
. ./tools/ahk.ps1 -EnginePath $engine
```

`check` returns 13 for syntax failure; ordinary parse errors return 12, uncaught
runtime errors 10, and explicit test failures 14. Read `--capabilities` for the
complete exit-code contract. `/Headless` and `check` are not sandboxes: loading
can perform operations such as `#DllLoad`. Do not execute arbitrary untrusted
scripts merely to validate them.

## Key directories

| Directory | Purpose |
| --- | --- |
| `source/` | Fork engine and upstream runtime |
| `qa/`, `tests/` | Native regression scripts and protocol/shell integration checks |
| `examples/native-mcp/` | Native MCP use cases and a script client example |
| `debugger-tool/mcp-server/` | Legacy TypeScript MCP/DBGp adapter |
| `debugger-tool/ahk-error-agent/` | Separate error capture agent |
| `debugger-tool/mcp-ahk/` | Alternate script MCP implementation and CLI adapter |
| `out/`, `build_*/` | Isolated generated binaries and build trees |

## Native MCP tools

Query MCP `tools/list` for current names and input schemas; do not hardcode the
native registry count or assume parity with the script adapter. Engine-level
commands/features come from `--capabilities`, while `server_status` reports the
live server's registry and counters.

| Tools | Purpose |
| --- | --- |
| `ast_outline` | Tree-sitter structure and spans; requires the x64 grammar DLL |
| `source_outline`, `workspace_symbols` | Lightweight source/symbol scans |
| `get_source_context` | Source lines around a location |
| `check`, `run`, `test` | Child-engine execution with diagnostics and captured streams |
| `server_status` | Engine identity, health, and counters |

Native execution tools default to a 30-second timeout (`timeout_ms`: 1–600000)
and an 8 MiB combined raw-output capture limit. Hitting the capture limit
terminates the job and returns `ok:false`, `outputLimitExceeded:true`, and
`captureLimitBytes:8388608`. Inspect `timedOut` separately.

No `#Include McpClient.ahk` is required to run the native server. That file is a
client helper only for an AHK script which wants to call another MCP process.

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
- Backslashes are literal in AHK strings; use ordinary Windows paths. The escape character is the backtick.
- **Always use parentheses on every function call**: `Print("text")` not `Print "text"`, `MsgBox("hi")` not `MsgBox "hi"`, `Eval(expr)` not `Eval expr`. Applies to ALL functions — built-ins, BIFs, user-defined, fork additions. No command-style calls.
- **Backticks are escape characters inside double-quoted strings.** `"`a"` is alert/bell, not a literal backtick. To quote code/identifiers inside Print strings, use single quotes: `Print("'i32' is removed")`. Backticks in `;` comments and `/* */` blocks are fine.

## Fork-only BIFs (always available)

These do not exist in upstream AutoHotkey. Use them directly — no `#include`, no helpers.

- **`Print(Fmt?, Values*)`** — stdout println with built-in `Format` dispatch.
  - `Print()` → blank line
  - `Print("plain text")` → write as-is (single-arg form never goes through Format, so literal `{ }` survive)
  - `Print("x={}, y={}", x, y)` → calls `Format(Fmt, Values*)` then writes
  - **Don't write `Print(Format("...", x))`** — pass the args directly to `Print` instead.
  - Writes to an attached console or redirected stdout when available.
- **`Eval(Expression)`** — runtime expression eval. Gated by `#EnableEval` directive or `/Eval` CLI flag. Throws `SyntaxError` on parse failure and a catchable `ValueError` above 16,384 UTF-16 code units. The REPL uses the same limit and continues after an oversized expression. Compiled Eval storage still has process lifetime to preserve closures. See `updates.md` section 1.
- **`SyntaxError`** — exception class for parse errors. Has `Message`, `What`, `Extra`, `Line`, `Column`.
- **`Check(Source)`** — validate AHK source with automatic oracle parity: spawns this exe in check mode (`/Diag=json /Check`) against a temp file in a child process, so host state is untouched and the verdict matches the CLI. Returns `{ Ok, Diagnostics, Raw }`: `Ok` is 1/0 (child exit 0 = valid, 13 = syntax error); `Diagnostics` is an Array (empty when Ok=1) of `{ Severity, Type, Code, Message, Extra, File, Line, Column }`; `Raw` is the captured child output. Its shared child runner has a 30-second timeout and 8 MiB combined output budget; spawn, timeout, or output-limit failure returns Ok=0 with a synthetic diagnostic. `Raw` combines stderr then stdout, preserving each stream's order without promising cross-stream chronology. Temporary-file and process-tree cleanup are automatic. The check-mode child skips ordinary script execution, but load-time directives such as `#DllLoad` can still have side effects; it is not a sandbox. This — not `TSParse(...).HasError` — is the correct 'does it parse?' check.
- **`JSON`** — native JSON class, no include. `JSON.Parse(Text, Reviver?, Options?)`
  and `JSON.Stringify(Value, Replacer?, Space?, Options?)`, aliased `Load`/`Dump`;
  `JSON.ParseAt(Text, &Pos, Options?)` parses one value from `Pos` and advances it
  (loop `while (pos <= StrLen(text))`) for NDJSON / JSON Lines / concatenated
  streams — the wire shape of newline-delimited JSON-RPC and streamed feeds.
  `Space` takes an indent width or a literal string. Objects parse into an ordered,
  case-sensitive `JSON.Object` (Map-like API plus `.Keys`/`.Values` in document
  order), preserving property order and key case; serialization can change whitespace and number formatting.
  `true`/`false`/`null` reach script as `1`/`0`/`""` — the container remembers what
  they were, so they re-emit as keywords. Arrays parse to `JSON.Array` (derives
  from `Array`, so `is Array` and every Array method still work) and carry the
  same tags; changing an array's length drops its tags rather than risk
  mislabelling a value. Options: `Container` ("JSON.Object"|"Map"),
  `Booleans`/`Null` ("integer"/"empty"|"native" for `JSON.True/False/Null`
  singletons, which round-trip inside arrays too), `MaxDepth`, `AllowComments`,
  `AllowTrailingCommas`, `EnsureAscii`, `EscapeSlash`. Plain object literals
  (`{a: 1}`) serialize via their own value properties — dynamic properties are
  skipped, since producing one means invoking script. Errors are `JSONError`
  (a `ValueError` subclass) carrying line/col/pos and a `[Code]`; depth and
  circular references are catchable. Conformance: nst/JSONTestSuite 95/95 y_
  and 188/188 n_ (`qa/tests/test_jsonsuite.ahk`).
- **`Inspect(Value, Depth := 2, MaxItems := 100)`** — JSON description of a live value: `type`, own `properties`, names of `getters`/`setters`/`methods` (never invoked), `items`/`entries`, `truncated`/`circular` flags. The REPL prints object results with it. `updates.md` §18.
- **`ProcessPipe(Command, Args?, WorkingDir?)`** — child process with UTF-8 stdio pipes in a job object: `Send(text, timeout?)`/`SendLine`, `ReadLine(timeout)`/`Read`/`ReadStdErr`, `Wait`, `Close`, `Kill`, `PID`/`Running`/`ExitCode`/`AtEOF`. Releasing the object kills the tree. `updates.md` §19.
- **`TSParse(Source)`** — parse AHK source with the bundled tree-sitter grammar; returns a snapshot tree of plain AHK objects. Lazily loads `bin/tree-sitter-ahk.dll` on first call. Returns `{ Root, Source, HasError }`; each node has `Type`, `StartByte`/`EndByte`, `StartRow`/`StartCol`/`EndRow`/`EndCol`, `Text`, `IsNamed`/`IsMissing`/`IsError`/`IsExtra`/`HasError`, `FieldName`, `Children`, `NamedChildren`, `Truncated`. For **structure only** — the grammar is incomplete (false `HasError` on valid code, e.g. typed Structs, fat-arrow methods, `^j::` hotkeys); do not use `TSParse(...).HasError` as a validity check. For 'does it parse?' use the `Check` BIF above (real-engine oracle), or the `check` CLI subcommand. Full docs: `docs/TREE_SITTER.md`.

Full reference: `updates.md` in the repo root.

## Design Documents

- `docs/plans/2026-01-11-interactive-llm-debugger-design.md` - Historical debugger integration design

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

# Current State & Open Items (updated 2026-09-19)

- Target language version: `2.1-alpha.31+Console`, based on upstream
  `v2.1-alpha.31`. Always verify the actual executable's `--version` and hash;
  historical files in `bin/` or `bin_harness/` may be stale.
- CMake builds GUI and Console by default, sharing the common runtime objects.
  Harness is an explicit optional target. CI gates Console for MSVC x64,
  MSVC Win32, and mingw x64, then publishes tag releases and checksums.
- `qa/` is the subprocess regression suite; `tests/run_console_gate.py ENGINE`
  is the aggregate boundary. Use an explicit engine path from `BUILD.md`.
- `WORKLOG.md` tracks verification results and outstanding language/docs work.
  Build and test locally when requested; remote publishing is a separate action.

Open items:
- [x] Stale Struct type-string examples (`i32`/`u32`/`u8`/`uptr` → `Int32`/
  `UInt32`/`UInt8`/`IntPtr`) fixed 2026-09-10 across 14 example files; no
  `UInt64`/`UIntPtr` class exists, so `u64`/`uptr` became `Int64`/`IntPtr`.
  `examples/struct_at_showcase.ahk` also had its clobbered `POINT` definition
  restored. Every file under `examples/` passes `check` on the alpha.31 harness.
- [x] Stale `export` module examples fixed 2026-09-10: keyword dropped, and the
  `#Import {X} from M` / bare `#Import "file.ahk"` forms (never valid on this
  engine) rewritten as `#Import M {X}` / `#Import "file.ahk" {*}`.
- [ ] **Module init is not lazy on alpha.31**: a `#Module` nothing imports still
  runs, before `__Main`'s auto-execute section (`examples/alpha21/05_lazy_module_init.ahk`
  documents the observation). alpha.21 notes promised first-reference init —
  decide whether this is an upstream change or a fork regression, then pin it.
- [ ] `/Headless` does **not** suppress `MsgBox` — a headless run of any
  MsgBox-driven example blocks on a real dialog. Verify such scripts via a
  scratch copy with `MsgBox` → `Print`, or extend `/Headless`.
- [ ] Faster tree-sitter path: build `tree-sitter-ahk.wasm` + `web-tree-sitter`
  for in-process, incremental parsing in a Node host. Needs the grammar
  **source** — only the `.dll` is vendored.
- [ ] `FileRead` on a zero-byte file returns **no value** on this alpha
  (see WORKLOG 2026-08-26) — pin intended behavior with a qa test.
