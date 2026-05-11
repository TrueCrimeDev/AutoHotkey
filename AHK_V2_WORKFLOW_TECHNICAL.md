# AutoHotkey v2 Workflow and Technical Notes (This Repo)

This document explains how this repository's AutoHotkey v2 build works in practice, and which source-level changes drive the behavior.

## Scope

This repo is not just stock AHK v2 source. It includes:

- A custom engine build tag: `2.1-alpha.26+Console` (`source/ahkversion.h`)
- Runtime console/error behavior around `/ErrorStdOut` (`source/error.cpp`, `source/AutoHotkey.cpp`)
- A built-in `_ScriptGetLines()` helper (`source/error.cpp`, `source/lib/functions.h`)

## High-Level Workflows

### 1. Build the engine

Use Visual Studio/MSBuild as documented in `BUILD.md`.

Typical output:

- `bin/AutoHotkey64.exe` (Release x64)

### 2. Run scripts normally

```powershell
bin\AutoHotkey64.exe your_script.ahk
```

This follows standard GUI/runtime behavior unless you pass debug/error flags.

### 3. Run in console/headless error mode

```powershell
bin\AutoHotkey64.exe /ErrorStdOut your_script.ahk
```

In this fork, runtime errors can be printed to stderr instead of modal dialogs (details below).

Test file in repo:

- `test_errorstdout.ahk`

### 4. Run in debugger mode (DBGp)

```powershell
bin\AutoHotkey64.exe /Debug your_script.ahk
```

AHK acts as the DBGp client and connects to a listening debugger server (default `localhost:9000`), such as:

- `debugger-tool/mcp-server`
- `debugger-tool/examples/simple_client.py`

### 5. Run console output tests

`FileAppend` with stream pseudo-files:

- `"*"` for stdout
- `"**"` for stderr

Example in repo:

- `test_console.ahk`

## End-to-End Data Flow

### Console/Error path

1. CLI flag parsed (`/ErrorStdOut`) in `source/AutoHotkey.cpp`.
2. Script errors route through `Script::ShowError(...)` in `source/error.cpp`.
3. If `mErrorStdOut` is enabled, formatted output is written to `"**"` (stderr).
4. Process exits with non-zero code for failures.

### Debugger path

1. `/Debug` parsed in `source/AutoHotkey.cpp` and target host/port stored.
2. After load, debugger connection is established and DBGp session begins.
3. Script execution hooks trigger debugger events:
   - line execution (`PreExecLine`)
   - function stack push/pop
   - exception throw (`PreThrow`)
4. External client (MCP/Python/C++) sends DBGp commands (`run`, `step_into`, `breakpoint_set`, etc.).
5. AHK returns XML responses (length-prefixed, null-terminated packets).

## Technical Details by Feature

## 1) Version identity

`source/ahkversion.h` defines:

- `RAW_AHK_VERSION "2.1-alpha.26+Console"`

The `+Console` metadata signals this fork includes console-oriented behavior.

## 2) `/ErrorStdOut` behavior in this fork

### Parsing and setup

- `source/AutoHotkey.cpp`
  - Parses `/ErrorStdOut`, optional `=encoding`, and `:color`
  - Calls `Script::SetErrorStdOut(...)`

- `source/error.cpp`
  - `Script::SetErrorStdOut(...)` stores encoding mode and optional ANSI color handling.

### Runtime error output path

Core path:

- `Script::ShowError(...)` checks `mErrorStdOut`
- Formats message with `FormatStdErr(...)`
- Writes to `"**"` (stderr) via `PrintErrorStdOut(...)`
- Sets pending exit code and exits app for non-warning errors

Important compatibility note in source:

- `PrintErrorStdOut` name is historical; output is stderr for compatibility.

## 3) stdout/stderr stream plumbing

`source/TextIO.cpp` allows pseudo-files:

- `"*"` -> stdout
- `"**"` -> stderr
- `"*"` in read mode -> stdin

This is why AHK scripts can do:

```autohotkey
FileAppend("hello`n", "*")   ; stdout
FileAppend("oops`n", "**")   ; stderr
```

Used directly in:

- `test_console.ahk`
- `debugger-tool/ahk-error-agent/include/cloudahk-error-handler.ahk`

## 4) DBGp stream redirection (`stdout`/`stderr` commands)

`source/Debugger.cpp` registers DBGp commands:

- `stdout`
- `stderr`

with handler methods:

- `redirect_stdout`
- `redirect_stderr`

Modes are defined in `source/Debugger.h`:

- `SR_Disabled` (0)
- `SR_Copy` (1)
- `SR_Redirect` (2)

When enabled, stream packets are emitted as DBGp `<stream type="...">` XML with base64 payload (`WriteStreamPacket`).

Implication:

- Console output can be mirrored or redirected to debugger clients over DBGp, not just local console handles.

## 5) Script execution interception points

Core debug hooks in source:

- Line execution: `g_Debugger.PreExecLine(...)` (`source/script.cpp`)
- Function stack tracking: `DEBUGGER_STACK_PUSH(...)` (`source/script_expression.cpp`, others)
- Exception interception: `g_Debugger.PreThrow(...)` (`source/error.cpp`)

This is the basis for stepping, stack traces, breakpoints, and exception handling in the MCP server and example clients.

## 6) `_ScriptGetLines()` built-in

Function registration:

- `source/lib/functions.h`

Implementation:

- `source/error.cpp` (`bif_impl FResult _ScriptGetLines(...)`)

Behavior:

- Resolves a script line by file + line number
- Returns an array of objects with:
  - `File`
  - `Number`
  - `Text`
- Optional range expands around the target line

This is used for higher quality error context and is a key capability for AI-assisted fixing workflows.

## Repo Tooling and How It Fits

### `debugger-tool/mcp-server`

- Bridges AI tools to AHK DBGp over stdio MCP
- Primary loop: debugger controls, breakpoints, stack/vars, evaluate

### `debugger-tool/ahk-error-agent`

- Headless error capture workflow built on debugger/events
- Includes optional `OnError` handler injection scripts:
  - `cloudahk-error-handler.ahk`
  - `cloudahk-error-handler-enhanced.ahk`

### VS Code tasks

Workspace tasks are defined in `.vscode/tasks.json`, including:

- Run with debug interceptor
- Run normally
- Start global debug server

Those tasks reference `AutoDebug.ahk` and `GlobalDebugServer.ahk`; ensure those scripts exist in your local workspace if you use those tasks.

## Common Commands

```powershell
# Build
msbuild AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64

# Normal run
bin\AutoHotkey64.exe script.ahk

# Console/headless error mode
bin\AutoHotkey64.exe /ErrorStdOut script.ahk

# Debug mode (default localhost:9000)
bin\AutoHotkey64.exe /Debug script.ahk

# Debug mode with explicit endpoint
bin\AutoHotkey64.exe /Debug=127.0.0.1:9000 script.ahk
```

## Known Caveats

- Some docs under `debugger-tool/` describe stock AHK behavior where `/ErrorStdOut` only catches load-time errors. This fork changes runtime behavior in `source/error.cpp`.
- DBGp stream packets (`<stream>`) are separate from normal `<response>` packets; tools need explicit handling if they want live stdout/stderr over debugger transport.
- `/Debug` requires the debugger server to be listening first, otherwise connect will fail.

## Quick Mental Model

Use this fork in two complementary modes:

- Console mode: reliable stderr/stdout behavior for automation and CI-like runs.
- DBGp mode: rich introspection (stack/vars/source context) for IDE and AI debugging workflows.

Together, they support scripted, headless, and LLM-assisted debugging without depending on GUI error dialogs.
