# REPL Mode (`repl` subcommand) — Design

**Goal:** An interactive / pipe-driven read-eval-print loop built into the binary, so an
agent (or a human in a terminal) can hold a *persistent* interpreter session instead of
paying a full process spawn per expression. Builds directly on the existing `Eval` BIF
machinery.

```text
AutoHotkey64.exe repl                       # bare session (synthetic empty script)
AutoHotkey64.exe repl script.ahk            # load script, run auto-execute, then REPL
AutoHotkey64.exe repl /Diag=json script.ahk # JSON results on stdout, JSON errors on stderr
```

## Why in the binary

- `Eval()` already evaluates expressions against live scope at runtime; the REPL is a
  driver loop around it.
- A live session means: millisecond evaluation, persistent state, interactive GUI
  poking (`g.BackColor := 0x202020` while the window is visible), hot re-assignment of
  functions/vars — none of which a spawn-per-expression model can do.
- The MCP server / agent tooling gets a structured, line-oriented protocol with zero
  extra dependencies.

## Semantics

| Aspect | Behavior |
|---|---|
| Invocation | `repl` as argv[1] (same slot as `check` / `test`); flags and optional script follow |
| Script arg | Optional. Absent → synthetic empty in-memory script (`*REPL` spec via `TextMem`) |
| Start | REPL loop begins **after** the auto-execute section completes |
| Input | One expression per line on stdin. Compound expressions via commas work (`x := 1, y := 2`) |
| Eval scope | Global scope (`aScope = nullptr` → same resolution as auto-execute) |
| Output | Result of each expression printed to stdout; void/unset results print nothing (text mode) |
| Errors | Standard fork error path: text or JSON on **stderr**; the session continues |
| `Eval()` gate | `repl` implies `g_AllowEval = true` |
| Persistence | `mReplMode` forces `IsPersistent()` true |
| EOF / `.exit` | Clean `ExitApp` → exit code 0 |
| `ExitApp(n)` typed in session | Exits with `n` (normal semantics) |
| #SingleInstance | Forced OFF in repl mode (parallel sessions are expected) |
| Errors don't taint exit code | A failed line must not turn a later clean exit into code 10 |

### Interactive vs piped

Detected once via `GetFileType(GetStdHandle(STD_INPUT_HANDLE)) == FILE_TYPE_CHAR`.

- **Interactive (console):** banner (`AutoHotkey v2.1-alpha.30+Console REPL — .help for commands`),
  `>>> ` prompt before each line, `ReadConsoleW` for proper Unicode input.
- **Piped (agent):** no banner, no prompt, stdin read as UTF-8 bytes (`ReadFile` + growing
  buffer until `\n`). Output is exactly one result line per input line in JSON mode.

### Text mode output

```text
>>> x := 42
42
>>> x * 2
84
>>> SetTimer(() => 0, 0)
>>> StrSplit("a,b,c", ",")
<Array object>
>>> 1 +
stderr: SyntaxError: ... (session continues)
```

- Strings/numbers: printed verbatim (same stringification as `Print`).
- Objects: `<ClassName object>` (v1 — no ToString dispatch).
- unset / void: nothing printed.

### JSON mode (`/Diag=json`)

stdout, one line per input line — pairs 1:1 with requests:

```json
{"kind":"result","ok":true,"type":"Integer","value":"84"}
{"kind":"result","ok":false,"type":"SyntaxError","value":"Missing operand"}
```

In JSON mode the `ok:false` result line **is** the error report — nothing extra goes
to stderr — so a stdout-only consumer pairs requests and responses 1:1. In text mode
errors print as a one-liner (`SyntaxError: Missing operand.`) on stderr.

### Meta-commands (text mode)

| Command | Action |
|---|---|
| `.exit` | `ExitApp` (code 0) |
| `.help` | one-line command summary |

Anything else starting with `.` is evaluated as an expression (errors naturally).

## Architecture

### Reader thread (lockstep)

A dedicated thread does blocking stdin reads. Per line:

