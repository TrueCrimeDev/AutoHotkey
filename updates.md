# Updates — Fork Changes Reference

This document covers everything added on top of upstream AutoHotkey `v2.1-alpha.31` in this fork. Use it as the entry point for "what's new and how do I use it."

## Overview at a glance

| Feature | Surface | Off-by-default? |
|---|---|---|
| Runtime expression evaluator | `Eval(expr)` BIF | Yes — gated |
| Eval gate (CLI form) | `/Eval` flag | n/a |
| Eval gate (script form) | `#EnableEval` directive | n/a |
| Println-style stdout helper | `Print(text)` BIF | Always on |
| Console mirror of main-window views | `KeyHistory()`/`ListLines()`/`ListVars()`/`ListHotkeys()` print to stdout when attached | Always on |
| Parse-failure error class | `SyntaxError` (extends `Error`) | Always on |
| Crash logging | `/CrashLog=path` flag | Yes — gated |
| Crash logging (script form) | `#CrashLog path` directive | Yes — gated |
| Stderr file tee | `/StdErrFile=path` flag | Yes — gated |
| Line coverage (LCOV) | `/Coverage=path` flag (see §17) | Yes — gated |
| Live-object inspector | `Inspect(Value, Depth?, MaxItems?)` BIF; REPL object results (see §18) | Always on |
| Native child-process pipes | `ProcessPipe(Command, Args?, WorkingDir?)` class (see §19) | Always on |
| Agent-oriented trace | `/Trace=json` (see §20) | Yes — gated |
| Engine tools in the native MCP server | `check`, `run`, `test` tools of the `mcp` verb (see §21) | n/a |
| External-signal exit code | `code=130` for Ctrl+C / close | Always on (gate is whether crash log is on) |
| Interactive / pipe-driven REPL | `repl` subcommand (see §16) | n/a — explicit mode |

Everything else inherited from `v2.1-alpha.31` works as documented upstream (implicit `export` for names defined inside a `#Module`, tail-call unset propagation, maybe-operator short-circuit, default-unset returns in v2.1 mode, etc. — see `examples/Alpha31_Example.ahk` for a runnable showcase of the alpha.31 changes).

---

## 1. `Eval(expr)` — runtime expression evaluator

Evaluates an AHK expression string against the caller's live scope. Reads and writes caller locals, calls methods, runs alpha.31 expression features (maybe operator, unset propagation) — anything you could type as the right-hand side of `x := ...` works inside `Eval(...)`.

### Quick example

```ahk
#Requires AutoHotkey v2.1-alpha.29
#EnableEval

x := 10
y := 20

MsgBox Eval("x + y")              ; -> 30
Eval("x := x + 1")                ; mutates caller's x
MsgBox x                          ; -> 11
MsgBox Eval("[1,2,3].Map(n => n*n).Reduce((a,b) => a+b, 0)")  ; -> 14
```

### Signature

```
result := Eval(Expression)
```

- `Expression` (String) — any AHK expression. Assignments (`:=`, `+=`, etc.) are valid expressions.
- Returns the evaluated value. May be `unset` if the expression is unset-valued (e.g., `Eval("[1,,3].RemoveAt(2)")` in v2.1 mode).

### Errors

| When | Class | Notes |
|---|---|---|
| Gate not enabled | `Error` | Message: `"Eval is disabled (add #EnableEval to your script or pass /Eval)"` |
| Input doesn't parse | `SyntaxError` | `.Message` carries the parser's diagnostic; `.File = "Eval"`, `.Line = 0`, `.Column = 0` (column info is best-effort and currently always 0) |
| Identifier missing in caller scope | `UnsetError` | Same as inline code |
| Anything raised by the evaluated expression | unchanged | Propagated as-is |

### Enabling it

Either route works; they're equivalent. Pick whichever fits your workflow.

**CLI flag (for ad-hoc runs, third-party launchers, MCP/DBGp scenarios):**

```bat
bin\AutoHotkey64.exe /Eval script.ahk
```

**Directive (self-documenting; recommended):**

```ahk
#Requires AutoHotkey v2.1-alpha.29
#EnableEval
; ... your script
Eval("anything")
```

Both flip the same internal flag. If both are set, no conflict.

### What it sees

`Eval(...)` resolves identifiers in this order:

1. The caller function's locals and parameters.
2. The caller function's static / closure variables (if any).
3. Globals (including built-ins like `A_AhkVersion`).
4. Throws `UnsetError` if the name is genuinely missing.

It cannot create new locals — that protects you from accidentally polluting the caller's scope with typos.

### Runtime parser repairs (September 2026)

Runtime parsing now checks balanced delimiters before creating functions, restores
existing variable lookup order after failed parses, and resolves references in new
fat-arrow bodies before execution. `Eval("(() => unsetLocal? || 42)()")` now returns
unset, matching the inline expression. This formerly crashing case is tested in
`tests/test_eval.ahk` Section F and `tests/test_console_repl.py`.

### Test coverage

