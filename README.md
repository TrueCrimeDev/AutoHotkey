# AutoHotkey v2 — Console Fork

A build of AutoHotkey v2.1-alpha that behaves like a real command-line program: runtime
errors go to `stderr` (as text **or** JSON), failures return meaningful exit codes, dialogs
can be suppressed, and the debugger speaks DBGp so an LLM can drive it. Everything else is
stock AutoHotkey.

![engine](https://img.shields.io/badge/engine-2.1--alpha.31%2BConsole-5B9FEF)
![based on](https://img.shields.io/badge/based%20on-AutoHotkey%20v2.1--alpha-22D3EE)
[![Build AutoHotkey](https://github.com/TrueCrimeDev/AutoHotkey/actions/workflows/build.yml/badge.svg)](https://github.com/TrueCrimeDev/AutoHotkey/actions/workflows/build.yml)
![license](https://img.shields.io/badge/license-GPL--2.0-7BC96F)
![platform](https://img.shields.io/badge/platform-Windows%20x64-808080)

---

## Contents

- [Why this fork](#why-this-fork)
- [Quick start](#quick-start)
- [Running scripts](#running-scripts)
- [Error reporting](#error-reporting)
- [Exit codes](#exit-codes)
- [Language additions](#language-additions)
- [REPL](#repl)
- [Crash logging](#crash-logging)
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
| **Unattended runs** | Dialogs block forever | `/Headless` suppresses every interactive prompt |
| **Syntax checking** | Run it and see | `check` subcommand: parse-only, exit `0`/`13` |
| **Single-script tests** | Roll your own | `test` subcommand: exit `0`/`14` |
| **Crash forensics** | Lost when the window closes | `/CrashLog=` append-only event log that survives hard crashes |
| **Inline evaluation** | — | `Eval("expr")` runs an expression in live scope (opt-in) |
| **Interactive session** | — | `repl` subcommand: persistent eval loop over stdin/stdout |
| **stdout helper** | `FileOpen("*","w")` boilerplate | `Print(fmt, args*)` — UTF-8, `Format`-aware |
| **Debugger** | DBGp (desktop-oriented) | Same DBGp, wired to an MCP server for LLM-driven debugging |

None of this touches the language. Scripts that run on upstream `v2.1-alpha.31` run here
unchanged; the additions are flags, subcommands, and a few opt-in built-ins.

---

## Quick start

### Build (Windows)

GCC (**mingw-w64** via [MSYS2](https://www.msys2.org)) is the canonical compiler. Install the
toolchain once:

```bash
pacman -S mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja
```

then build from the repo root:

```powershell
.\build.bat
```

Output lands in `bin\AutoHotkey64.exe`. MSVC is still supported as an alternative
(`build_local.bat`) and produces the CI release binary. Full details — both toolchains, manual
invocations, and the CMake flags — are in [`BUILD.md`](BUILD.md) and [`updates.md` §12](updates.md).

### First run

```powershell
bin\AutoHotkey64.exe script.ahk
```

### Confirm the console behavior

```powershell
bin\AutoHotkey64.exe /ErrorStdOut tests/test_errorstdout.ahk 1>out.txt 2>err.txt
```

Normal output ends up in `out.txt`; the runtime error lands in `err.txt`. That split — stdout
for results, stderr for diagnostics — is the whole point.

---

## Running scripts

One executable, selected into different modes by its first arguments:

| Invocation | Mode |
|---|---|
| `AutoHotkey64.exe script.ahk` | Normal run |
| `AutoHotkey64.exe /Debug script.ahk` | Connect to a DBGp debugger on port 9000 |
| `AutoHotkey64.exe /ErrorStdOut script.ahk` | Runtime errors → `stderr` as text |
| `AutoHotkey64.exe /ErrorStdOut:color script.ahk` | …with ANSI color |
| `AutoHotkey64.exe /ErrorStdOut=UTF-8 script.ahk` | …with an explicit encoding |
| `AutoHotkey64.exe /Headless script.ahk` | Suppress all dialogs (non-interactive) |
| `AutoHotkey64.exe /Diag=json script.ahk` | Runtime errors → `stderr` as JSON |
| `AutoHotkey64.exe check script.ahk` | Parse only — exit `0` (ok) / `13` (fail) |
| `AutoHotkey64.exe test script.ahk` | Run as a test — exit `0` (pass) / `14` (fail) |
| `AutoHotkey64.exe repl [script.ahk]` | Interactive / pipe-driven eval session ([REPL](#repl)) |

Flags compose. A typical unattended invocation:

```powershell
bin\AutoHotkey64.exe /Headless /Diag=json script.ahk 2>diagnostics.jsonl
```

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
methods, supports alpha.31 expression features. Gated behind `#EnableEval` (or the `/Eval`
flag) so it can never run unless you ask for it.

```ahk
#EnableEval
x := 10, y := 20
MsgBox(Eval("x + y"))   ; 30
Eval("x := x + 1")      ; mutates the caller's x
```

Bad input throws `SyntaxError`; missing identifiers throw `UnsetError`.

### `SyntaxError` — parse-failure exception

A real `Error` subclass (`Message`, `What`, `Extra`, `Line`, `Column`), thrown by `Eval` on
parse failure and available for your own parsers to throw.

### `_ScriptGetLines(File, Line, Range?)` — source context

Returns source-text lines around a position — the primitive the debugger tooling uses to show
surrounding code:

```ahk
for line in _ScriptGetLines(A_LineFile, A_LineNumber, -3)   ; 3 lines either side
    Print("{:03}: {}", line.Number, line.Text)
```

---

## REPL

`repl` turns the binary into a persistent interpreter session: expressions arrive on
stdin (terminal or pipe), results leave on stdout, state survives between lines. Built
on the `Eval` machinery, so the loaded script's globals, functions and classes are all
live.

```text
$ bin\AutoHotkey64.exe repl
AutoHotkey v2.1-alpha.31+Console REPL - one expression per line; .help for commands
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
- **Errors never end the session**: parse and runtime errors print one line (stderr in
  text mode) and the loop continues with prior state intact.
- EOF or `.exit` exits `0`; `ExitApp(n)` exits with `n`.
- `/Diag=json` makes every input line produce exactly one JSON result line on stdout —
  the agent-friendly wire format:

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
[2026-05-13 21:35:14] [START] pid=12345 ahk=2.1-alpha.31+Console script=C:\app\app.ahk ...
[2026-05-13 21:43:22] [ERROR] pid=12345 type=TypeError mode=Exit
  Message: This value of type "String" has no method named "DoStuff".
  File: C:\app\Lib\Clip.ahk
  Line: 142
  Stack:
    C:\app\Lib\Clip.ahk (142) : [Clip.Foo]
    > Auto-execute
[2026-05-13 21:43:22] [EXIT] pid=12345 code=10 reason=Error
```

Event types, reason names, `OnError` interaction, and limitations: [`updates.md` §4](updates.md).

---

## AI-assisted debugging

The fork preserves AutoHotkey's DBGp debugger and pairs it with an MCP server
([`debugger-tool/mcp-server/`](debugger-tool/mcp-server/)) that exposes it to LLM tools such as
Claude Code and Cursor. Combined with the structured errors above, this closes a tight loop:

```
run script → capture structured error → inspect source / variables → apply fix → re-run
```

The MCP server speaks DBGp on port 9000 and surfaces ~22 tools:

| Group | Tools |
|---|---|
| Execution | `debug_run`, `debug_step_into` / `_over` / `_out`, `debug_stop`, `debug_status` |
| Breakpoints | `breakpoint_set`, `breakpoint_remove`, `breakpoint_list` |
| Inspection | `variables_get`, `evaluate`, `stack_trace`, `watch_add` / `_remove` / `_list` |
| Source intel | `get_source_context`, `source_outline`, `workspace_symbols` |
| Error loop | `capture_error`, `analyze_error`, `apply_fix` |
| Queue | `list_errors`, `clear_errors` |

**Start it** (the server must be listening before the script connects):

```powershell
cd debugger-tool\mcp-server
npm install && npm run build
node build/index.js
```

```powershell
bin\AutoHotkey64.exe /Debug your_script.ahk    # connects to localhost:9000
```

Tool-by-tool usage lives in [`debugger-tool/mcp-server/README.md`](debugger-tool/mcp-server/README.md).

---

## Repository map

| Path | Purpose |
|---|---|
| [`source/`](source/) | AutoHotkey engine source (C++) — fork changes live here |
| [`debugger-tool/mcp-server/`](debugger-tool/mcp-server/) | MCP server bridging LLM tools to AutoHotkey's DBGp debugger |
| [`debugger-tool/ahk-error-agent/`](debugger-tool/ahk-error-agent/) | Headless error-capture and fix-automation agent |
| [`examples/`](examples/) | Runnable feature demos — `alpha21/`, `alpha22/`, plus structs, GUIs, and ANSI showcases |
| `examples/Alpha22_Example.ahk` … `examples/Alpha30_Example.ahk` | Per-version language showcases |
| `tests/` | Test suite for `Eval`, crash logging, and exit codes |
| [`BUILD.md`](BUILD.md) | Build instructions |
| [`updates.md`](updates.md) | Complete fork reference |

---

## Documentation

| Document | Covers |
|---|---|
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