1. heap-dup the line → `PostMessage(g_hWnd, AHK_REPL_INPUT, 0, (LPARAM)str)`
2. `WaitForSingleObject(g_ReplLineDone, INFINITE)` — main thread signals after the line
   is fully processed (result printed)

Lockstep guarantees ordering, gives natural backpressure, and keeps the message queue
bounded. EOF posts `AHK_REPL_INPUT` with `lParam = 0`.

### Main-thread dispatch

`AHK_REPL_INPUT` appended to the `UserMessages` enum (end of first group, before the
`= WM_USER+20` jump). Handled in `MainWindowProc` using the proven `MsgMonitor` /
`AHK_HOT_IF_EVAL` pattern:

```cpp
case AHK_REPL_INPUT:
    g_script.ReplExecLine((LPTSTR)lParam);   // frees the string, signals g_ReplLineDone
    return 0;
```

`ReplExecLine` (error.cpp, beside `Eval`):

```cpp
if (!aLine) → ExitApp(EXIT_EXIT)            // EOF
meta-command? → handle, signal, return
if (g_nThreads >= g_MaxThreadsTotal) → print busy diagnostic, signal, return
InitNewThread(0, false, true);
g->ExcptMode = EXCPTMODE_CATCH;                  // implicit try/catch: in console mode an
                                                 // unhandled error would report-and-exit
FResult fr = EvalCore(aLine, nullptr, result);   // factored core of BIF Eval
g->ExcptMode = EXCPTMODE_NONE;
fr == OK → print result (text or JSON)
else     → extract type/message from g->ThrownToken, print one line, FreeExceptionToken
ResumeUnderlyingThread();
free + SetEvent(g_ReplLineDone)
```

Note: without `EXCPTMODE_CATCH`, `Line::SetThrownToken` and `Script::RuntimeError`
both short-circuit to the report-and-exit path when `mErrorStdOut` is set — the first
bad expression would kill the session with exit 10. Verified empirically.

Because each line runs as a normal pseudo-thread, hotkeys/timers/GUI events interleave
correctly between (and during) evaluations, and a thrown error kills only that line.

### `EvalCore` factoring

`bif_impl Eval` keeps its gate + `g->CurrentFunc` scope resolution and delegates the
body (parse-to-postfix, `ACT_SWITCH` scratch line, `PRIVATIZE_S_DEREF_BUF`,
`ExpandSingleArg`, result transfer, `SyntaxError` conversion) to
`EvalCore(LPCTSTR expr, UserFunc *scope, ResultToken &ret)`. No behavior change for
the BIF.

### Synthetic script (`repl` with no file)

`ParseCmdLineArgs` sets `script_filespec = _T("*REPL")`. `Script::Init` already routes
`*name` → `ScriptKindResource`. `LoadIncludedFile` gets a branch ahead of the resource
lookup: when `mReplMode` and spec == `*REPL`, load a built-in empty script string
through the existing `TextMem` path.

## File map

| File | Change |
|---|---|
| `source/hook.h` | `AHK_REPL_INPUT` added to `UserMessages` (end of first group) |
| `source/script.h` | `bool mReplMode`, `void ReplStart()`, `void ReplExecLine(LPTSTR)` |
| `source/AutoHotkey.cpp` | `repl` subcommand parse; synthetic filespec; `ReplStart()` after auto-exec, before `MsgSleep` |
| `source/script.cpp` | `IsPersistent()` honors `mReplMode`; `*REPL` branch in `LoadIncludedFile` |
| `source/script2.cpp` | `AHK_REPL_INPUT` case in `MainWindowProc` |
| `source/error.cpp` | `EvalCore` factoring; `ReplStart` (banner, console attach, reader thread); `ReplExecLine`; result printer (text+JSON) |
| `tests/test_repl.cmd` | pipe-driven end-to-end test |
| `updates.md`, `README.md` | docs |

No new build files; everything lands in files already compiled.

## Out of scope (v1)

- Multi-line input / block continuation (Eval is expression-only; commas cover most needs)
- `ToString` dispatch for object results
- JSON *input* framing (one expression per line is the protocol)
- Readline-style editing/history (the host terminal provides what it provides)
- `.load` / `.vars` meta-commands