`tests/test_eval.ahk` exercises:
- A: presence (`IsSet(Eval)`, `Eval is Func`)
- B: `SyntaxError` class exists and extends `Error`
- C: arithmetic, string concat, method calls, fat-arrow IIFE
- D: reads caller locals + globals
- E: writes caller locals (`Eval("x := 99")` mutates `x`)
- F: alpha.29 features pass through (maybe operator, unset propagation)
- G: `SyntaxError` with non-empty `Message` and a `Column` property on parse failure
- H: reentrancy (nested `Eval`)

Run it with `bin\AutoHotkey64.exe test tests\test_eval.ahk` (the `#EnableEval` directive at the top of the file enables the BIF; no CLI flag needed).

`tests/test_eval_gated.ahk` confirms the gate is closed by default — calling `Eval(...)` without enabling it throws `"Eval is disabled"`.

---

## 2. `Print(fmt, args*)` — stdout println built-in (variadic, Format-aware)

A no-frills BIF that writes text plus a newline to stdout, UTF-8 encoded. Replaces the common boilerplate of opening `FileOpen("*", "w", "UTF-8")` and calling `.Write(text "`n")`. Since 2026-05-22, `Print` is also variadic and accepts Format-style placeholders directly, so the common `Print(Format("...", x))` idiom collapses to `Print("...", x)`.

### Signature

```
Print()                  ; blank line
Print(Text)              ; write Text as-is (no Format pass)
Print(Fmt, Values*)      ; Format(Fmt, Values*) then write
```

- Zero args: writes a blank line (just `\n`).
- One arg: writes the value plus `\n` as-is — **never goes through `Format`**. Literal `{` and `}` in the string survive (e.g. JSON snippets).
- Two or more args: the first arg is the format string; remaining args are the placeholder values. Internally delegates to the existing `Format` BIF, so all `Format` placeholder syntax works (`{}`, `{1}`, `{:08X}`, `{1:08X}`, `{{`, `}}`, etc.). Returns nothing.

### Examples

```ahk
Print("hello")                        ; hello
Print()                               ; (blank line)

x := 42
y := "world"
Print("x={}, y={}", x, y)             ; x=42, y=world
Print("first {1}, again {1}", "AA")   ; first AA, again AA
Print("0x{:08X}", 0xDEAD)             ; 0x0000DEAD

; Literal braces survive in the single-arg form:
Print("{ok: true}")                   ; {ok: true}

; The old wrapper still works (Print just consumes the formatted string):
Print(Format("x={}", 42))             ; x=42
```

If the process has no console attached (GUI app run from Explorer), the call silently does nothing — no crash, no error.

### Why it exists

The old idiom:

```ahk
stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")
PrintLine("hello")
```

is now:

```ahk
Print("hello")
```

The variadic `Format` dispatch removes the next layer of friction — instead of:

```ahk
Print(Format("processing {} of {} files...", n, total))
```

you write:

```ahk
Print("processing {} of {} files...", n, total)
```

`Print` is always available (no gate, no directive). It does not exist upstream; it's a fork-only addition.

### Console mirror of main-window views

When stdout is attached (console build run from a terminal, or output redirected), the four
main-window view functions write their text to stdout instead of opening the GUI main window:

```ahk
KeyHistory()    ; key history + hook/timer status -> stdout
ListLines()     ; recently executed script lines  -> stdout
ListVars()      ; global/local variables          -> stdout
ListHotkeys()   ; hotkey table                    -> stdout
```

