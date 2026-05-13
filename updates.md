# Updates — Fork Changes Reference

This document covers everything added on top of upstream AutoHotkey `v2.1-alpha.29` in this fork. Use it as the entry point for "what's new and how do I use it."

## Overview at a glance

| Feature | Surface | Off-by-default? |
|---|---|---|
| Runtime expression evaluator | `Eval(expr)` BIF | Yes — gated |
| Eval gate (CLI form) | `/Eval` flag | n/a |
| Eval gate (script form) | `#EnableEval` directive | n/a |
| Println-style stdout helper | `Print(text)` BIF | Always on |
| Parse-failure error class | `SyntaxError` (extends `Error`) | Always on |
| Crash logging | `/CrashLog=path` flag | Yes — gated |
| Crash logging (script form) | `#CrashLog path` directive | Yes — gated |
| Stderr file tee | `/StdErrFile=path` flag | Yes — gated |
| External-signal exit code | `code=130` for Ctrl+C / close | Always on (gate is whether crash log is on) |

Everything else inherited from `v2.1-alpha.29` works as documented upstream (tail-call unset propagation, maybe-operator short-circuit, default-unset returns in v2.1 mode, etc. — see `Alpha29_Example.ahk` for a runnable showcase).

---

## 1. `Eval(expr)` — runtime expression evaluator

Evaluates an AHK expression string against the caller's live scope. Reads and writes caller locals, calls methods, runs alpha.29 expression features (maybe operator, unset propagation) — anything you could type as the right-hand side of `x := ...` works inside `Eval(...)`.

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

### Known v1 limitation

The combination `Eval("(() => unsetLocal? || 42)()")` (IIFE + maybe-operator + `||`) currently crashes through `Eval` even though the inline form works. The runtime-preparse path doesn't fully replicate the inline alpha.29 path for that specific combo. Documented in `tests/test_eval.ahk` Section F. Won't bite typical use; avoid IIFEs with the maybe operator inside `Eval` for now.

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

## 2. `Print(text)` — stdout println built-in

A no-frills BIF that writes `text` followed by a newline to stdout, UTF-8 encoded. Replaces the common boilerplate of opening `FileOpen("*", "w", "UTF-8")` and calling `.Write(text "`n")`.

### Signature

```
Print(Text := "")
```

- `Text` (String, optional) — defaults to empty. The literal text plus `\n` is written to stdout.
- Returns nothing.

### Examples

```ahk
Print("hello")          ; writes:  hello\n
Print()                 ; writes:  \n  (just a newline)
Print("a" . " " . "b")  ; writes:  a b\n
```

If the process has no console attached (GUI app run from Explorer), the call silently does nothing — no crash, no error.

### Why it exists

The old idiom:

```ahk
stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")
PrintLine "hello"
```

is now:

```ahk
Print "hello"
```

That's it. No setup, no global, no helper definition. Tests and examples are easier to write.

`Print` is always available (no gate, no directive). It does not exist upstream; it's a fork-only addition.

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
[2026-05-13 21:35:14] [START] pid=12345 ahk=2.1-alpha.29+Console script=C:\Users\me\app.ahk cmdline="bin\AutoHotkey64.exe /CrashLog=C:\logs\ahk.log app.ahk"
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
| `Print` | `Print(Text := "")` | Write `Text` plus a newline to stdout, UTF-8. Always on. |
| `_ScriptGetLines` | `_ScriptGetLines(File, Line, Range?)` | (Pre-existing fork addition.) Read source-text lines around a given position. |

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
| `tests/manual_*.ahk` | Manual verification scripts (SEH, recursion, long-running for Ctrl+C). Not run automatically. |

The Alpha22-29 feature showcases at the repo root (`Alpha22_Example.ahk` through `Alpha29_Example.ahk`) exercise upstream alpha features and are unaffected by the fork-only additions.

---

## 12. Build paths

Two build systems coexist; both produce `bin/AutoHotkey64.exe`.

### MSVC (canonical)

```bat
build_local.bat
```

Uses Visual Studio BuildTools (VS18 / VS2022) → `AutoHotkeyx.sln` / `AutoHotkeyx.vcxproj`. Faster build; smaller binary. The `Config.vcxproj` includes `/Zc:preprocessor` (required by `__VA_OPT__` in `script_func_impl.h`).

### mingw (cross-compile from WSL)

```bash
cd build_mingw
cmd.exe /c rebuild.bat
```

Uses MSYS2 mingw-w64 via CMake. Larger statically-linked binary (~3.2 MB vs MSVC's ~1.3 MB). Some MSVC-only constructs are guarded with `#ifdef _MSC_VER`:

- `__try`/`__except` SEH around the crash-log filter's defensive guard (mingw GCC doesn't support that syntax — bare filter still works, just without the inner reentrancy catch).
- Various goto-init-crossing block wraps and `std::nullptr_t` qualifications throughout `source/` (mingw GCC is stricter than MSVC).
- ASM stubs (`x64call.asm` / `x64stub.asm`) have GAS-syntax twins (`x64call.s` / `x64stub.s`) for the mingw build.

The mingw build is suitable for development work from WSL but the MSVC binary is the recommended one for distribution.

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

- **Specs** — `docs/superpowers/specs/2026-05-12-eval-builtin-design.md`, `docs/superpowers/specs/2026-05-13-crashlog-design.md`
- **Plans** — `docs/superpowers/plans/2026-05-12-eval-builtin.md`, `docs/superpowers/plans/2026-05-13-crashlog.md`
- **CLAUDE.md** — high-level project orientation
- **README.md** — top-level fork overview
- **Alpha29_Example.ahk** — runnable showcase of upstream alpha.29 features

The two specs are the authoritative reference for design decisions; the plans break the work into TDD tasks; this `updates.md` is the user-facing summary.
