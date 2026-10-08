# AutoHotkey v2 Workflow and Technical Notes (This Repo)

This document explains how this repository's AutoHotkey v2 build works in practice, and which source-level changes drive the behavior.

## Scope

This repo is not just stock AHK v2 source. It includes:

- A custom engine build tag: `2.1-alpha.33+Console` (`source/ahkversion.h`)
- A console executable, `AutoHotkey64Console.exe`, built from the same source as the GUI `AutoHotkey64.exe` (`AHK_CONSOLE_ENTRYPOINT` in `source/AutoHotkey.cpp`)
- Runtime console/error behavior around `/ErrorStdOut` (`source/error.cpp`, `source/AutoHotkey.cpp`)
- A built-in `_ScriptGetLines()` helper (`source/error.cpp`, `source/lib/functions.h`)

## High-Level Workflows

### 1. Build the engine

Build with CMake as documented in `BUILD.md` (MSVC x64, MSVC Win32, or mingw-w64 GCC x64; CI builds, syntax-checks and gates all three configurations).

Typical output:

- `out/msvc/x64/AutoHotkey64Console.exe` (console engine) and `out/msvc/x64/AutoHotkey64.exe` (GUI), Release x64, with BUILD.md's isolated `AHK_OUTPUT_DIR`
- `AutoHotkey32Console.exe` and `AutoHotkey32.exe` from the MSVC Win32 route
- `bin/` instead when `AHK_OUTPUT_DIR` keeps its default, as `build.bat` (the mingw-w64 convenience route) does

The commands below use `bin\AutoHotkey64Console.exe`, the engine `.mcp.json` and the Claude Code hooks use; substitute the path of the build you are testing.

### 2. Run scripts normally

```powershell
bin\AutoHotkey64Console.exe your_script.ahk
```

The console engine keeps the terminal attached, so the shell waits for the script and receives its exit code, and it reports load and runtime errors on stderr. The GUI `bin\AutoHotkey64.exe` follows standard GUI/runtime behavior (error dialogs) unless you pass debug/error flags, and PowerShell does not wait for it unless its output is piped.

### 3. Run in console/headless error mode

```powershell
bin\AutoHotkey64Console.exe /Headless your_script.ahk
bin\AutoHotkey64Console.exe /Headless /Diag=json your_script.ahk   # one JSON diagnostic per line on stderr
```

In this fork, runtime errors can be printed to stderr instead of modal dialogs (details below). The console engine does this by default; `/ErrorStdOut[=encoding][:color]` selects the text encoding and color, and turns the routing on for the GUI engine. `/Headless` also reports the engine's own error and instance prompts on stderr, but a script's own `MsgBox`, `InputBox` and `Gui` still show and block. From Git Bash, which rewrites arguments that start with `/`, use `--headless`, `--diag=json` and `//ErrorStdOut`.

Test files in repo:

- `tests/test_errorstdout.ahk` (shows a `MsgBox` before its error, so not for unattended runs)
- `tests/test_console.ahk` (dialog-free: stdout lines, then an uncaught error on stderr and exit code 10)

### 4. Run in debugger mode (DBGp)

```powershell
bin\AutoHotkey64Console.exe /Debug your_script.ahk
```

AHK acts as the DBGp client and connects to a listening debugger server (default `localhost:9000`; `/Debug=host:port` for another endpoint, `/Debug=stdio` for DBGp over stdin/stdout; `//Debug` from Git Bash), such as:

- `debugger-tool/mcp-server`
- `debugger-tool/examples/simple_client.py`

### 5. Run console output tests

`FileAppend` with stream pseudo-files:

- `"*"` for stdout
- `"**"` for stderr

Example in repo:

- `tests/test_console.ahk`

### 6. Launch under MCP supervision (legacy stdio adapter)

For this repo, run scripts with the native server's `mcp__ahk-mcp__run` and
`mcp__ahk-mcp__test` (the `ahk-mcp` entry in `.mcp.json`). Those tools have no
debugger. The stdio debugger launch below exists only in the legacy
`debugger-tool/mcp-server` adapter, which `.mcp.json` does not register (see
`debugger-tool/mcp-server/CLAUDE.md`):