Tab-delimited tables (KeyHistory, ListHotkeys) are expanded to spaces at 8-column stops
so they stay aligned in any viewer (terminals, VS Code's Output panel, log files).
Otherwise the output is the same text the GUI edit control would show. With no console
attached (script launched by double-click), the GUI window opens exactly as upstream.
GUI-originated paths — tray menu, the main window's View menu, Refresh — always use the
window, never the console. Shares `Print`'s UTF-8 stdout writer.

---

## 3. `SyntaxError` — new exception class

A new error type that extends `Error`, registered alongside `ValueError`, `TypeError`, etc. Thrown by `Eval(...)` when the input string fails to parse. Available to scripts that want to throw their own parse-related errors.

### Class hierarchy

```
Error
├── MemoryError
├── OSError
├── SyntaxError      ← new
├── TargetError
├── TimeoutError
├── TypeError
├── UnsetError
│   ├── MemberError
│   │   ├── PropertyError
│   │   └── MethodError
│   └── UnsetItemError
├── ValueError
│   └── IndexError
└── ZeroDivisionError
```

### Properties

On instances thrown by `Eval`:

| Property | Type | Value |
|---|---|---|
| `Message` | String | The parser's diagnostic text |
| `File` | String | `"Eval"` |
| `Line` | Integer | `0` |
| `Column` | Integer | `0` (best-effort placeholder for v1) |

Scripts can also throw their own:

```ahk
throw SyntaxError("custom parse failure", "MyParser", 42)
```

---

## 4. `/CrashLog=` and `#CrashLog` — structured crash logging

Records every notable event in a script's life — startup, errors, parse failures, fatal interpreter crashes, signal-triggered exits — to an append-only text file. Independent of how the script is launched: works even when the launcher discards stderr (VSCode AHK extension, task scheduler, custom runners).

### Enabling it

Either route. Both routes are equivalent and idempotent.

**CLI flag:**

```bat
bin\AutoHotkey64.exe /CrashLog=C:\logs\ahk.log script.ahk
```

**Directive (in the script):**

```ahk
#Requires AutoHotkey v2.1-alpha.29
#CrashLog C:\logs\ahk.log
```

If the directive is supplied, it wins (it runs at script-load time, after CLI parsing).

The parent directory must exist; the file itself is created (or appended to) on first write.

### File format

Append-only, UTF-8, plain text. Each event has a `[YYYY-MM-DD HH:MM:SS] [TAG] key=value …` header line. Multi-line events indent continuation lines two spaces.

### Event types

| Tag | When |
|---|---|
| `[START]` | First write after process launch. Fields: `pid`, `ahk=<version>`, `script=<absolute path>`, `cmdline=<full command line>`. |
| `[PARSE]` | Parse / load-time error, before auto-exec. Fields: `pid`, `file`, `line` plus indented `Message:` line. |
| `[ERROR]` | Uncaught script-level exception after all OnError handlers returned 0 / no handler registered. Fields: `pid`, `type=<ErrorClass>`, `mode=<Exit\|Continue>` plus indented `Message:` / `File:` / `Line:` / `What:` / `Extra:` / `Stack:` lines. |
| `[FATAL]` | Interpreter-level SEH fault caught by `SetUnhandledExceptionFilter`. Fields: `pid`, `code=0x<hex>`, `address=0x<hex>` plus indented `LastFile:` / `LastLine:` / `LastHotkey:` lines (currently empty placeholders — see "Known limitations"). |
| `[EXIT]` | Process termination — written by every exit path. Fields: `pid`, `code`, `reason=<name>`. |

### Reason names in `[EXIT]`

| Reason | Exit code | When |
|---|---|---|
| `Normal` | 0 | Clean exit (`ExitApp`, `ExitApp 0`, fall-through) |
| `ExitApp(n)` | n | Intentional non-zero exit via `ExitApp(n)` for n ∉ {0,10,11,12,13,14,64} |
| `Error` | 10 | Uncaught script exception |
| `Critical` | 11 | Internal/critical error |
| `Fatal` | 11 | SEH unhandled exception |
| `Parse` | 12 | Parse / load failure |
| `Check` | 13 | `check` subcommand verdict |
| `Test` | 14 | `test` subcommand verdict |
| `Usage` | 64 | CLI usage error |
| `ExternalSignal` | 130 | Ctrl+C / Ctrl+Break / console close / logoff / shutdown |

`Fatal` and `Critical` share code 11; the reason names disambiguate.

### Example log

```
[2026-05-13 21:35:14] [START] pid=12345 ahk=2.1-alpha.31+Console script=C:\Users\me\app.ahk cmdline="bin\AutoHotkey64.exe /CrashLog=C:\logs\ahk.log app.ahk"
[2026-05-13 21:43:22] [ERROR] pid=12345 type=TypeError mode=Exit
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

### How records persist through crashes

Every record is written as **open-write-flush-close** — the file handle is never held open between events. A `FlushFileBuffers` follows every write. This means: even if the next event is a fatal interpreter crash that corrupts buffered state, the previous records are already safely on disk.

### Threading

All log writes go through one process-global `CRITICAL_SECTION`. Hook threads, the main thread, and the SEH/console-signal callbacks all serialize through the same lock.

### OnError integration

`[ERROR]` records are written **only when the exception escapes all OnError handlers**. If any OnError handler returns `1` (consume), no `[ERROR]` is written.

```ahk
#CrashLog C:\logs\ahk.log
OnError((e, mode) => 1)   ; consume → no [ERROR] record
throw Error("silenced")
```

```ahk
#CrashLog C:\logs\ahk.log
OnError((e, mode) => 0)   ; let propagate → [ERROR] written
throw Error("logged")
```

This is intentional: scripts that have their own error-handling discipline shouldn't double-log.

### Known v1 limitations

- `[FATAL]`'s `LastFile` / `LastLine` / `LastHotkey` fields are placeholder empty strings. Pulling them safely from globals inside an SEH filter requires more plumbing than v1 included. The exception code and address are accurate.
- The SEH filter can be deadlocked if the main thread crashes while holding the crash-log lock. Extremely rare in practice; documented in the source for a future hardening.
- Other Windows components (Visual C++ runtime, WER, debuggers) can install their own unhandled-exception filter that supersedes ours. If that happens, our `[FATAL]` won't fire. No workaround from user space.
- `/CrashLog=` paths are resolved relative to the working directory. Use absolute paths for predictable behaviour across launchers.

---

## 5. `/StdErrFile=` — duplicate stderr to a file

When the script writes anything to stderr (via the existing `/ErrorStdOut` path), the same bytes are also appended to the file at the supplied path. Composes with `/ErrorStdOut[=encoding]`.

### Usage

```bat
bin\AutoHotkey64.exe /ErrorStdOut /StdErrFile=C:\logs\ahk.stderr script.ahk
```

The file gets the same byte-for-byte content the terminal's stderr would have received. If `/ErrorStdOut` is not set, this fork's headless paths still emit stderr, so the file still gets the formatted error output.

There is **no** `#StdErrFile` directive in v1 — stderr redirection is fundamentally a launcher concern; if the script could opt itself in, log-and-relaunch would be required to capture stderr from before the directive was parsed.

---

## 6. Console signal handling — exit code 130

`SetConsoleCtrlHandler` is installed at startup. On `CTRL_C_EVENT`, `CTRL_BREAK_EVENT`, `CTRL_CLOSE_EVENT`, `CTRL_LOGOFF_EVENT`, `CTRL_SHUTDOWN_EVENT`, the handler:

1. Writes `[EXIT] code=130 reason=ExternalSignal` to the crash log (if enabled).
2. Returns `FALSE` so the OS proceeds with its default action (process termination).

This means Ctrl+C in a launching terminal correctly distinguishes "user killed it" from "script exited normally" in the log.

Interaction with `OnExit` script callbacks: the console handler runs on a separate OS thread. The script's main thread may or may not get a chance to run `OnExit` depending on the signal type (CTRL_C is more lenient; CLOSE/LOGOFF/SHUTDOWN terminate aggressively). The crash log entry is written from the handler thread, so it's guaranteed regardless.

---

## 7. Exit code reference (combined)

Existing exit-code taxonomy is preserved unchanged from the fork's prior behaviour. The new code is `130` for external signals.

| Code | Meaning | Crash log `reason=` |
|---|---|---|
| `0` | Success | `Normal` |
| `1`–`9`, `15`–`63`, `65`–`129`, `131`–`255` | `ExitApp(n)` with non-reserved n | `ExitApp(n)` |
| `10` | Uncaught script-level exception | `Error` |
| `11` | Internal/critical error OR SEH fault | `Critical` or `Fatal` |
| `12` | Parse / load failure | `Parse` |
| `13` | `check` subcommand failed | `Check` |
| `14` | `test` subcommand failed | `Test` |
| `64` | CLI usage error | `Usage` |
| `130` | Ctrl+C / Ctrl+Break / console close / logoff / shutdown | `ExternalSignal` |

---

## 8. CLI flag reference (fork-added flags)

All flags in this list are fork-only additions. Existing AHK flags (`/ErrorStdOut`, `/Headless`, `/Check`, `/Test`, `/Debug`, etc.) still work as documented.

| Flag | Effect |
|---|---|
| `/Eval` (or `--eval`) | Enable the `Eval(...)` BIF for the process. Off by default. |
| `/CrashLog=<path>` (or `--crashlog=<path>`) | Enable structured crash logging to `<path>`. Off by default. |
| `/StdErrFile=<path>` (or `--stderrfile=<path>`) | Duplicate all stderr writes to `<path>`. Off by default. |
| `/Coverage=<path>` (or `--coverage=<path>`) | Write an LCOV line-coverage report for every loaded script file to `<path>` at exit (§17). Off by default. |
| `/Trace=json` (or `--trace=json`) | Like `/Trace`, but one JSON event per executed statement (§20). `/Trace=text` is the default text form. |

---

## 9. Script directive reference (fork-added directives)

| Directive | Effect |
|---|---|
| `#EnableEval` | Enable the `Eval(...)` BIF for this script. Same effect as the `/Eval` flag. |
| `#CrashLog <path>` | Enable structured crash logging to `<path>` for this script. Same effect as `/CrashLog=<path>`. Quoted paths are accepted. |

Both directives must appear at top-of-script scope, alongside `#Requires`, `#SingleInstance`, etc.

---

## 10. Built-in function reference (fork-added BIFs)

| Function | Signature | Effect |
|---|---|---|
| `Eval` | `Eval(Expression)` | Evaluate an AHK expression string in the caller's scope. Gated. |
| `Print` | `Print()` / `Print(Text)` / `Print(Fmt, Values*)` | Write text plus a newline to stdout, UTF-8. 2+ args dispatch through `Format(Fmt, Values*)`; 1 arg is written as-is so literal `{` / `}` survive. Always on. |
| `_ScriptGetLines` | `_ScriptGetLines(File, Line, Range?)` | (Pre-existing fork addition.) Read source-text lines around a given position. |
| `Inspect` | `Inspect(Value, Depth := 2, MaxItems := 100)` | JSON description of a live value: own values, getter/setter/method names, items, entries. Never invokes script. §18. |
| `ProcessPipe` | `ProcessPipe(Command, Args?, WorkingDir?)` | Child process with UTF-8 stdio pipes in a job object. §19. |

---

## 11. Tests in this repo

All tests live under `tests/`. Run any of them with:

```bat
bin\AutoHotkey64.exe test tests\<script>.ahk
```

(Exit 0 = pass, exit 14 = fail.)

| Test | Covers |
|---|---|
| `tests/test_eval.ahk` | `Eval` BIF: A–H sections (presence, SyntaxError class, basic expressions, scope read/write, alpha.29 passthrough, SyntaxError column, reentrancy). Uses `#EnableEval`. |
| `tests/test_eval_gated.ahk` | `Eval` BIF disabled-message when no gate is set. |
| `tests/test_crashlog_start_exit.ahk` | Clean run produces `[START]` + `[EXIT] reason=Normal`. |
| `tests/test_crashlog_error.ahk` | Uncaught throw produces `[ERROR]` + `[EXIT] reason=Error`. |
| `tests/test_crashlog_onerror_consumes.ahk` | OnError returning 1 silences `[ERROR]`. |
| `tests/test_crashlog_parse.ahk` | Deliberate syntax error → `[PARSE]` + `[EXIT] reason=Parse`. |
| `tests/test_crashlog_stderrfile.ahk` | `/StdErrFile` mirrors stderr to disk. |
| `tests/test_crashlog_directive.ahk` | `#CrashLog` directive works without CLI flag. |
| `tests/test_crashlog_exitapp_n.ahk` | `ExitApp 7` → `[EXIT] code=7 reason=ExitApp(7)`. |
| `tests/crashlog_check.ahk` | Verifier harness: asserts a log file contains given substrings. |
| `tests/run.ahk` | Single-process suite: `#Include`s every `tests/*.test.ahk` (framework in `tests/Test.ahk`), prints results, exits 14 on failure. Run with `test`; add `/Coverage=` for LCOV. |
| `qa/tests/test_inspect.ahk` | `Inspect`: primitives, depth/MaxItems clamps, arrays/maps/JSON.Object, class getters and methods, native Gui controls, cycles, 60-deep chains, 500-property objects. |
| `qa/tests/test_processpipe.ahk` | `ProcessPipe`: UTF-8 round trip, timeouts, Kill, stderr separation, 2 MB producer without deadlock, 200 KB line across chunk boundaries, argument quoting, kill-on-release, error paths. |
| `tests/test_console_coverage.py` | `/Coverage=`: DA/LF/LH consistency, structural lines excluded, per-iteration `while` counts, relative path resolution, report survives uncaught errors and `ExitApp(14)`. |
| `tests/test_repl.sh` | `repl` subcommand end-to-end (bash; pipes stdin): values, cross-line state, error resilience, JSON mode, `ExitApp` passthrough, script-hosted session. |
| `tests/manual_*.ahk` | Manual verification scripts (SEH, recursion, long-running for Ctrl+C). Not run automatically. |

The Alpha22-29 feature showcases under `examples/` (`examples/Alpha22_Example.ahk` through `examples/Alpha29_Example.ahk`) exercise upstream alpha features and are unaffected by the fork-only additions.

---

## 12. Build paths

Two build systems coexist; both produce `bin/AutoHotkey64.exe`. **GCC (mingw-w64) is the canonical compiler**; MSVC remains available and still produces the CI release binary.

### GCC / mingw-w64 (canonical)

```bash
# from the repo root (WSL or a Windows shell):
cmd.exe /c build.bat                 # append `clean` to force a fresh configure
```

`build.bat` drives MSYS2's mingw-w64 toolchain through CMake — Ninja when present, otherwise MinGW Makefiles — and writes `bin/AutoHotkey64.exe`; the build tree lives in `build_gcc/`. Requires MSYS2 with:

```
pacman -S mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja
```

Set `MSYS2_ROOT` if MSYS2 isn't at `C:\msys64`. The `build-mingw` job in `.github/workflows/build.yml` builds this route in CI on every push. Statically linked (~3.2 MB). Some MSVC-only constructs are guarded with `#ifdef _MSC_VER`:

- `__try`/`__except` SEH around the crash-log filter's defensive guard (mingw GCC doesn't support that syntax — bare filter still works, just without the inner reentrancy catch).
- Various goto-init-crossing block wraps and `std::nullptr_t` qualifications throughout `source/` (mingw GCC is stricter than MSVC).
- ASM stubs (`x64call.asm` / `x64stub.asm`) have GAS-syntax twins (`x64call.s` / `x64stub.s`) for the mingw build.

