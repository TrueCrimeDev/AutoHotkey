# Crash Logging — Design

**Status:** draft, awaiting user review
**Date:** 2026-05-13
**Target:** AHK v2.1-alpha.29+Console fork (this repo)
**Scope:** new engine-level crash logger + stderr file mirror. C++ work in `source/`. Ships with `bin/AutoHotkey64.exe`.

## Goal

Make crash records and stderr output persist on disk regardless of how the script is launched, so a launcher that discards stderr (VSCode AHK extension, task scheduler, custom runner) still surfaces what went wrong.

Three surfaces:

1. **`/CrashLog=<path>` CLI flag** and **`#CrashLog <path>` directive** — enable structured crash logging.
2. **`/StdErrFile=<path>` CLI flag** — duplicate every stderr write to a file. Coexists with `/ErrorStdOut[=encoding]`.
3. **Exit code 130 for `ExternalSignal`** — Ctrl+C, console window close, logoff, shutdown.

Existing exit codes (0 / 10 / 11 / 12 / 13 / 14 / 64) are preserved unchanged. The crash log carries semantic reason names in addition, so launchers can match on either.

## Public API

### CLI

```
bin\AutoHotkey64.exe /CrashLog=C:\logs\ahk.log script.ahk
bin\AutoHotkey64.exe /StdErrFile=C:\logs\ahk.stderr script.ahk
bin\AutoHotkey64.exe /CrashLog=C:\logs\ahk.log /StdErrFile=C:\logs\ahk.stderr script.ahk
```

Both flags accept a Windows path. The directory must exist; the file is created (or appended to) on first write.

### Directive

```ahk
#Requires AutoHotkey v2.1-alpha.29
#CrashLog C:\logs\ahk.log
; rest of script
```

`#CrashLog` takes a single bareword path. Quotes are optional. The directive must appear at script-top scope (same level as `#Requires` / `#EnableEval`).