- Its `launch_script` tool runs `bin\AutoHotkey64.exe /Debug=stdio script.ahk` (the GUI
  build by default; `AHK_EXE` overrides it) as a child process, so no port 9000
  listener is involved.
- DBGp frames travel over the child's stdin/stdout; script `Print()`/stdout output is
  redirected into DBGp `<stream>` packets (`stdout -c 2`) and read via `get_script_output`.
- The script starts paused before auto-execute; `debug_run` begins execution.
- An exception breakpoint is set by default, so uncaught errors break for inspection
  (stack and variables) instead of killing the process. The engine has no DBGp `eval`
  command (it answers error 4), so the adapter's `evaluate` tool fails; read values with
  `variables_get` or `property_get`.

### 7. Run generated code from stdin (no temp file)

The engine accepts `*` as the script name and reads source from stdin. Use the console
build, which the shell waits for:

```powershell
'Print("hi")' | & .\bin\AutoHotkey64Console.exe *
'Print("hi")' | & .\bin\AutoHotkey64Console.exe check *
```

```bash
# Git Bash: quote * so the shell does not expand it to file names
echo 'Print("hi")' | ./bin/AutoHotkey64Console.exe '*'
echo 'Print("hi")' | ./bin/AutoHotkey64Console.exe check '*'
```

Useful for validating or running harness-generated snippets without touching disk.
`check` validates a snippet without running it; its diagnostics name the file `*`.
`/ErrorStdOut` is not needed on the console build (in Git Bash, write `//ErrorStdOut`).

### 8. Interrupt a running script: break → inspect → run

DBGp advertises `supports_async=1`, so a busy script can be interrupted at any time:

1. Send `break` (legacy adapter: `debug_command` with `break`) — script pauses wherever it is.
2. Inspect or mutate: `property_get`, `context_get` (adapter: `variables_get`), `property_set`.
   There is no DBGp `eval`.
3. Send `run` to resume.

This is the supported "REPL into a running process" pattern; it works even when the
script's own message loop is busy (unlike any in-script listener approach).

### 9. NDJSON event stream convention

For machine-readable script telemetry, emit one JSON object per line on stdout using
single-argument `Print()` (single-arg form never passes through Format, so literal
braces survive):

```autohotkey
Print('{"event":"start","detail":"loading config"}')
Print('{"event":"progress","step":3,"total":10}')
```

A supervising harness reads these from `get_script_output` (stdio launch) or the
process stdout (plain console run) and parses each line independently. Errors arrive
on the same model via `/Diag=json` on stderr.

## End-to-End Data Flow

### Console/Error path

1. CLI flag parsed (`/ErrorStdOut`) in `source/AutoHotkey.cpp`; the console entrypoint enables it before parsing, so `AutoHotkey64Console.exe` needs no flag.
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

- `RAW_AHK_VERSION "2.1-alpha.33+Console"`

The `+Console` metadata signals this fork includes console-oriented behavior. `--version` prints this string plus the build's source revision (CMake's `AHK_BUILD_REVISION`, with `-dirty` for uncommitted changes), compiler and architecture.

## 2) `/ErrorStdOut` behavior in this fork

### Parsing and setup

- `source/AutoHotkey.cpp`
  - Parses `/ErrorStdOut`, optional `=encoding`, and `:color`
  - Calls `Script::SetErrorStdOut(...)`
  - Under `AHK_CONSOLE_ENTRYPOINT`, calls `g_script.SetErrorStdOut(nullptr)` at startup, so the console engine reports errors on stderr by default

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

- `tests/test_console.ahk`
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