### MSVC (alternative)

```bat
build_local.bat
```

Uses Visual Studio BuildTools (VS18 / VS2022) → `AutoHotkeyx.sln` / `AutoHotkeyx.vcxproj`. Smaller binary (~1.3 MB) with full SEH crash-log fidelity; this is what the CI `release` job ships. The `Config.vcxproj` includes `/Zc:preprocessor` (required by `__VA_OPT__` in `script_func_impl.h`).

---

## 13. Quick recipes

### Headless script with crash logging and stderr capture

```bat
bin\AutoHotkey64.exe ^
    /Headless ^
    /ErrorStdOut ^
    /CrashLog=C:\logs\ahk.log ^
    /StdErrFile=C:\logs\ahk.stderr ^
    your_script.ahk
```

### Self-contained script that logs everything

```ahk
#Requires AutoHotkey v2.1-alpha.29
#CrashLog C:\logs\ahk.log
#EnableEval

; Now Eval() works and any uncaught error lands in C:\logs\ahk.log.
result := Eval("1 + 2")
Print "result is " . result
```

### Interactive REPL (manual session)

```ahk
#Requires AutoHotkey v2.1-alpha.29
#EnableEval

Loop {
    line := InputBox("expr>", "REPL")
    if line.Result != "OK"
        break
    try
        Print line.Value " = " (Eval(line.Value) ?? "<unset>")
    catch SyntaxError as e
        Print "syntax error: " e.Message
    catch as e
        Print e.__Class ": " e.Message
}
```

