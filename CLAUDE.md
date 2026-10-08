# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A native AutoHotkey `2.1-alpha.33+Console` fork. The engine supplies shell
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
  smaller tool surface. `debugger-tool/mcp-server/` and
  `debugger-tool/ahk-error-agent/` are TypeScript DBGp clients/adapters; they
  are not the native server.
- CMake shares engine objects across GUI, Console, and optional Harness targets.
  Read `BUILD.md` for supported compiler routes and exact-artifact verification.

Do not infer the installed engine version or user-wide MCP registration from
this document. The checked-in `.mcp.json` starts `./bin/AutoHotkey64Console.exe mcp`,
a path relative to the project root. Inspect the active host's configuration
before changing it.

## Claude Code setup

- Start `claude` at the repository root; `.mcp.json` and `.claude/settings.json`
  resolve from there.
- `bin/*.exe` is gitignored, so a fresh clone has no engine: the project MCP
  server cannot start and the post-edit syntax gate is off. Build per `BUILD.md`
  (CMake's default `AHK_OUTPUT_DIR` is `bin`) or copy a release console engine
  into `bin/`. An engine anywhere else needs the x64 `tree-sitter-ahk.dll` beside
  it for `ast_outline` and `TSParse`; CMake does not copy it.
- `ahk-mcp` (project, `.mcp.json`) is the engine's native `mcp` verb. Use
  `mcp__ahk-mcp__check`, `run` and `test` for this repo's scripts; they run the
  fork engine. If `tools/list` lacks `check`, `run` and `test`, the server is
  running an older engine: it was started from an earlier `.mcp.json` (which
  launched the GUI `bin/AutoHotkey64.exe`, then older than the console build),
  or `bin/` holds a pre-a551fcd4 build. A server started before `bin/` was
  rebuilt keeps the engine it loaded: its `server_status` `ahkVersion` says
  which (on 2026-10-08 a session server still reported `2.1-alpha.31+Console`
  after `bin/` became alpha.33). Reconnect it (`/mcp`) and compare `--version`;
  rebuild only if `bin/AutoHotkey64Console.exe` itself lacks them.
- `ahk` (user-wide, if connected) is a separate Node server. Its `AHK_Check`,
  `AHK_Run` and `AHK_Eval` use the engine its `AHK_PATH` names, normally stock
  AutoHotkey, which rejects fork directives such as `#EnableEval` and lacks the
  fork BIFs; `AHK_Eval` and the `uia_*` inspector need the fork. Only its `core`
  toolset is listed. `debug` (`AHK_Debug_DBGp`), `uia` (used by the `uia` skill),
  `library`, `extras` and `legacy` stay hidden until
  `AHK_Settings {"action":"enable_toolset","toolset":"debug"}`, which persists
  machine-wide in `%APPDATA%\ahk-mcp\tool-settings.json`. Enable a toolset, or
  change that server's registration, only when the user asks. Its
  `AHK_Debug_DBGp` `capture_error` captures, and its `evaluate` works, only on
  a server with the ahk-mcp capture fix (not on ahk-mcp `master`), restarted
  since; see [DBGp Protocol](#dbgp-protocol).
- Hooks are registered in the committed `.claude/settings.json` and run as
  `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<name>.sh"`; they need Git for Windows
  bash, not python or jq. Engine: `AHK_CUSTOM_EXE` if set (only that), else
  `bin/AutoHotkey64Console.exe`, else `bin/AutoHotkey64.exe`. An exe without the
  fork's marker text (stock AutoHotkey) is refused wherever it lives. Test them with `bash .claude/hooks/test-hooks.sh`; see
  `.claude/hooks/README.md`.
  - SessionStart, `ahk-debug-context.sh`: reports the detected engine and the
    tooling map.
  - PostToolUse on Edit/Write/MultiEdit/`AHK_File_Edit`/`AHK_File_Create`,
    `ahk-post-edit.sh`: runs the fork `check` on an edited `.ahk` file inside
    the repo. A syntax error (engine exit 12/13) is fed back to you as hook
    feedback (hook exit 2): fix it and re-check. Warnings pass. The
    `test_crashlog_parse*.ahk` and `test_parse_error*.ahk` fixtures are skipped.
  - PreToolUse, PostToolUse and PostToolUseFailure on `mcp__ahk__AHK_Debug_DBGp`,
    `check-ahk-connection.sh` and `post-capture-guidance.sh`: add DBGp workflow
    guidance. They fire only while the `debug` toolset is enabled.
- Per-user overrides belong in `.claude/settings.local.json` and
  `CLAUDE.local.md`; both are gitignored.
- The Bash tool is Git Bash, which rewrites any argument that starts with `/`
  into a path: `check /Diag=json f.ahk` checks `C:\Program Files\Git\Diag=json`
  and exits 13 ("Script file not found."), the same code as a syntax error. Use
  the aliases `--diag=json`, `--headless`, `--coverage=`, `--trace`, `--eval`,
  `--crashlog=` and `--stderrfile=`, or double the slash for switches without
  one (`//Debug`, `//include`, `//ErrorStdOut`). PowerShell passes `/Flag`
  unchanged. Use `python`, not `python3`, which may be the Microsoft Store stub.

## Running and testing

Use the exact fresh engine path. An isolated build need not replace `bin/` or
modify an installed alias. `bin/AutoHotkey64Console.exe` is what `.mcp.json` and
the hooks use; check its `--version`, because `bin/` may be stale or `-dirty`.
Use the Console exe: PowerShell does not wait for the GUI `AutoHotkey64.exe`
unless it is piped, so `$LASTEXITCODE` is lost.

```powershell
$engine = (Get-Item out/msvc/x64/AutoHotkey64Console.exe, bin/AutoHotkey64Console.exe -ErrorAction Ignore | Select-Object -First 1).FullName
& $engine --version
& $engine --capabilities
& $engine run ScriptName.ahk
& $engine check --diag=json ScriptName.ahk
& $engine test tests/run.ahk
New-Item -ItemType Directory -Force coverage | Out-Null   # --coverage writes nothing into a missing directory
& $engine --coverage=coverage/tests.lcov test tests/run.ahk
& $engine mcp
python tests/run_console_gate.py $engine
python tools/check_all.py $engine
. ./tools/ahk.ps1 -EnginePath $engine
```

From Git Bash (the Bash tool):

```bash
engine=out/msvc/x64/AutoHotkey64Console.exe; [ -f "$engine" ] || engine=./bin/AutoHotkey64Console.exe
"$engine" check --diag=json ScriptName.ahk
"$engine" test tests/run.ahk
mkdir -p coverage && "$engine" --coverage=coverage/tests.lcov test tests/run.ahk
python tests/run_console_gate.py "$engine"
```

`check` and `test` already run headless. `check` prints `CHECK PASS` (or
`{"kind":"check","status":"pass"}` with `--diag=json`) on stdout and returns 0;
it returns 13 for a syntax failure and also when the script file is missing
(`Script file not found.`, line 0), so read the diagnostic before calling it a
syntax error. `run` returns 12 for parse errors and 10 for uncaught runtime
errors. `test` returns 0 on pass and 14 only for an explicit `ExitApp(14)`, a
persistent script, or an execution failure; an uncaught error inside a test
still returns 10. Diagnostics go to stderr (one flat JSON object per line with
`--diag=json`), but `#Warn ..., StdOut` sends warnings to stdout, so read both
streams. `/ErrorStdOut` only selects encoding and color here; it does not move
diagnostics to stdout. Read `--capabilities` for the complete exit-code
contract. `/Headless` only routes error and warning dialogs to stderr; `MsgBox`,
`InputBox` and `Gui` still block, so do not run dialog-driven scripts
unattended. `/Headless` and `check` are not sandboxes: loading can perform
operations such as `#DllLoad`. Do not execute arbitrary untrusted scripts
merely to validate them.

`launch_script` (spawns `bin/AutoHotkey64.exe /Debug=stdio`, no port 9000)
exists only in the legacy `debugger-tool/mcp-server` adapter, which `.mcp.json`
does not register (see `debugger-tool/mcp-server/CLAUDE.md`); here use
`mcp__ahk-mcp__run` and `test`. A generated snippet can run from stdin with `*`
as the script name: PowerShell `'Print("hi")' | & $engine *`; Git Bash
`echo 'Print("hi")' | "$engine" '*'` (quote `*`, which Bash otherwise expands
to file names). `check '*'` validates a snippet the same way, and its
diagnostics name the file `*`. The Console exe needs no `/ErrorStdOut` for this.

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
| `.claude/` | Claude Code hooks, the `uia` skill, and shared settings |

## Native MCP tools

Query MCP `tools/list` for current names and input schemas; do not hardcode the
native registry count or assume parity with the script adapter. Engine-level
commands/features come from `--capabilities`, while `server_status` reports the
live server's registry and counters.

| Tools | Purpose |
| --- | --- |
| `ast_outline` | Tree-sitter structure and spans; needs the x64 `tree-sitter-ahk.dll` beside the engine |
| `source_outline`, `workspace_symbols` | Lightweight line-regex scans (`source/mcp_server.cpp:930`): they miss functions whose default parameters contain parentheses and every fat-arrow (`=>`) function, so use `ast_outline` for a complete list |
| `get_source_context` | Source lines around a location |
| `check`, `run`, `test` | Child-engine execution with diagnostics and captured streams |
| `server_status` | Engine identity, health, and counters |

Native execution tools default to a 30-second timeout (`timeout_ms`: 1–600000)
and an 8 MiB combined raw-output capture limit. Hitting the capture limit
terminates the job and returns `ok:false`, `outputLimitExceeded:true`, and
`captureLimitBytes:8388608`. Inspect `timedOut` separately. When
`MCP_TOOL_TIMEOUT` is set (check the user's settings `env`), Claude Code
abandons an MCP call after that many milliseconds while the child keeps
running to its own `timeout_ms`; keep `timeout_ms` below that limit.

No `#Include McpClient.ahk` is required to run the native server. That file is a
client helper only for an AHK script which wants to call another MCP process.

## _ScriptGetLines

This fork includes `_ScriptGetLines(Filename, LineNumber, Range := 0)` for source context:

```autohotkey
lines := (_ScriptGetLines(A_LineFile, A_LineNumber, 3) ?? "") || []  ; up to 3 parsed lines before/after
for line in lines {
    Print("{:03}: {}", line.Number, line.Text)
}
```

It returns an Array of `{File, Number, Text}` objects, one per parsed line;
comments and blank lines are skipped. `Text` is the engine's rendering of the
parsed line, not the raw source: trailing comments are dropped, and
`for line in lines {` comes back as `For line in lines` plus a separate `{`
entry with the same `Number`. Those brace entries count toward `Range`. A
negative or omitted range returns just the given line. A line number with no
code (blank, comment-only or past the end) returns no Array, and what you get
depends on the calling module's compatibility mode: by default (v2.0 mode) an
empty string, which `for` rejects with `TypeError`; under a
`#Requires AutoHotkey v2.1-...` at the top level of the module's own file (the
main script, or the file that declares the `#Module`) no value, so even a plain
assignment throws `UnsetError`. Since upstream `47eabd41`/`08beacf1` a
`#Requires` in an `#Include`d file or inside a function no longer sets the
mode (so `tests/Test.ahk`'s line-1 `#Requires` is inert when included).
Neither `?? []` nor `|| []` alone covers both modes; guard with
`(... ?? "") || []` as above. Merged from lexikos' `linecontext` branch.

## CloudAHK Error Handlers

The handlers live in `debugger-tool/ahk-error-agent/include/`. `/include` takes
one file and must precede the script path.

```powershell
# Basic (any AHK v2 engine, including stock)
& $engine /include debugger-tool/ahk-error-agent/include/cloudahk-error-handler.ahk script.ahk
# Enhanced (adds source lines through _ScriptGetLines, i.e. this fork)
& $engine /include debugger-tool/ahk-error-agent/include/cloudahk-error-handler-enhanced.ahk script.ahk
```

```bash
# Git Bash: double the slash
"$engine" //include debugger-tool/ahk-error-agent/include/cloudahk-error-handler-enhanced.ahk script.ahk
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

## Fork-only BIFs (built in)

These do not exist in upstream AutoHotkey, so stock engines (including one a
user-wide `ahk` server may run) lack them. Use them directly — no `#include`,
no helpers. `Inspect`, `ProcessPipe` and `/Coverage` need an engine whose
`--capabilities` `features` lists `inspect`, `processPipe` and `coverage`
(built from a551fcd4 or later); an older build (any exe whose `--capabilities`
lacks them) does not have them. `features` does not cover the other BIFs
(its `check` is the CLI verb, not `Check()`). To probe one, run `check` on a
one-line script that calls it. A missing function does not fail `check`: the
exit code stays 0, and a warning, `This global variable appears to never be
assigned a value.`, names it.

- **`Print(Fmt?, Values*)`** — stdout println with built-in `Format` dispatch.
  - `Print()` → blank line
  - `Print("plain text")` → write as-is (single-arg form never goes through Format, so literal `{ }` survive)
  - `Print("x={}, y={}", x, y)` → calls `Format(Fmt, Values*)` then writes
  - **Don't write `Print(Format("...", x))`** — pass the args directly to `Print` instead.
  - Writes to an attached console or redirected stdout when available.
- **`Eval(Expression)`** — runtime expression eval. Gated by `#EnableEval` directive or `/Eval` CLI flag (`--eval` from Git Bash). Throws `SyntaxError` on parse failure and a catchable `ValueError` above 16,384 UTF-16 code units. The REPL uses the same limit and continues after an oversized expression. Compiled Eval storage still has process lifetime to preserve closures. See `updates.md` section 1.
- **`SyntaxError`** — exception class for parse errors (`is Error`). One thrown by `Eval` has only the own properties `Message`, `File` (`"_Eval"`), `Line` (0) and `Column` (0); reading its `What`, `Extra` or `Stack` throws `PropertyError`, so a generic `catch as e` logger must guard them. One built with `SyntaxError(Message, What?, Extra?)` has the usual Error properties (`What`, `Extra`, `File`, `Line`, `Stack`) and no `Column`.
- **`Check(Source)`** — validate AHK source with automatic oracle parity: spawns this exe in check mode (`/Diag=json /Check`) against a temp file in a child process, so host state is untouched and the verdict matches the CLI. Returns `{ Ok, Diagnostics, Raw }`: `Ok` is 1 when the child exits 0 (warnings allowed) and 0 otherwise (13 for a syntax error); `Diagnostics` is an Array of `{ Severity, Type, Code, Message, Extra, File, Line, Column }` that is empty when Ok=1, even after warnings, and otherwise holds one record: the first diagnostic record in `Raw`, whatever its severity. A load-time warning printed before the error (VarUnset warnings are on by default) therefore takes the error's place, so check `Diagnostics[1].Severity` and read `Raw` for the rest. `Raw` is the captured child output. Its shared child runner has a 30-second timeout and 8 MiB combined output budget; a spawn failure, a timeout, an output-limit failure, or a nonzero exit with no diagnostic record returns Ok=0 with one synthetic diagnostic (`Severity` "error", `Code` 0, `Line` 0, a `Message` starting "Check:"). `Raw` combines stderr then stdout, preserving each stream's order without promising cross-stream chronology. Temporary-file and process-tree cleanup are automatic. The check-mode child skips ordinary script execution, but load-time directives such as `#DllLoad` can still have side effects; it is not a sandbox. This — not `TSParse(...).HasError` — is the correct 'does it parse?' check.
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
  same tags. Inserting, removing or resizing (`Push`, `InsertAt`, `RemoveAt`,
  `Pop`, `Length`, `Capacity`) and `Clone` keep each remaining item's tag, and
  new items carry none (`Push(true)` emits `1`); assigning an element, even
  its own value, or `Delete`-ing it drops that element's tag, so an edit
  never revives the source keyword. Options: `Container` ("JSON.Object"|"Map"),
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
- **`TSParse(Source)`** — parse AHK source with the bundled tree-sitter grammar; returns a snapshot tree of plain AHK objects. Lazily loads `tree-sitter-ahk.dll` on first call, from the engine's own directory and then the normal DLL search path (`bin/` ships the x64 DLL; copy it beside an isolated build). Returns `{ Root, Source, HasError }`; each node has `Type`, `StartByte`/`EndByte`, `StartRow`/`StartCol`/`EndRow`/`EndCol`, `Text`, `IsNamed`/`IsMissing`/`IsError`/`IsExtra`/`HasError`, `FieldName`, `Children`, `NamedChildren`, `Truncated`. For **structure only** — the grammar is incomplete (false `HasError` on valid code, e.g. typed Structs, fat-arrow methods, `^j::` hotkeys); do not use `TSParse(...).HasError` as a validity check. For 'does it parse?' use the `Check` BIF above (real-engine oracle), or the `check` CLI subcommand. Full docs: `docs/TREE_SITTER.md`.

Full reference: `updates.md` in the repo root.

## Design Documents

- `docs/plans/2026-06-21-in-process-mcp-server-design.md` - Native in-process MCP server design (historical)

## DBGp Protocol

`/Debug[=host[:port]]` makes the engine connect out to a DBGp listener (default
`localhost:9000`); `/Debug=stdio` speaks DBGp over stdin/stdout. Start the
listener first and put the switch before the script path. Name the port the
listener reports: a bare `/Debug` always means 9000, which another program may
hold. With no listener on that port (never started, stopped, or its server
restarted) the engine opens a modal "Failed to connect to an active debugger
client. Continue running the script without the debugger?" box, even with
`/Headless`; a script still attached when its listener goes away without
detaching it gets a similar one (a fixed build's `stop` detaches). `/Headless`
turns the engine's other prompts into stderr text. That includes the default
`#SingleInstance Prompt`, which runs before the debugger connects: a relaunch
of a script whose previous run is still alive (attached, paused or running)
prints `Another instance is already running. Use #SingleInstance Force or
/force.`, exits 64 and never connects. The console engine reports an uncaught
error on stderr and exits 10 with or without `/Headless`.

```text
PowerShell:  & .\bin\AutoHotkey64Console.exe /Debug=localhost:9001 /Headless script.ahk
Git Bash:    ./bin/AutoHotkey64Console.exe //Debug=localhost:9001 --headless script.ahk
```

- The project `ahk-mcp` server has no DBGp tool, and the legacy
  `debugger-tool/mcp-server` adapter is not registered.
- The user-wide `ahk` server's `AHK_Debug_DBGp` is in its hidden `debug`
  toolset; enable it only when the user asks. `start` binds 9000 by default and
  silently moves to 9001+ when that port is busy; its reply and
  `action:"status"` give the port. A build with the capture fix honors the
  `port` argument; an older build ignores it.
- What works depends on the server build. The ahk-mcp capture fix captures
  errors and evaluates paths. It is on ahk-mcp's local branch
  `fix/dbgp-capture-error` (not pushed, and not merged into `master`, which
  lacks it), and a running server loads a rebuilt `dist/` only after it
  restarts. `status` tells the builds apart: a fixed build lists
  `error_capture`, `session` and `waiting_connections`, an older one only
  `connected`, `port` and `errors_queued`. An older build never queues an
  error, so its
  `capture_error` always times out with `{"captured":false,"reason":"timeout"}`
  and `analyze_error` is unreachable; its `evaluate`, and `breakpoint_set`
  with a `condition`, fail with `Command timeout` after 10 s. There, read
  values with `variables_get`, use breakpoints and stepping, or run the script
  with `mcp__ahk-mcp__run` or `test` and read its diagnostics.
- Loop on a fixed build:
  1. `start`; the user launches the script with `/Debug=localhost:<port>`. On
     connecting the server sets an exception breakpoint, and the script waits
     at its first line. Set breakpoints then (`breakpoint_set` fails with
     `Not connected` before the script connects, and AutoHotkey rejects a
     `condition`).
  2. `run`, or let `capture_error` start the script. Every uncaught error is
     captured in the background and the script resumed (`run` then answers
     `error captured, script resumed (...)`); the console engine then prints
     the error on stderr and exits 10. At a breakpoint use `stack_trace`,
     `variables_get` (context 0 local, 1 global) and `evaluate`, which reads a
     variable or property path (`x`, `obj.prop`, `arr[1]`, `m["key"]`) and
     rejects operators (`a + b`): the engine has no eval command. A step that
     reaches a throw stays paused there.
  3. `capture_error` (`timeout`, default 30000 ms) returns the oldest queued
     error at once as `{"captured":true,"error":{...}}`, even one from an
     earlier run (`clear_errors` drops those). It resumes a script paused at
     a breakpoint or throw only when nothing is queued (one waiting at its
     first line is started either way), so after a step stops at a throw,
     send `run` (or call `capture_error` again) to let the script finish. The
     error has `error_type`, `message`, `file`, `line`, `source_context`,
     `stack_trace` (local paths), `local_variables`, `global_variables`,
     `timestamp`, `detected_by` and `session`, plus `what`, `extra` and
     `ahk_stack` when the thrown value has them. `line` is `Error.Line` (the
     caller's line when `what` names a function); `stack_trace[0]` is where
     the throw ran, which this fork's own error report (stderr, `--diag=json`)
     names instead (a fork bug; see WORKLOG Session 12).
     `detected_by:"stderr"` has no stack or variables. With nothing to return
     it gives `"reason":"not_listening"` at once without `start`, and
     `"reason":"session_ended"` (with `exit`) when the script ends during the
     call, or ended unreported before it. A run whose end you already learned
     is not reported again: once its error was returned or a `run` reply said
     `Status: stopped`, the call waits for the next launch and returns
     `"reason":"timeout"` without one, so relaunch first. `clear_errors` drops
     queued errors and a remembered end, so it has the same effect only on a
     script that already ended; one that ends after `clear_errors` is still
     reported once as `session_ended`. Before a relaunch of the same script,
     let the old run exit (send `run`, or `stop`, which detaches it, then
     `start` again; close a persistent script): while it is alive the
     default `#SingleInstance Prompt` refuses the relaunch (exit 64, never
     connects; `Force` or `/force` replaces the old run instead), so
     `capture_error` times out or returns the old run's `session_ended`. A
     result adds `waiting_connections` when another script (or a copy of one
     with `#SingleInstance Off`) connected while one is attached; it waits,
     paused at its first line, until the attached script ends.
  4. `analyze_error` with `error` set to that object returns a Markdown prompt
     for you to analyze (no confidence score). Show the user your diagnosis,
     then `apply_fix` (`file`, `line`, the exact current `original` line,
     `replacement`; it rewrites CRLF files with LF, on any build) and have
     the user relaunch once the old run has exited.
- Only one listener can own a port, so a VS Code debug session and
  `AHK_Debug_DBGp` must not share one (thqby's default debug port range is
  9002-9100).

DBGp commands: `run`, `step_into`, `step_over`, `breakpoint_set`, `property_get`, `stack_get`

---

# Current State & Open Items (updated 2026-10-08)

- Target language version: `2.1-alpha.33+Console`, based on upstream
  `v2.1-alpha.33` plus the upstream `alpha` commits through `47eabd41`
  (`docs/alpha/v2.1-alpha.33.md`). Always verify the actual executable's
  `--version` and hash; historical files in `bin/` or `bin_harness/` may be
  stale.
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
  restored. Every file under `examples/` passes `check` on the alpha.31
  harness, and on alpha.33 (47/47, 2026-10-08).
- [x] Stale `export` module examples fixed 2026-09-10: keyword dropped, and the
  `#Import {X} from M` / bare `#Import "file.ahk"` forms (never valid on this
  engine) rewritten as `#Import M {X}` / `#Import "file.ahk" {*}`.
- [ ] **`&Module.Var` corrupts the heap (upstream alpha.33 bug)**:
  `source/script_module.cpp:42`-`44` (`ScriptModule::__Ref`, upstream
  `9f4df71b`) returns `Var::GetRef()`'s uncounted reference
  (`source/var.cpp:245`-`248`) through `_o_return` without an `AddRef`.
  `r := &Mod.X` reads and writes through `%r%`, then the process exits
  0xC0000374 after auto-execute; `Bump(&Mod.X)` leaves `Mod.X` unset
  (`UnsetError`) and exits the same way. One `ObjAddRef(ObjPtr(r))` prevents
  both (rechecked 2026-10-08 on `f7712ec15171`). Also reproduced on the
  official `AutoHotkey_2.1-alpha.33.zip` GUI build (2026-10-08), so it is not
  the merge. Use `#Import Mod {X}` plus `&X`. Engine fix: `AddRef` before
  `_o_return(ref)`, then report it upstream. No suite pins it yet.
- [ ] **Module init is not lazy, by upstream design** (rechecked on alpha.33,
  2026-10-08): every module runs at startup in reverse order of creation
  (`source/script.cpp:1042`-`1048`, `Script::AutoExecSection`), so a
  `#Module` nothing imports still runs before `__Main`; since alpha.21
  (`c0ab7108`) a first reference only runs a module early
  (`source/var.cpp:1444`). The `v2.1-alpha.21` tag already has the run-all
  loop, so this is not a fork regression. `docs/alpha/v2.1-alpha.21.md` is
  corrected; still open: `examples/alpha21/README.md:25` ("Lazy
  initialization"), the comment at `examples/alpha21/05_lazy_module_init.ahk:57`
  ("Observed on the alpha.31 engine"), and a qa test pinning the order.
- [ ] `/Headless` does **not** suppress `MsgBox` (`source/script2.cpp:1257` ->
  `source/window.cpp:932`), `InputBox` (`source/lib/InputBox.cpp:75`) or
  `Gui`: `mHeadless` is read only at `source/error.cpp:1151`/`:1165` and
  `source/AutoHotkey.cpp:556`/`:596` (read from source, not run). Verify such
  scripts via a scratch copy with `MsgBox` → `Print`, or extend `/Headless`.
- [ ] Faster tree-sitter path: build `tree-sitter-ahk.wasm` + `web-tree-sitter`
  for in-process, incremental parsing in a Node host. Needs the grammar
  **source**: only `bin/tree-sitter-ahk.dll` (loaded by `source/ts_api.cpp:41`
  and `:45`) is vendored.
- [ ] `FileRead` of a zero-byte file returns no value (`source/lib/file.cpp:228`
  returns `OK` without one; upstream alpha.33 has the same line): `""` in v2.0
  mode, but under a top-level `#Requires AutoHotkey v2.1-...` it throws
  `UnsetError` "No value was returned." (`source/script_expression.cpp:452`);
  `FileRead(f, "RAW")` returns an empty Buffer (rechecked 2026-10-08). Pin it
  with a qa test and report it upstream.

Engine bugs found 2026-10-07 (WORKLOG Sessions 12-14), all rechecked on
alpha.33 (`f7712ec15171`) on 2026-10-08 and still present (the
`Debugger::FatalError` item from source only); none fixed yet:
- [ ] `JSON()` is callable (`source/json.cpp:1969`: the class is built on `JsonObject::sPrototype` with no factory) and returns a plain Object posing as `JSON.Object`: `.Set("a", 1)` corrupts memory (exit 11 "Invalid memory read/write." or 0xC0000374), `.Count` reads garbage and enumerating `.Keys` is nondeterministic and often crashes.
- [ ] `JSON.True`/`False`/`Null` are writable value properties (`source/json.cpp:1995` `SetOwnProp`; the comment at `:1983` says getter-only): `JSON.True := 5` and `JSON.Null := ""` stick.
- [ ] JSON `MaxDepth`: the parser checks each value's depth with the root at 0 (`source/json.cpp:954`, `:999`), the writer counts containers (`:1108`), so an innermost empty container one level deeper parses (and `Validate` accepts it) but cannot re-serialize: `[[]]` with `MaxDepth: 1`, or 257 nested `[]` by default (`[[1]]` is rejected).
- [ ] With `AllowTopLevelScalar: false`, `Parse`/`ParseAt` (`source/json.cpp:1464`, `:1875`) report `(line 1, col 1, pos 1)` wherever the scalar is, and `ParseAt` leaves `Pos` on it, so a catch-and-continue loop never advances; `Validate` (`:1780`) reports the position after the value (Line 3, Col 6, Pos 8 for "\n\n   42").
- [ ] `Check()` builds its single diagnostic from the first record of any severity (`source/console_check.cpp:262`): a VarUnset warning on line 2 plus a missing `Goto` label on line 3 gives `Ok=0` with only the warning; field extraction (`:110`, `:137`) searches to the end of the captured output, so a key missing from that record would be read from a later one (from source).
- [ ] DBGp `WritePropertyData` (same in upstream alpha.33): `source/Debugger.cpp:1508` stages UTF-8 at the buffer tail and `:1514` base64-encodes it forward over unread bytes (one 196000-byte value via `property_get -m 0` arrived 192142 bytes wrong from offset 1953 while a 140000-byte one arrived intact; the damage depends on the value's size and content); `:1476` counts a surrogate pair as 7 bytes (three emoji: `size="21"` for 12 bytes) and `-m 5` splits the pair into U+FFFD.
- [ ] `Debugger::FatalError` (`source/Debugger.cpp:2786`, MessageBox at `:2798`) shows a modal Yes/No box even under `/Headless` on a failed connect (`:2725`, `:2751`) or lost connection (`:2418`, `:2425`, `:2463`); only `/Debug=stdio` prints it (`:2790`). Upstream alpha.33 always shows the box. Read from source, not run.
- [ ] `source/error.cpp:1803`, in the uncaught-exception `Script::ShowError` overload (`:1775`), passes `TokenToString(t)` (Extra, else Message) to `GetLine` instead of `file`, so the uncaught-error report and `--diag=json` name the throw line, not `Error.Line` (created on line 3, thrown on line 6: reported as 6, `OnError` sees 3). Fork-only, from lexikos' linecontext commit `d8217d1a`; upstream alpha.33 matches by file index.
- [ ] `source/error.cpp:1784` `ExprTokenType t` reaches `:1803` uninitialized when the thrown object has own `File` and nonzero `Line` but neither `Message` nor `Extra`: `throw {File: A_LineFile, Line: 1}` on any line but the first exits 0xC0000409 with no report (alpha.33 and alpha.31, text and `--diag=json`). Engine fix: pass `file` to `GetLine` (this also fixes the item above).
- [ ] Headless error reports truncate silently: the text report is cut at `DIAG_JSON_BUF_SIZE`-1 = 87298 chars (`source/error.cpp:1167`, defined `:294`), mid-message and without `Specifically:`, source or stack; `--diag=json` stays valid but caps `message`/`extra` at 16384 chars each (`:439`-`:440`, `:450`-`:451`).
- [ ] The crash log writes `Error.Stack` raw after `  Stack:` (`source/crashlog.cpp:190`): its lines are not indented and end in CRLF, unlike every other LF line.
- [ ] An `Eval` `SyntaxError` is built by hand (`source/console_eval.cpp:59`-`64`: own `Message`, `File` `_Eval`, `Line` 0, `Column` 0 only), so reading `What`, `Extra` or `Stack` throws `PropertyError`.
- [ ] An `Eval` assignment inside a function adds a local to it for good (`source/console_eval.cpp:28` parses in the caller's scope): a later call's `Eval("qq")` reports a *local* unset, and `Eval("gv := 5")` leaves global `gv` unchanged. Documented in `updates.md:106`-`119`; close as intended or change it.
- [ ] `--coverage=` into a missing directory writes nothing, prints nothing and exits 0 (`source/coverage.cpp:92` returns on `INVALID_HANDLE_VALUE`); `qa/tests/test_coverage_missing_dir.ahk` pins it.
- [ ] DBGp has no `eval` command (`source/Debugger.cpp:47` command table; `eval` answers error 4) and `breakpoint_set` rejects `--` conditions (`:771`, error 3), as upstream alpha.33 does: clients read paths with `property_get`.
- [ ] Native `source_outline`/`workspace_symbols` match functions with one line regex (`source/mcp_server.cpp:930`-`931`, `MatchFuncDecl`), so they miss a function whose default parameters contain parentheses and every fat-arrow function: on `qa/Harness.ahk` they skip `RunQaChild` (line 25) and `SnippetOut` (line 118), which `ast_outline` finds (same on alpha.31). Engine fix: balance nested parentheses and accept `=>` bodies.
- [ ] `--help` (`source/AutoHotkey.cpp:86`-`111`) lists only slash options: not `/Debug[=host:port|stdio]`, and none of the Git Bash aliases (`--headless`, `--diag=`, `--eval`, `--trace`, `--crashlog=`, `--stderrfile=`, `--coverage=`) that `:353`-`:429` accept.

Follow-ups from the alpha.33 re-verification (2026-10-08), outside that pass's
docs-only scope:
- [ ] No suite covers an alpha.32/alpha.33 change. Add `qa/tests/test_alpha33.ahk`
  in the `test_alpha31.ahk` style: `Object.Prototype.DefineProp.Call` on a Struct
  throws `TypeError` (guards `a020f5b0`), `ObjSetCapacity` on a Struct throws
  `TypeError`, `a.b[1]` with `b => unset` throws `UnsetError`, `#Import` inside a
  function, `NumPut(Int32, ...)`/`NumGet(buf, Int32)`, `#Requires` scoping in an
  `#Include`, and `&Module.Var` as a KNOWN-BUG `RunSnippet` pin.
- [ ] `tests/test_powershell_cli.py:56` and
  `debugger-tool/mcp-ahk/tests/conformance_native.py:235` hard-code
  `2.1-alpha.33`; derive it from `source/ahkversion.h` as
  `tests/test_console_cli.py` does. `conformance_native.py:109`-`110` also
  writes fixtures into the repo's `temp/`.
- [ ] `python tools/check_all.py` walks dot-directories that only the local
  `.git/info/exclude` hides: a stale nested worktree under `.kilo/worktrees/`
  fails it locally (CI never has one). Skip dot-directories, or any directory holding a `.git` file, next to
  `SKIP_DIRS` (`tools/check_all.py:23`).
- [ ] The b44b48e3 merge brought in upstream's `.github/FUNDING.yml` (Lexikos)
  and `.github/ISSUE_TEMPLATE/config.yml` (bug reports to the autohotkey.com
  forum, wrong for fork features): replace with fork links or delete
  (maintainer decision).
- [ ] `.vscode/launch.json:54`-`56` still says `bin\AutoHotkey64.exe` lacks
  inspect, processPipe and coverage; both `bin/` exes now report alpha.33
  `f7712ec15171` with all three (`docs/VSCODE_SETUP.md` is corrected).
