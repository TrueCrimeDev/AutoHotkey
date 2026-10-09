# AutoHotkey v2 — Console Fork

A build of AutoHotkey v2.1-alpha that behaves like a real command-line program: runtime
errors go to `stderr` (as text **or** JSON), failures return meaningful exit codes, dialogs
can be suppressed, and the debugger speaks DBGp so an LLM can drive it. Everything else is
stock AutoHotkey.

![engine](https://img.shields.io/badge/engine-2.1--alpha.33%2BConsole-5B9FEF)
![based on](https://img.shields.io/badge/based%20on-AutoHotkey%20v2.1--alpha-22D3EE)
[![Build AutoHotkey](https://github.com/TrueCrimeDev/AutoHotkey/actions/workflows/build.yml/badge.svg)](https://github.com/TrueCrimeDev/AutoHotkey/actions/workflows/build.yml)
![coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/TrueCrimeDev/AutoHotkey/badges/coverage.json)
![license](https://img.shields.io/badge/license-GPL--2.0-7BC96F)
![platform](https://img.shields.io/badge/platform-Windows%20x64-808080)
[![docs](https://img.shields.io/badge/docs-Console%20%2B%20ClautoHotkey-A855F7)](https://truecrimedev.github.io/AutoHotkey/)

**Docs site:** [truecrimedev.github.io/AutoHotkey](https://truecrimedev.github.io/AutoHotkey/) — Console engine guides plus the [ClautoHotkey harness](https://truecrimedev.github.io/AutoHotkey/clautohotkey/harness.html) (static and dry-run gates for Claude Code).

---

## Contents

- [Why this fork](#why-this-fork)
- [Quick start](#quick-start)
- [Running scripts](#running-scripts)
- [Error reporting](#error-reporting)
- [Exit codes](#exit-codes)
- [Language additions](#language-additions)
- [Native JSON and local tools](#native-json-and-local-tools)
- [REPL](#repl)
- [Crash logging](#crash-logging)
- [Line coverage](#line-coverage)
- [Inspecting live objects](#inspecting-live-objects)
- [Driving child processes](#driving-child-processes)
- [CI for AutoHotkey libraries](#ci-for-autohotkey-libraries)
- [AI-assisted debugging](#ai-assisted-debugging)
- [Repository map](#repository-map)
- [Documentation](#documentation)
- [License](#license)

---

## Why this fork

Stock AutoHotkey is built for the desktop: errors open a MsgBox, output goes to GUIs, and a
script that fails still exits `0`. That model fights you the moment you run scripts from a
terminal, a CI job, or an agent loop. This fork keeps the language identical and changes only
the *plumbing around it* so AHK fits into pipes, scripts, and tooling.

| | Stock AutoHotkey | This fork |
|---|---|---|
| **Runtime error** | Modal MsgBox; nothing on `stderr` | Formatted text on `stderr`, with source context and stack |
| **Machine-readable errors** | — | `/Diag=json` emits a one-line JSON diagnostic per error |
| **Exit code on failure** | `0` | Distinct non-zero codes per failure class (10–14, 64, 130) |
| **Unattended runs** | Dialogs block forever | `/Headless` suppresses the engine's own prompts (script `MsgBox` calls still show) |
| **Syntax checking** | Run it and see | `check` subcommand: parse-only, exit `0`/`13` |
| **Single-script tests** | Roll your own | `test` subcommand: exit `0` on pass; failures keep their codes ([`test` exit codes](#exit-codes)) |
| **Crash forensics** | Lost when the window closes | `/CrashLog=` append-only event log that survives hard crashes |
| **Inline evaluation** | — | `Eval("expr")` runs an expression in live scope (opt-in) |
| **Interactive session** | — | `repl` subcommand: persistent eval loop over stdin/stdout |
| **stdout helper** | `FileOpen("*","w")` boilerplate | `Print(fmt, args*)` — UTF-8, `Format`-aware |
| **Debugger** | DBGp (desktop-oriented) | Same DBGp, wired to an MCP server for LLM-driven debugging |

None of this touches the language. The engine is upstream `v2.1-alpha.33` plus the upstream
`alpha` commits through `47eabd41` (see [`docs/alpha/v2.1-alpha.33.md`](docs/alpha/v2.1-alpha.33.md)),
so scripts that run on that upstream code run here unchanged; the additions are flags,
subcommands, and a few opt-in built-ins.

---

## Quick start

### Build (Windows)

CMake is the supported build route. [`BUILD.md`](BUILD.md) has the prerequisites and
commands for MSVC x64, MSVC Win32, and mingw-w64 GCC x64 (the three configurations CI
builds, syntax-checks and gates), and how to verify the exact executable you built. The
two x64 routes produce the console engine `AutoHotkey64Console.exe`, which the examples in
this README use, and the GUI `AutoHotkey64.exe`; the Win32 route produces
`AutoHotkey32Console.exe` and `AutoHotkey32.exe`.

- **Output directory.** CMake's `AHK_OUTPUT_DIR` defaults to `bin\`. BUILD.md's commands
  pass isolated directories (`out\msvc\x64`, `out\mingw\x64`) so a build never overwrites
  the engine in `bin\`. Copy a tested build into `bin\` when you want the examples below,
  `tools/ahk.ps1`, and the Claude Code setup (`.mcp.json`, hooks) to use it.
- **`build.bat`** is a convenience wrapper for the mingw-w64 route: it builds in
  `build_gcc\` and writes both executables straight into `bin\`.
- **`AutoHotkeyx.sln` / `build_local.bat`** remain available for the GUI executable only.

### First run

```powershell
bin\AutoHotkey64Console.exe script.ahk
```

Use `bin\AutoHotkey64Console.exe --help` to discover commands, `--version` to identify the
engine, compiler, architecture, and source revision, or `--capabilities` for JSON.
An uncommitted source build reports its base revision with a `-dirty` suffix.

For PowerShell, build `AutoHotkey64Console` as described in [BUILD.md](BUILD.md)
and dot-source `tools/ahk.ps1` from this checkout (or from your PowerShell profile).
It registers `ahk` as a native alias to `bin/AutoHotkey64Console.exe`, so the
terminal waits for scripts and the REPL receives keyboard input directly.

```powershell
. .\tools\ahk.ps1
ahk                       # Version and quick guide
ahk help                  # Also: -h, --h, -help, --help
ahk run .\script.ahk       # Or: ahk .\script.ahk
ahk check .\script.ahk
ahk repl                  # Type .exit to return to PowerShell
```

The console executable reports script errors in the terminal by default. The
standard `AutoHotkey64.exe` remains available for GUI launches; PowerShell does not
wait for it unless its output is piped, so its exit code is lost. See the
[PowerShell repair notes](docs/powershell-cli-20260907.md) for troubleshooting.

Git tracks only `bin/tree-sitter-ahk.dll`; everything else in `bin/` is local, so a
fresh clone has no engine there until you build one or copy a release console engine
in. Executables in `bin/` can also be older than the source, and the x64 and x86 or
GUI and console files need not come from the same build, so check `--version` on the
one you run. For everyday terminal use, choose `AutoHotkey64Console.exe` through `ahk`.

### Confirm the console behavior

```powershell
bin\AutoHotkey64Console.exe tests\test_console.ahk 1>out.txt 2>err.txt
```

Normal output ends up in `out.txt`; the runtime error lands in `err.txt`, and the process
exits `10`. That split — stdout for results, stderr for diagnostics — is the whole point.

---

## Running scripts

One executable, selected into different modes by its first arguments:

| Invocation | Mode |
|---|---|
| `AutoHotkey64Console.exe script.ahk` | Normal run; runtime errors → `stderr` as text |
| `AutoHotkey64Console.exe /Debug script.ahk` | Connect to a DBGp debugger (default `localhost:9000`; `/Debug=host:port` for another). With no listener, or when it goes away, the script runs on and `stderr` says `Debugger error: ... continuing without the debugger.` |
| `AutoHotkey64Console.exe /ErrorStdOut script.ahk` | Runtime errors → `stderr` as text (the console engine's default) |
| `AutoHotkey64Console.exe /ErrorStdOut:color script.ahk` | …with ANSI color |
| `AutoHotkey64Console.exe /ErrorStdOut=UTF-8 script.ahk` | …with an explicit encoding |
| `AutoHotkey64Console.exe /Headless script.ahk` | Report the engine's error and warning prompts on `stderr` instead of dialogs (a script's own `MsgBox`, `InputBox`, and `Gui` still show) |
| `AutoHotkey64Console.exe /Diag=json script.ahk` | Runtime errors → `stderr` as JSON |
| `AutoHotkey64Console.exe check script.ahk` | Parse only — exit `0` (ok) / `13` (fail) |
| `AutoHotkey64Console.exe test script.ahk` | Run as a test — exit `0` (pass), `10` (uncaught error), `12` (parse error), `14` (`ExitApp(14)`, a persistent script, or an execution failure) |
| `AutoHotkey64Console.exe repl [script.ahk]` | Interactive / pipe-driven eval session ([REPL](#repl)) |
| `AutoHotkey64Console.exe mcp` | Native local tools over stdin/stdout |
| `AutoHotkey64Console.exe --help` | Commands, flags, and usage |
| `AutoHotkey64Console.exe --version` | Engine version and build identity |
| `AutoHotkey64Console.exe --capabilities` | Machine-readable feature and protocol information |
| `AutoHotkey64Console.exe /Trace script.ahk` | Stream readable executing statements to stderr; quiet while idle ([trace notes](docs/console-trace-20260907.md)) |

The GUI `AutoHotkey64.exe` accepts the same commands and flags; use the console engine
from a terminal, CI job, or agent so the shell waits for it and receives its output.

Flags compose. A typical unattended invocation:

```powershell
bin\AutoHotkey64Console.exe /Headless /Diag=json script.ahk 2>diagnostics.jsonl
```

Global flags can precede a command: `/Headless /Diag=json check script.ahk`.
Arguments after the script filename belong to the script. Use `--` before a script
filename which would otherwise be interpreted as a command or flag.

Git Bash rewrites any argument that starts with `/` into a path, so from Git Bash use
the aliases `--headless`, `--diag=json`, `--coverage=`, `--trace`, `--eval`,
`--crashlog=`, and `--stderrfile=`, or double the slash for other switches
(`//Debug`, `//ErrorStdOut`, `//include`). PowerShell and cmd pass `/Flag` unchanged.

---

## Error reporting

### Human-readable (`/ErrorStdOut`)

A runtime error is printed to `stderr` with the location, the message, and a source window
that marks the offending line:

```text
demo.ahk (4) : ==> This value of type "String" has no method named "NoSuchMethod".
          2| Print("starting work")
          3| x := "hello"
        > 4| x.NoSuchMethod()
          5|
          6|
```

The process exits `10`, so a shell or CI step sees the failure without parsing anything.

### Machine-readable (`/Diag=json`)

The same error, as one JSON object per line (newline-delimited — pipe it straight into a
`.jsonl` consumer):

```json
{"kind":"diagnostic","format":"json","schema":2,"severity":"error","type":"MethodError","code":10,"message":"This value of type \"String\" has no method named \"NoSuchMethod\".","extra":"","what":"","file":"demo.ahk","line":4,"column":0,"source":"x.NoSuchMethod()","stack":""}
```

Fields (`schema` 2):

| Field | Meaning |
|---|---|
| `kind` | `"diagnostic"` (errors/warnings) or `"check"` (the `check` subcommand verdict) |
| `severity` | `error` or `warning` |
| `type` | AHK error class — `MethodError`, `TypeError`, `ValueError`, … |
| `code` | The process exit code this error maps to |
| `message` | The error text |
| `file`, `line`, `column` | Location (`column` is best-effort; often `0`) |
| `source` | The exact source line |
| `what`, `extra`, `stack` | Function context, extra detail, and call stack when available |

`#Warn` diagnostics flow through the same formatter, so a warning becomes a
`"severity":"warning"` record instead of corrupting stdout. The `check` subcommand emits
`{"kind":"check","status":"pass"}` on success.

### Stream separation

```ahk
FileAppend("result`n", "*")    ; → stdout
FileAppend("oops`n", "**")     ; → stderr
```

Results and diagnostics stay on separate streams, so a consumer can read `1>` and `2>`
independently.

---

## Exit codes

Failures are distinguishable by exit code alone — no output scraping required:

| Code | Meaning | Crash-log reason |
|---|---|---|
| `0` | Success | `Normal` |
| `10` | Uncaught script exception | `Error` |
| `11` | Internal/critical error or SEH fault | `Critical` / `Fatal` |
| `12` | Parse / load failure | `Parse` |
| `13` | `check` failed | `Check` |
| `14` | `test` failed | `Test` |
| `64` | CLI usage error | `Usage` |
| `130` | Ctrl+C / console close / logoff / shutdown | `ExternalSignal` |

`ExitApp(n)` with any other `n` passes that code straight through.

Under `test`, a script that runs to its end exits `0` and prints `TEST PASS`. An uncaught
error still exits `10` and a parse error `12`. Code `14` comes from an explicit
`ExitApp(14)` (the [`Test.ahk`](tests/Test.ahk) framework uses it for failed cases), a
persistent script (`TEST FAIL: test mode requires a non-persistent script.`), or an
execution failure. Other `ExitApp(n)` codes pass through, `0` included, without the
`TEST PASS` line. `--capabilities` lists the codes under `exitCodes`.

---

## Language additions

A small set of fork-only built-ins. The first two are always available; `Eval` is opt-in. See
[`updates.md`](updates.md) for the complete reference, edge cases, and tests.

### `Print(fmt, args*)` — stdout, the easy way

UTF-8 `println` with built-in `Format` dispatch. No `FileOpen` boilerplate; a silent no-op
when no console is attached.

```ahk
Print("hello")                      ; hello
Print("x={}, y={}", 42, "world")    ; x=42, y=world
Print("0x{:08X}", 0xDEAD)           ; 0x0000DEAD
Print("{ok: true}")                 ; single-arg form is literal — braces survive
```

### `Eval(expr)` — evaluate an expression in live scope *(opt-in)*

Runs any AHK expression string against the caller's variables — reads and writes locals, calls
methods, supports v2.1-alpha expression features (maybe operator, unset propagation). Gated behind `#EnableEval` (or the `/Eval`
flag) so it can never run unless you ask for it.

```ahk
#EnableEval
x := 10, y := 20
MsgBox(Eval("x + y"))   ; 30
Eval("x := x + 1")      ; mutates the caller's x
```

Bad input throws `SyntaxError`; missing identifiers throw `UnsetError`.

### `SyntaxError` — parse-failure exception

An `Error` subclass, thrown by `Eval` on parse failure and available for your own parsers
to throw. One thrown by `Eval` carries only `Message`, `File` (`"_Eval"`), `Line` (`0`) and
`Column` (`0`). It has no `What`, `Extra` or `Stack`, so reading `e.What` raises a
`PropertyError` inside the handler; check `e.HasProp("What")` first. A `SyntaxError` your
script constructs has the usual `Error` properties (`What`, `Extra`, `File`, `Line`, `Stack`)
but no `Column`. Details: [`updates.md` §3](updates.md).

### `_ScriptGetLines(File, Line, Range?)` — source context

Returns the parsed lines around a position as an Array of `{File, Number, Text}` — the
primitive the debugger tooling uses to show surrounding code. `Text` is the engine's rendering
of the line, and comments and blank lines are skipped. A negative or omitted `Range` returns
only the given line. A line with no code returns no Array (an empty string, or no value under
a `#Requires AutoHotkey v2.1-...` at the top level of the calling module's own file; one in an
`#Include` file or a function no longer sets the mode), so guard the call:

```ahk
for line in (_ScriptGetLines(A_LineFile, A_LineNumber, 3) ?? "") || []   ; up to 3 parsed lines either side
    Print("{:03}: {}", line.Number, line.Text)
```

---

## Native JSON and local tools

`JSON.Parse`, `JSON.Stringify`, and `JSON.Validate` are built in:

```autohotkey
values := JSON.Parse('[true,false,null]')
values[1] := "edited"
Print(JSON.Stringify(values)) ; ["edited",false,null]
```

Parsed arrays preserve untouched boolean/null types through edits, insertion,
removal, resizing, and cloning. Assignment clears the original element's type tag;
use `JSON.True`, `JSON.False`, or `JSON.Null` (read-only singletons) when explicitly
assigning those types. `JSON` itself is not a constructor: `JSON()` throws `TypeError`;
create objects with `JSON.Parse`.
String values support embedded NUL characters. Object keys containing NUL are
rejected with `UnsupportedKey` to prevent truncation and key collisions.

`bin\AutoHotkey64Console.exe mcp` provides the native MCP tools to a local client over
stdin/stdout. It does not need a network listener. `--capabilities` reports the
supported protocol versions and engine features. The optional bundled tree-sitter
grammar DLL supports x64 only.

## REPL

`repl` turns the binary into a persistent interpreter session: expressions arrive on
stdin (terminal or pipe), results leave on stdout, state survives between lines. Built
on the `Eval` machinery, so the loaded script's globals, functions and classes are all
live.

```text
$ bin\AutoHotkey64Console.exe repl
AutoHotkey v2.1-alpha.33+Console REPL - one expression per line; .help for commands
>>> x := 10
10
>>> x * 4
40
>>> g := Gui("+AlwaysOnTop", "Live"), g.Show("w200 h80")
>>> g.BackColor := 0x202020
2105376
>>> .exit
```

- `repl script.ahk` loads the script, runs its auto-execute section, then opens the
  session against its state — hotkeys, timers and GUI events keep firing throughout.
- Recoverable parse and runtime errors print one line (stderr in text mode) and the
  loop continues. Invalid syntax preserves existing variable lookup state.
- EOF or `.exit` exits `0`; `ExitApp(n)` exits with `n`.
- `/Diag=json` produces one JSON result per input line, including blank lines,
  `.help`, and `.exit`. Results use the full string length, including escaped NULs.
  Ordinary script output (`Print`, `FileAppend`, `FileOpen`, and startup output)
  goes to stderr so stdout remains readable as JSON. Explicit `ExitApp` or a fatal
  process failure can end the session before a result is written.

```json
{"kind":"result","ok":true,"type":"Integer","value":"42"}
{"kind":"result","ok":false,"type":"SyntaxError","value":"Missing operand."}
```

Spawn-per-expression is gone: an agent (or the MCP server) opens one process, writes
lines, reads lines, and closes stdin when done. Full reference: [`updates.md` §16](updates.md).

---

## Crash logging

`/CrashLog=<path>` (or the `#CrashLog <path>` directive) records every notable event —
startup, parse errors, uncaught exceptions, fatal interpreter faults, and signal-triggered
exits — to an append-only, UTF-8 log. Each record is written open-write-flush-close, so the
last events survive even a hard crash. It works regardless of how the script was launched,
including launchers that discard `stderr`.

```text
[2026-05-13 21:35:14] [START] pid=12345 ahk=2.1-alpha.33+Console script=C:\app\app.ahk ...
[2026-05-13 21:43:22] [ERROR] pid=12345 type=MethodError mode=Return
  Message: This value of type "String" has no method named "DoStuff".
  File: C:\app\Lib\Clip.ahk
  Line: 142
  What:
  Extra:
  Stack:
C:\app\Lib\Clip.ahk (142) : [Clip.Foo] s.DoStuff()
C:\app\app.ahk (33) : [] Clip.Foo()
> Auto-execute
[2026-05-13 21:43:22] [EXIT] pid=12345 code=10 reason=Error
```

The `Stack:` lines are the error's own `Stack` text, written unindented with CRLF endings,
so a record runs until the next `[YYYY-MM-DD` header line.

Event types, reason names, `OnError` interaction, and limitations: [`updates.md` §4](updates.md).

---

## Line coverage

`/Coverage=<path>` writes an LCOV tracefile at exit with no script instrumentation. The
parser supplies the executable lines, the interpreter's per-line dispatch counts the hits,
and alpha-only syntax is counted correctly because the engine itself is the source of truth.

```powershell
bin\AutoHotkey64Console.exe /Headless /Coverage=coverage\tests.lcov test tests\run.ahk
python tools\lcov_summary.py "coverage/**/*.lcov" --include "^Lib/" --badge coverage\badge.json
```

The engine creates a missing report directory, every level of it. If the report still
cannot be written (say, the path runs through an existing file), one stderr line names
the report and the Win32 error (a warning record under `/Diag=json`), and the exit code
is the script's own ([`updates.md` §17](updates.md)).

```text
SF:C:\lib\Async.ahk
DA:12,1
DA:13,0
LF:2
LH:1
end_of_record
```

Structural lines (`else`, `catch`, `case`, braces, function headers) are not reported, so
they never count against you. The file is rewritten open-write-flush-close on every exit
path, including uncaught errors and fatal faults, so a crashing test still leaves partial
data. Details: [`updates.md` §17](updates.md).

---

## Inspecting live objects

`Inspect(value, depth := 2, maxItems := 100)` returns JSON describing a value without
running any of its code: own values, the names of getters, setters and methods (own and
inherited), array items, map entries, function signatures. Cycles and depth limits are
reported, not followed. The REPL prints object results this way too.

```autohotkey
btn := Gui().AddButton("w200", "Save")
Print(Inspect(btn, 1))
; {"type":"Gui.Button","properties":{},"getters":["Text","Type","Enabled",...],"methods":["Focus","Move","OnEvent",...]}
```

Details: [`updates.md` §18](updates.md).

---

## Driving child processes

`ProcessPipe` runs a program with UTF-8 stdin/stdout/stderr pipes inside a job object, so
releasing the object or calling `Kill()` takes the whole process tree with it. Waits keep
timers and hotkeys running. It is the transport for hosting a JSONL agent server such as
Codex's app-server from a script.

```autohotkey
p := ProcessPipe("codex", ["app-server"])
p.SendLine(JSON.Stringify({method: "initialize", id: 1, params: {}}))
reply := JSON.Parse(p.ReadLine(30))   ; TimeoutError after 30 s
```

Details: [`updates.md` §19](updates.md). `/Trace=json` (§20) and the native MCP server's
`check`/`run`/`test` tools (§21) close the loop from the other side.

---

## CI for AutoHotkey libraries

GitHub's Windows runners run in an interactive session, so GUI and hotkey code works.
`/Headless` suppresses the engine's own prompts (error dialogs, startup warnings), but a
script's own `MsgBox` still opens a real dialog and blocks the job, so keep those out of test
paths. A library repo needs three things: the engine, a single-process test entry point, and
the `test` subcommand.

**1. Fetch the engine** from the latest tagged release (seconds, no build):

```yaml
runs-on: windows-latest
steps:
  - uses: actions/checkout@v4
  - run: gh release download -R TrueCrimeDev/AutoHotkey -p AutoHotkey64Console.exe -D bin
    env: { GH_TOKEN: ${{ github.token }} }
```

This needs a published `v*` tag release; until one exists, `gh release download` fails
with `release not found`, so build the engine per [`BUILD.md`](BUILD.md) instead.

**2. Write `tests/run.ahk`** that `#Include`s the framework and every `tests/*.test.ahk`
(copy [`tests/Test.ahk`](tests/Test.ahk) and [`tests/run.ahk`](tests/run.ahk) from this
repo). Test files register cases:

```autohotkey
Test.Case("parses a config", () => Assert.Eq(JSON.Parse('{"a":1}')["a"], 1))
Test.Case("rejects garbage", () => Assert.Throws(() => JSON.Parse("{"), JSONError))
```

`Test.Run()` prints one line per case, exits 14 on any failure, emits `::error` annotations
under GitHub Actions, and writes JUnit XML when `AHK_TEST_JUNIT` is set.

**3. Run it** with coverage and machine-readable diagnostics:

```yaml
  - run: bin\AutoHotkey64Console.exe /Headless /Diag=json /Coverage=coverage.lcov test tests\run.ahk 2>diag.jsonl
  - if: failure()
    shell: pwsh
    run: |
      Get-Content diag.jsonl | ConvertFrom-Json | % {
        "::error file=$($_.file),line=$($_.line)::$($_.type): $($_.message)" }
```

Uncaught errors become PR annotations for free. For a README number, feed `coverage.lcov`
to `codecov/codecov-action`, or copy this repo's no-third-party route from
[`build.yml`](.github/workflows/build.yml): `tools/lcov_summary.py` computes `LH/LF`,
writes a shields.io endpoint JSON, and the workflow force-pushes it to a `badges` branch
that `img.shields.io/endpoint` reads. Each build job also has a syntax-check step
(`python tools/check_all.py` on the engine that job just built) that parses every `.ahk` in
a couple of seconds; the test job needs the MSVC build jobs, so it does not start after a
parse failure there.

---

## AI-assisted debugging

`AutoHotkey64Console.exe mcp` is the primary MCP surface. The engine serves MCP over
stdin/stdout itself, with no Node bridge and no network listener. Its `check`, `run` and
`test` tools spawn the engine on a file and return the exit code, captured streams and JSON
diagnostics ([`updates.md` §21](updates.md)); on the current build `tools/list` also reports
`ast_outline`, `get_source_context`, `server_status`, `source_outline` and
`workspace_symbols`. The checked-in [`.mcp.json`](.mcp.json) registers it for Claude Code as
`ahk-mcp`, and `tests/test_mcp_protocol.py` pins the protocol envelope.

The fork also preserves AutoHotkey's DBGp debugger. The legacy DBGp bridge
([`debugger-tool/mcp-server/`](debugger-tool/mcp-server/)) is a separate Node MCP server that
drives it for LLM tools such as Claude Code and Cursor; until roadmap A1 completes the
debugger protocol, breakpoints, stepping, stack and variable inspection and error capture
live only there. Combined with the structured errors above, this closes a tight loop:

```
run script → capture structured error → inspect source / variables → apply fix → re-run
```

The bridge speaks DBGp on port 9000, or supervises the engine over `/Debug=stdio` with
`launch_script`, and surfaces 28 tools:

| Group | Tools |
|---|---|
| Supervision | `launch_script`, `terminate_script`, `get_script_output` |
| Execution | `debug_run`, `debug_step_into` / `_over` / `_out`, `debug_stop`, `debug_status`, `debug_command` |
| Breakpoints | `breakpoint_set`, `breakpoint_remove`, `breakpoint_list` |
| Inspection | `variables_get`, `evaluate`, `stack_trace`, `watch_add` / `_remove` / `_list` |
| Source intel | `get_source_context`, `source_outline`, `ast_outline`, `workspace_symbols` |
| Error loop | `capture_error`, `analyze_error`, `apply_fix` |
| Queue | `list_errors`, `clear_errors` |

**Start it** (the server must be listening before the script connects; otherwise the
script runs without the debugger and says so on `stderr`):

```powershell
cd debugger-tool\mcp-server
npm install && npm run build
node build/index.js
```

```powershell
bin\AutoHotkey64Console.exe /Debug your_script.ahk    # connects to localhost:9000
```

Tool-by-tool usage lives in [`debugger-tool/mcp-server/README.md`](debugger-tool/mcp-server/README.md).

For Claude Code, the [ClautoHotkey](https://github.com/TrueCrimeDev/ClautoHotkey) plugin wraps this engine in post-edit validation hooks and a grading harness. The harness docs are on the site: [Static & dry-run gates](https://truecrimedev.github.io/AutoHotkey/clautohotkey/harness.html) and [MCP integration](https://truecrimedev.github.io/AutoHotkey/clautohotkey/mcp.html).

---

## Repository map

| Path | Purpose |
|---|---|
| [`source/`](source/) | AutoHotkey engine source (C++) — fork changes live here |
| [`debugger-tool/mcp-server/`](debugger-tool/mcp-server/) | Legacy DBGp bridge: a Node MCP server for breakpoints, stepping and error capture |
| [`debugger-tool/ahk-error-agent/`](debugger-tool/ahk-error-agent/) | Headless error-capture and fix-automation agent |
| [`examples/`](examples/) | Runnable feature demos — `alpha21/`, `alpha22/`, plus structs, GUIs, and ANSI showcases |
| `examples/Alpha22_Example.ahk` … `examples/Alpha30_Example.ahk` | Per-version language showcases |
| `tests/` | `run.ahk` + `*.test.ahk` single-process suite, `Test.ahk` framework, Python console-gate suites |
| [`qa/`](qa/) | Subprocess-per-test interpreter regression suite |
| `tools/` | `check_all.py` (parse every `.ahk`), `lcov_summary.py` (merge coverage, badge JSON) |
| [`BUILD.md`](BUILD.md) | Build instructions |
| [`updates.md`](updates.md) | Complete fork reference |

---

## Documentation

| Document | Covers |
|---|---|
| [Docs site](https://truecrimedev.github.io/AutoHotkey/) | Console + ClautoHotkey guides, recipes, showcase (built from `website/`) |
| [ClautoHotkey harness](https://truecrimedev.github.io/AutoHotkey/clautohotkey/harness.html) | Static & dry-run gates, `ahk-harness/result@1` schema, `CheckResults.py` |
| [`updates.md`](updates.md) | Authoritative reference for every fork addition |
| [`BUILD.md`](BUILD.md) | Toolchains, build configs, troubleshooting |
| [`CLAUDE.md`](CLAUDE.md) | Project orientation for AI agents |
| [`V3_MILESTONE_STATUS.md`](docs/V3_MILESTONE_STATUS.md) | Milestone implementation status |
| [`docs/TREE_SITTER.md`](docs/TREE_SITTER.md) | Vendored tree-sitter AHK grammar DLL: exports, DllCall usage |
| `debugger-tool/mcp-server/README.md` | MCP tool reference and setup |

---

## License

This fork inherits AutoHotkey's **GNU GPL v2** license — see [`license.txt`](license.txt). It
is a specialized fork, not a claim of upstream parity; for stock behavior, use an official
[AutoHotkey](https://www.autohotkey.com/) build. Built on
[AutoHotkey v2.1-alpha](https://github.com/AutoHotkey/AutoHotkey) by Lexikos and contributors.