### Diagnose a script that mysteriously exits with code 10 in production

Add to the top of the script:

```ahk
#CrashLog C:\ProgramData\YourApp\ahk-crash.log
```

Inspect the log file after the next crash. The `[ERROR]` record will tell you the type, message, file, line, what, extra, and stack.

---

## 14. What's NOT in v1

These are reasonable next steps but were intentionally left out to keep v1 focused:

- Log rotation / size limits
- JSON output format option for the crash log
- Network / syslog destinations
- Stdout capture (only stderr is mirrored)
- `#StdErrFile` directive
- Runtime API: a writable `A_CrashLogPath` so scripts can change the path mid-run
- Separating `Critical` vs `Fatal` into distinct exit codes
- Customizable timestamp format / timezone
- Compression / encryption
- An `Exec(stmts)` BIF for multi-statement evaluation (currently `Eval` is single-expression only)
- Postfix cache for hot `Eval` paths
- Wiring the MCP debugger's `evaluate` tool to use `Eval` instead of DBGp's eval
- Filling `[FATAL]`'s `LastFile` / `LastLine` / `LastHotkey` placeholders with safe accessors

If any of these matter, they're all single-purpose follow-up tasks rather than v1 redesigns.

---

## 15. Where this is documented in the repo

- **Specs** — `docs/superpowers/specs/2026-05-12-eval-builtin-design.md`, `docs/superpowers/specs/2026-05-13-crashlog-design.md`, `docs/superpowers/specs/2026-06-12-repl-mode-design.md`
- **Plans** — `docs/superpowers/plans/2026-05-12-eval-builtin.md`, `docs/superpowers/plans/2026-05-13-crashlog.md`
- **CLAUDE.md** — high-level project orientation
- **README.md** — top-level fork overview
- **examples/Alpha29_Example.ahk** — runnable showcase of upstream alpha.29 features