- Bridges AI tools to AHK DBGp over stdio MCP (a legacy TypeScript adapter; the engine's own MCP server is `AutoHotkey64Console.exe mcp`, `source/mcp_server.cpp`, which has no DBGp tool)
- Primary loop: debugger controls, breakpoints, stack/vars, evaluate

### `debugger-tool/ahk-error-agent`

- Headless error capture workflow built on debugger/events
- Includes optional `OnError` handler injection scripts:
  - `cloudahk-error-handler.ahk`
  - `cloudahk-error-handler-enhanced.ahk`

### VS Code tasks

Workspace tasks are defined in `.vscode/tasks.json` and use the fork's console
engine, `bin\AutoHotkey64Console.exe` (build it first; the `bin\*.exe` engines
are gitignored):

- `Run AHK (fork, color)`, `Check AHK (fork)` and `Test AHK (fork)` for the active file
- `QA suite (fork)` (`qa/run.ahk`, the default test task) and `Console gate (choose engine)` (`tests/run_console_gate.py`)
- CMake MSVC build tasks (`out/msvc/x64`, the default build task; `out/msvc/x64_debug`; `out/msvc/Win32`), `build.bat` (mingw, overwrites `bin\`), and the legacy msbuild `.sln` tasks (GUI only)

The repository ships no keybindings; VS Code reads shortcuts only from the
user's own `keybindings.json`. See [VSCODE_SETUP.md](VSCODE_SETUP.md) for the
full task list, the launch configurations, the recommended extensions
(`.vscode/extensions.json`) and an optional user keybinding example.

## Common Commands

```powershell
# Build (x64 developer prompt; see BUILD.md for prerequisites, Win32 and mingw-w64)
cmake -S . -B build_msvc_x64 -G Ninja -DCMAKE_BUILD_TYPE=Release -DAHK_OUTPUT_DIR=out/msvc/x64
cmake --build build_msvc_x64 --target AutoHotkey64Console AutoHotkey64 --parallel 6

# Normal run (errors on stderr)
bin\AutoHotkey64Console.exe script.ahk

# Syntax check: exit 0, or 13 for a syntax error or a missing script file
bin\AutoHotkey64Console.exe check /Diag=json script.ahk
# Single-script test: exit 0 on pass, 10 for an uncaught error, 12 for a parse
# error, 14 for ExitApp(14), a persistent script or an execution failure
# (--capabilities lists the codes under exitCodes)
bin\AutoHotkey64Console.exe test script.ahk

# Console/headless error mode
bin\AutoHotkey64Console.exe /Headless /Diag=json script.ahk

# Debug mode (default localhost:9000)
bin\AutoHotkey64Console.exe /Debug script.ahk

# Debug mode with explicit endpoint
bin\AutoHotkey64Console.exe /Debug=127.0.0.1:9000 script.ahk
```

From Git Bash, write `--headless`, `--diag=json`, `//Debug` and `//Debug=127.0.0.1:9000` instead of the `/` forms; Git Bash rewrites an argument that starts with a single `/` into a path.

## Known Caveats

- Some docs under `debugger-tool/` describe stock AHK behavior where `/ErrorStdOut` only catches load-time errors. This fork changes runtime behavior in `source/error.cpp`.
- DBGp stream packets (`<stream>`) are separate from normal `<response>` packets; tools need explicit handling if they want live stdout/stderr over debugger transport.
- `/Debug` requires the debugger server to be listening first, otherwise connect will fail. The script then runs without the debugger and prints `Debugger error: Could not connect to localhost:PORT; continuing without the debugger.` on stderr (a lost connection prints `Connection to localhost:PORT lost; ...`; under `/Diag=json` either is one warning record with `what` "Debugger"). Engines before `f14d7427` showed a modal prompt instead, even with `/Headless`.
- `/Headless` covers the engine's own prompts only; a script that calls `MsgBox`, `InputBox` or `Gui` still blocks on a real window.

## Quick Mental Model

Use this fork in two complementary modes:

- Console mode: reliable stderr/stdout behavior for automation and CI-like runs.
- DBGp mode: rich introspection (stack/vars/source context) for IDE and AI debugging workflows.

Together, they support scripted, headless, and LLM-assisted debugging without depending on GUI error dialogs.