If both `/CrashLog=A` and `#CrashLog B` are supplied, the directive wins (it's evaluated at script load, after CLI parsing). This matches the principle that the script's own declaration is closer to the source of truth than the launcher's flag.

There is intentionally **no** `#StdErrFile` directive in v1 — stderr redirection is fundamentally a launcher concern; if the script could opt itself in, log-and-relaunch would be required to capture stderr from before the directive was parsed. CLI-only is the safer surface.

## File format

Append-only, plain text, UTF-8 with BOM. Each event is one or more lines; the first line of every event is `[YYYY-MM-DD HH:MM:SS] [TAG] key=value …`. Continuation lines (for multi-line ERROR/FATAL details) are indented two spaces.

### Events

| Tag | When | Fields |
|---|---|---|
| `[START]` | First write after process launch | `pid=<n>` `ahk=<version>` `script=<absolute path>` `cmdline=<full cmdline>` |
| `[PARSE]` | Parse / load-time error, before auto-exec | `pid=<n>` `file=<path>` `line=<n>` then indented `Message:` line |
| `[ERROR]` | Uncaught script-level exception (after all OnError handlers returned 0 / none registered) | `pid=<n>` `type=<ErrorClass>` `mode=<ExitApp|Continue>` then indented `Message:` / `File:` / `Line:` / `What:` / `Extra:` / `Stack:` lines |
| `[FATAL]` | SEH unhandled exception caught by `SetUnhandledExceptionFilter` | `pid=<n>` `code=0x<hex>` `address=0x<hex>` then indented `LastFile:` / `LastLine:` / `LastHotkey:` lines (best-effort from globals) |
| `[EXIT]` | Process termination, written by every exit path | `pid=<n>` `code=<n>` `reason=<name>` |

### `reason=` values for `[EXIT]`

| Reason | Exit code | When |
|---|---|---|
| `Normal` | 0 | Script exited normally (auto-exec ran to completion, `ExitApp` with no arg, or `ExitApp 0`) |
| `ExitApp(n)` | n | `ExitApp(n)` with non-zero n; reason carries the literal value, e.g. `ExitApp(7)` |
| `Error` | 10 | Uncaught script-level exception |
| `Critical` | 11 | Critical / internal error |
| `Fatal` | 11 | SEH fault caught by the unhandled-exception filter |
| `Parse` | 12 | Parse / load failure |
| `Check` | 13 | `check` subcommand failed (existing behavior) |
| `Test` | 14 | `test` subcommand failed (existing behavior) |
| `Usage` | 64 | CLI usage error (existing behavior) |
| `ExternalSignal` | 130 | Ctrl+C, Ctrl+Break, console close, logoff, shutdown |

### Example

```
[2026-05-13 21:35:14] [START] pid=12345 ahk=2.1-alpha.29+Console script=C:\Users\me\app.ahk cmdline="bin\AutoHotkey64.exe /CrashLog=C:\logs\ahk.log app.ahk"
[2026-05-13 21:43:22] [ERROR] pid=12345 type=TypeError mode=ExitApp
  Message: This value of type "String" has no method named "DoStuff".
  File: C:\Users\me\Lib\Clip.ahk
  Line: 142
  What: Foo
  Extra: "abc"
  Stack:
    C:\Users\me\Lib\Clip.ahk (142) : [Clip.Foo]
    C:\Users\me\app.ahk (33) : [Clip.StartMonitor]
    > Auto-execute
[2026-05-13 21:43:22] [EXIT] pid=12345 code=10 reason=Error
```

## Architecture

### Lifecycle

```
Process start
   │
   ▼
1. Parse CLI: /CrashLog=, /StdErrFile=     →  g_CrashLogPath, g_StdErrFilePath
2. Install SetUnhandledExceptionFilter     →  catches SEH for [FATAL]
3. Install SetConsoleCtrlHandler           →  catches Ctrl+C/close for [EXIT] reason=ExternalSignal
4. Crash log: emit [START] if g_CrashLogPath set
   │
   ▼
5. Parse the .ahk script. If parse fails:
      crash log → [PARSE] + [EXIT] reason=Parse code=12
      stderr also gets the existing /ErrorStdOut message (which is teed to /StdErrFile if set)
      exit 12
   │
   ▼
6. Auto-exec + main message loop.
      Script runs, hotkeys/timers/threads execute.
      Script-level uncaught errors → ScriptError → OnError dispatch.
         If all handlers returned 0 (or none registered): crash log → [ERROR]
         OnError handlers consume the error (returned 1) → do NOT log [ERROR]
   │
   ▼
7. Exit (one of):
      a) Normal ExitApp(n) / fall-through → crash log → [EXIT] reason=Normal|ExitApp(n) code=n
      b) Uncaught script error → already logged [ERROR], then [EXIT] reason=Error code=10
      c) Parse error path (above) → [EXIT] reason=Parse code=12
      d) SEH fault → SetUnhandledExceptionFilter writes [FATAL] + [EXIT] reason=Fatal code=11, then returns EXCEPTION_CONTINUE_SEARCH
      e) Ctrl+C / console signal → SetConsoleCtrlHandler writes [EXIT] reason=ExternalSignal code=130, returns FALSE
```

### Files

| File | Purpose |
|---|---|
| `source/crashlog.h` (new) | Public interface: `SetCrashLogPath`, `SetStdErrFilePath`, `LogStart`, `LogError`, `LogFatal`, `LogParse`, `LogExit`, `MirrorStderr`. |
| `source/crashlog.cpp` (new) | Implementation. Owns the file-write logic, formatting, threading lock. |
| `source/globaldata.h` / `.cpp` (modify) | Add `g_CrashLogPath`, `g_StdErrFilePath` (both `LPTSTR`, default `nullptr`). |
| `source/AutoHotkey.cpp` (modify) | Parse `/CrashLog=`, `/StdErrFile=`. Install SEH filter + console handler. Emit `[START]`. Wire exit paths to `LogExit`. |
| `source/script.cpp` (modify) | Add `#CrashLog` directive branch in `Script::IsDirective` (calls `SetCrashLogPath`). Add `Script::CrashLogPath()` accessor if needed. |
| `source/error.cpp` (modify) | Hook into the post-OnError chokepoint in `Script::ShowError` to call `LogError` when the error escapes. Hook `PrintErrorStdOut` to also mirror to `g_StdErrFilePath`. |
| `CMakeLists.txt` (modify) | Add `source/crashlog.cpp` to `AHK_SOURCES`. |
| `AutoHotkeyx.vcxproj` (modify) | Add `<ClCompile Include="source\crashlog.cpp" />` and the corresponding header. |

### Threading

Hooks fire on different threads (`g_HookThreadID`). Console handlers fire on a separate thread the OS chose. The SEH filter may fire on any thread. The crash log must therefore be thread-safe.

Approach: a single `CRITICAL_SECTION g_CrashLogLock` initialized at startup. Every public Log* function takes the lock, opens the file, writes the record, flushes, closes, releases the lock. Open-write-close per event is intentional — SEH faults must not lose the previously written records to a dirty buffer.

### File handle strategy

**Open-write-close per event**, not held open. Rationale:
- A fatal fault can corrupt the buffered state of any open `FILE*` or `HANDLE`; subsequent records would be lost.
- Logging frequency is low (a handful of events per process lifetime); the open+close cost is negligible.
- Multiple processes can log to the same path without coordinating handle ownership.

Use `CreateFile` with `OPEN_ALWAYS`, `FILE_APPEND_DATA`, `FILE_SHARE_READ | FILE_SHARE_WRITE`. Each write is one `WriteFile` of the fully-rendered UTF-8 bytes followed by `FlushFileBuffers` and `CloseHandle`. If the directory doesn't exist, the open fails silently and the event is dropped (no recursion into the error path).

### `/StdErrFile=` tee

Single injection point in `source/error.cpp` where the existing `PrintErrorStdOut` (the `**` stream) writes to stderr. Add: if `g_StdErrFilePath` is non-null, also append the same bytes to that file via the same open-write-close pattern (sharing the crash-log lock to keep ordering deterministic).

Coexists with `/ErrorStdOut=utf-8` — the encoding chosen for stderr is mirrored verbatim to the file.

### OnError integration

`Script::ShowError` (in `source/error.cpp`) is the chokepoint after OnError dispatch. The dispatch already records whether any handler returned 1 (consume) vs 0 (let propagate). At the point where `ShowError` decides the script must exit (i.e., the error wasn't consumed):

```cpp
// Existing logic decides aErrorType == FAIL → exit imminent.
// New: if g_CrashLogPath set and error wasn't consumed, log it.
if (CrashLog::IsEnabled() && !error_was_consumed_by_on_error)
    CrashLog::LogError(/* error object, type, file, line, what, extra, stack */);
```

The exact field-extraction logic (calling into `ExprTokenType` / Error-object getters for Message / File / Line / What / Extra / Stack) reuses what the existing `FormatStdErr` does for the `**` stream — same source of truth.

### SEH FATAL capture

Install `SetUnhandledExceptionFilter` very early in `WinMain` (before any AHK init):

```cpp
SetUnhandledExceptionFilter(CrashLog::UnhandledExceptionFilter);
```

The filter:
1. Captures `pExceptionInfo->ExceptionRecord->ExceptionCode` and `ExceptionAddress`.
2. Reads `g_script.mCurrFileIndex` / `mCurrLine->mLineNumber` / `g_script.mThisHotkeyName` (best effort — may be stale or null).
3. Calls `CrashLog::LogFatal(...)` with that context.
4. Calls `CrashLog::LogExit(11, "Fatal")`.
5. Returns `EXCEPTION_CONTINUE_SEARCH` — Windows' default handler still runs (crash dialog or termination).

The filter must be reentrancy-safe: if it itself faults, do nothing (catch via `__try` inside the filter and return immediately).

### Signal handling

Install `SetConsoleCtrlHandler` at the same point as the SEH filter:

```cpp
SetConsoleCtrlHandler(CrashLog::ConsoleCtrlHandler, TRUE);
```

The handler responds to `CTRL_C_EVENT`, `CTRL_BREAK_EVENT`, `CTRL_CLOSE_EVENT`, `CTRL_LOGOFF_EVENT`, `CTRL_SHUTDOWN_EVENT`. For each:

1. `CrashLog::LogExit(130, "ExternalSignal")`.
2. Return `FALSE` so the OS continues with its default action (which is process termination for CLOSE/LOGOFF/SHUTDOWN, and silently for CTRL_C/CTRL_BREAK if subsequent handlers don't claim them).

Interaction with `OnExit` script callbacks: the console handler runs on a separate OS thread before process termination. AHK's existing `OnExit` callback may or may not run depending on the signal type and timing (CTRL_C typically lets the main thread continue briefly; CTRL_CLOSE / LOGOFF / SHUTDOWN terminate aggressively). The crash log entry is written from the handler thread, so it is guaranteed regardless of whether `OnExit` runs. We do not block or coordinate with `OnExit`.

## OnError integration details

The existing post-OnError chokepoint is `Script::ShowError`. After it calls into the OnError dispatch chain (`Object::Invoke` on each handler), it knows whether any handler returned `1`. The crash log call wraps that decision:

- All handlers returned 0 (or none registered) AND error escapes → log [ERROR].
- Any handler returned 1 → script continues; do NOT log.

This means the user can selectively silence the crash log by registering an OnError that catches and returns 1. That's intentional: scripts that have their own error-handling discipline shouldn't double-log.

## /StdErrFile + /ErrorStdOut interaction

These compose:
- `/ErrorStdOut[=encoding]` sets `mErrorStdOut = true` and the codepage.
- `/StdErrFile=path` sets `g_StdErrFilePath`.
- When `mErrorStdOut` writes a byte sequence to stderr, the same byte sequence is appended to `g_StdErrFilePath` if set.

If `/ErrorStdOut` is NOT set, errors go to the default GUI MsgBox (or are suppressed in `/Headless`). In that case, `/StdErrFile` has nothing to mirror — it's a silent no-op. (No warning record; keeping the event vocabulary tight for v1.)

## Exit-code reason mapping (the load-bearing decision)

Existing taxonomy preserved verbatim. The crash log's `reason=` field carries semantic context that pairs with the numeric code:

| Reason | Code | Source |
|---|---|---|
| `Normal` | 0 | `ExitApp` / `ExitApp(0)` / fall-through |
| `ExitApp(n)` | n | `ExitApp(n)` for n in 1..9, 15..63, 65..129, 131..255 (anything not reserved below) |
| `Error` | 10 | Uncaught script exception (post-OnError) |
| `Critical` | 11 | Internal / critical error |
| `Fatal` | 11 | SEH unhandled exception |
| `Parse` | 12 | Parse / load failure |
| `Check` | 13 | `check` subcommand verdict (existing) |
| `Test` | 14 | `test` subcommand verdict (existing) |
| `Usage` | 64 | CLI usage error (existing) |
| `ExternalSignal` | 130 | Ctrl+C / console close / logoff / shutdown |

`Fatal` and `Critical` share code 11. The reason names disambiguate. Future work could split them if launcher demand emerges.

`ExitApp(1)` produces `reason=ExitApp(1) code=1`, distinguishing intentional code-1 exits from `Error` (code 10). This addresses the request's concern about "exit 1 is used for both 'uncaught exception' and 'ExitApp(1) called intentionally'" — the codes are already distinct in this fork (Error is 10, not 1), and the reason name surfaces that explicitly in the crash log.

## What v1 does NOT include

- Log rotation / size limits
- JSON output format option
- Network / syslog destinations
- Stdout capture (only stderr)
- `#StdErrFile` directive (CLI-only by design — see "Directive" section)
- Per-script log paths via runtime API (`SetCrashLogPath` is C++-internal in v1)
- Customizable timestamp format
- Separate logs for hooks vs main thread
- Compression / encryption

All of these are reasonable v2+ extensions; left out for v1 to keep the diff focused and the failure modes few.

## Testing plan

### Headless invocation tests (`tests/test_crashlog_*.ahk`)

| Test | What it asserts |
|---|---|
| `test_crashlog_start_exit.ahk` | Clean script + `/CrashLog=tmp` produces `[START]` + `[EXIT] reason=Normal code=0` |
| `test_crashlog_error.ahk` | `throw Error(...)` with no OnError → `[ERROR]` + `[EXIT] reason=Error code=10` |
| `test_crashlog_onerror_consumes.ahk` | `OnError((e,*) => 1)` consumes the throw → only `[START]` and `[EXIT] reason=Normal code=0`, NO `[ERROR]` |
| `test_crashlog_parse.ahk` | Script with syntax error → `[PARSE]` + `[EXIT] reason=Parse code=12` |
| `test_crashlog_exitapp_n.ahk` | `ExitApp 7` → `[EXIT] reason=ExitApp(7) code=7` |
| `test_crashlog_stderrfile.ahk` | `/ErrorStdOut /StdErrFile=tmp.err` + throw → stderr file contains the same formatted error as stderr would |
| `test_crashlog_directive.ahk` | `#CrashLog tmp.log` at top of script + throw → same `[ERROR]` record without needing CLI flag |

Each test is a small standalone `.ahk` that writes to a temp path, executes the failure scenario, and a harness verifies the resulting log file contains the expected `[TAG]` lines. A simple Python or AHK-driven test runner reads the log files and asserts substrings; exit codes from the AHK runs themselves are also checked.

### Interactive verification (manual)

- `Ctrl+C` while a long-running script is in its message loop → `[EXIT] reason=ExternalSignal code=130`.
- Force-close the console window → same.
- Trigger an access violation via a malformed `DllCall` → `[FATAL] code=0xC0000005 …` + `[EXIT] reason=Fatal code=11`.

(SEH and console signals are hard to test headlessly across CI; manual verification with the dev's console is acceptable for v1.)

### Regression watch

- Existing `tests/test_eval.ahk` / `test_eval_gated.ahk` continue to pass.
- Existing `Alpha22_Example.ahk` through `Alpha29_Example.ahk` continue to run identically.
- `bin\AutoHotkey64.exe check script.ahk` still exits 0/13 as before.
- `bin\AutoHotkey64.exe test script.ahk` still exits 0/14 as before.

## Open questions

None blocking. Anything that surfaces during implementation goes in the implementation plan or a follow-up.

## Future work (post-v1)

- `#StdErrFile` directive (would require log-and-relaunch pattern; non-trivial)
- JSON output format
- Log rotation (size and time-based)
- Runtime API: `A_CrashLogPath` read-write var so scripts can change the path mid-run
- Separate the `Critical` vs `Fatal` exit codes (currently both 11)
- Stdout mirror flag (`/StdOutFile=path`)
- Configurable timestamp format and timezone
- Crash-log replay tool (turns a log file into a readable report)