The specs are the authoritative reference for design decisions; the plans break the work into TDD tasks; this `updates.md` is the user-facing summary.

---

## 16. `repl` subcommand — interactive / pipe-driven eval session

A read-eval-print loop built on the `Eval` machinery (§1). One process holds live
interpreter state: evaluate expressions in milliseconds, build and poke GUIs
interactively, and drive it all from a terminal or an agent's stdin pipe.

```bat
bin\AutoHotkey64.exe repl                       :: bare session (synthetic empty script)
bin\AutoHotkey64.exe repl script.ahk            :: load script, run auto-execute, then REPL
bin\AutoHotkey64.exe repl /Diag=json script.ahk :: JSON result lines on stdout
```

### Semantics

- Global flags can appear before or after `repl` (also `check`, `test`, and `mcp`),
  before the optional script. Arguments after the script remain script arguments.
- One expression per line; comma compounds work (`x := 1, y := 2`). Expressions are
  evaluated in **global scope**, so the loaded script's globals, functions and classes
  are all reachable.
- The session starts **after** the auto-execute section finishes. Hotkeys, timers and
  GUI events keep firing between (and during) evaluations — each line runs as a normal
  pseudo-thread.
- `Eval()` is implicitly enabled (`g_AllowEval`), `#SingleInstance` is forced off, and
  the script is treated as persistent for the lifetime of the session.
- Recoverable errors do not end the session. The REPL acts as an implicit try/catch: parse
  errors and runtime errors print one line and the loop continues, with prior state
  intact. (`SyntaxError: Missing operand.` on stderr in text mode.)
- EOF or `.exit` → clean exit `0`. `ExitApp(n)` typed into the session exits with `n`.
- Interactive text consoles get a banner and a `>>> ` prompt; piped stdin and JSON
  mode get neither. An initial UTF-8 BOM is accepted; malformed UTF-8 input yields
  an error result and leaves the next input available.
- Meta-commands: `.exit`, `.help`.

### Output

Text mode: the expression's value prints to stdout; void/unset results print an empty line;
objects print as `<ClassName object>`; errors print one line to stderr.

JSON mode (`/Diag=json`): one stdout result per input line, including blank lines,
`.help`, and `.exit`. Ordinary script stdout is redirected to stderr before the
host script loads; this covers `Print`, `FileAppend`, and `FileOpen`. Results are
ordered with input and use dynamic, length-aware serialization. Explicit
`ExitApp` or a fatal process failure may terminate before a result can be emitted.

```json
{"kind":"result","ok":true,"type":"Integer","value":"42"}
{"kind":"result","ok":false,"type":"SyntaxError","value":"Missing operand."}
{"kind":"result","ok":true,"type":"Unset","value":""}
```

### Example session

```text
>>> x := 10
10
>>> x * 4
40
>>> g := Gui("+AlwaysOnTop", "Live"), g.Show("w200 h80")
>>> g.BackColor := 0x202020
2105376
>>> .exit
```

### v1 limitations

- Single-line expressions only (no multi-line blocks; use commas or load a script).
- No `ToString` dispatch for object results (`<Array object>`, not contents).
- Scratch expression allocations remain in the process heap until exit; very long
  sessions and oversized expressions still need a separate resource-use review.

Implementation: `source/error.cpp` (reader thread, mailbox, `ReplDrainInput`,
`EvalCore` shared with the `Eval` BIF), dispatch via `AHK_REPL_INPUT` in
`MainWindowProc`. Design: `docs/superpowers/specs/2026-06-12-repl-mode-design.md`.
Tests: `tests/test_repl.sh`, `tests/test_console_repl.py`. Run the aggregate checks
with `python tests/run_console_gate.py bin/AutoHotkey64.exe`.

---

## 17. `/Coverage=` — LCOV line coverage from the interpreter

Zero script instrumentation: the parser already knows every executable line
(that is "lines found") and the interpreter already passes every line through
one dispatch point before executing it (that is "lines hit"). `/Coverage=`
connects the two and writes a standard LCOV tracefile at exit.

### Enabling it

```bat
bin\AutoHotkey64.exe /Headless /Coverage=coverage\tests.lcov test tests\run.ahk
```

`--coverage=<path>` is accepted too. A relative path is resolved against the
working directory at launch, before the script can `SetWorkingDir`. When the
flag is absent the per-line cost is one predictable branch on a global bool.

### File format

One record per source file that contributed at least one executable line
(the main script, every `#Include`, every `#Module` file):

```text
SF:C:\lib\Async.ahk
DA:12,1
DA:13,0
LF:2
LH:1
end_of_record
```

- `DA:<line>,<hits>` — one entry per executable source line. A line holding
  several statements (`if x {`) is one entry.
- Lines that never reach the dispatch point are not reported at all, so they
  cannot drag the number down: `else`, `catch`, `finally`, `case`, bare braces,
  function and class headers, and the loader's synthetic end-of-module line.
- `while` and `until` count once per condition evaluation; loop bodies count
  once per iteration.
- `LF`/`LH` are the found/hit totals for that file.

### When it is written

The whole file is rewritten (open-write-flush-close, like the crash log) at
every exit path: normal end of script, `ExitApp(n)`, uncaught error (exit 10),
test failure (exit 14), the SEH fatal filter (exit 11) and Ctrl+C / console
close (exit 130). A test that crashes still leaves the data gathered up to
that point. A parse failure writes nothing, because nothing ran.

### Merging and reporting

`tools/lcov_summary.py` sums `DA` records across any number of tracefiles,
prints a per-file table, writes a merged tracefile, and emits a shields.io
endpoint JSON badge:

```bat
python tools\lcov_summary.py "coverage/**/*.lcov" --include "^Lib/" --out coverage\merged.lcov --badge coverage\badge.json
```

`qa/run.ahk` launches one process per test; set `AHK_QA_COVERAGE_DIR=<dir>`
and every child writes its own `<test>_<pid>_<n>.lcov` there for the merge.
Any LCOV consumer (Codecov, `genhtml`, VS Code Coverage Gutters) reads the
files directly.

### Not covered (by design)

- Branch (`BRDA`) and function (`FN`/`FNDA`) records.
- Lines executed by `Eval()` — they have no source line.
- A `#Coverage` directive; the flag is a launcher concern like `/Debug`.

---

## 18. `Inspect(Value, Depth := 2, MaxItems := 100)` — live-object inspector

Returns a JSON string describing a value the way a debugger's variable pane
would, without running any script code. The same serializer describes object
results in the REPL (`repl` prints `{"type":"Gui.Button",...}` instead of
`<Gui.Button object>`).

```autohotkey
g := Gui()
btn := g.AddButton("w200", "Save")
Print(Inspect(btn, 1))
```

```json
{"type":"Gui.Button","properties":{},"getters":["Text","Type","Enabled","Visible",...],
 "setters":["Text","Enabled","Visible",...],"methods":["Focus","Move","OnEvent",...]}
```

### Shape

| Key | Present for | Meaning |
|---|---|---|
| `type` | everything | `Type(Value)` |
| `value`, `length` | primitives at top level | the value; `length` for strings |
| `properties` | any object | own **value** properties, serialized |
| `getters` / `setters` / `methods` | any object | names of dynamic members, own and inherited up to (excluding) `Object.Prototype` |
| `typed` | struct-like objects | names of typed fields (values need a read, so they are listed only) |
| `class` | class objects | the class name (`Widget`), static values appear under `properties` |
| `length`, `items` | `Array` | `null` for holes |
| `count`, `entries` | `Map`, `JSON.Object` | `[key, value]` pairs in stored order (keys of any type) |
| `name`, `minParams`, `maxParams`, `variadic` | `Func` | signature |
| `truncated` | any node | `Depth` exhausted at this node, or a list was cut at `MaxItems` |
| `circular` | any node | this object is already open further up |

Nested primitives are inlined as JSON values; nested objects are descriptors.
`Depth` is clamped to 0…32 and `MaxItems` to ≥ 1. Getters are never evaluated:
evaluating one could run arbitrary script, so a value that only exists behind a
getter appears by name only. Read it explicitly if you need it.

---

## 19. `ProcessPipe(Command, Args?, WorkingDir?)` — native child-process pipes

A child process with UTF-8 `stdin`/`stdout`/`stderr` pipes, no console window,
and a job object with kill-on-close: releasing the object or calling `Kill()`
terminates the child and everything it spawned.

```autohotkey
p := ProcessPipe("codex", ["app-server"])
p.SendLine(JSON.Stringify({method: "initialize", id: 1, params: {}}))
reply := JSON.Parse(p.ReadLine(30))      ; seconds; throws TimeoutError
p.Close()                                ; EOF to the child
Print("exit {}", p.Wait(5))
```

| Member | Effect |
|---|---|
| `ProcessPipe(Command, Args?, WorkingDir?)` | `Args` is an Array (each item quoted for `CommandLineToArgvW`), a raw string appended verbatim, or omitted (`Command` is the full command line). Throws `OSError` if the process cannot start. |
| `Send(Text, Timeout?)` / `SendLine(Text, Timeout?)` | Write UTF-8 to stdin; `SendLine` appends `\n`. The write is overlapped and the child's output keeps being drained while it is pending, so a child busy writing cannot deadlock the script. `TimeoutError` after `Timeout` seconds (omitted = wait); the child may have received a prefix. |
| `ReadLine(Timeout?)` | Next stdout line without its line ending. Waits up to `Timeout` seconds (omitted = until data or exit); `TimeoutError` on expiry; `""` at EOF (check `AtEOF`). |
| `Read(Timeout?)` | Everything buffered on stdout. Without `Timeout` it returns immediately (possibly `""`); with one it waits for at least one character. |
| `ReadStdErr()` | Everything buffered on stderr, then clears it. |
| `Wait(Timeout?)` | Blocks until exit; returns the exit code; `TimeoutError` on expiry. |
| `Close()` | Closes stdin so a child reading to EOF finishes. |
| `Kill()` | Terminates the job (process tree). |
| `PID`, `Running`, `ExitCode` (`-1` while running), `AtEOF` | State. |

While waiting, the script's timers, hotkeys and GUI events keep running
(`MsgSleep`, like `WinWait`). Both pipes are drained during every wait and
during every pending write, so a child that floods stderr cannot deadlock a
`ReadLine` on stdout and a child that floods stdout cannot deadlock a `Send`.
Pipe buffers are 1 MB; a busy child is drained continuously. Incomplete UTF-8
sequences at a chunk boundary are held until the next read.

`File.AtEOF` is unreliable on a pipe inside the *child* (it reports true while
the pipe is momentarily empty). A child reading its stdin to the end should
loop on `ReadLine()` until it returns `""`.

---

## 20. `/Trace=json` — statement events for agents

`/Trace` keeps its text form. `/Trace=json` emits one object per executed
statement on stderr, ready for a harness to consume alongside `/Diag=json`:

```json
{"event":"statement","file":"C:\\app\\App.ahk","line":27,"function":"SaveRecord","thread":1,"text":"recordCount += 1"}
```

`function` is empty at top level; `thread` is the count of pseudo-threads
alive when the statement ran (1 = auto-execute, more inside hotkeys/timers).
Unknown formats exit 64.

---

## 21. Native MCP tools: `check`, `run`, `test`

`AutoHotkey64.exe mcp` now covers the whole check / run / test loop without a
Node or Python bridge. Each tool spawns this same executable in a child
process (`/Headless /Diag=json`), captures both streams, and returns every
stderr line that parses as a diagnostic:

| Tool | Arguments | Result |
|---|---|---|
| `check` | `file`, `cwd?`, `timeout_ms?` | `ok`, `exitCode` (0/13), `diagnostics[]`, `stdout`, `stderr` |
| `run` | `file`, `args?[]`, `cwd?`, `timeout_ms?` | same plus `timedOut`; the process tree is killed at `timeout_ms` (default 30000, max 600000) |
| `test` | as `run` | `exitCode` 0 pass / 14 fail |

`diagnostics[]` items are the engine's schema-2 diagnostic objects (`type`,
`message`, `file`, `line`, `column`, `stack`, …). A persistent script under
`run` is reported with `timedOut: true` rather than hanging the server.
