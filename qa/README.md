# qa/ — fork regression suite

Empirically-verified interpreter regression tests for this AutoHotkey fork.
Distinct from `tests/` (ad-hoc manual crashlog/debugger experiments).

## Run

```powershell
bin\AutoHotkey64.exe /Headless /ErrorStdOut qa\run.ahk
```

Suite exit code = failing assertions + crashes/timeouts, so `0` means the whole
tree is green. Empty discovery is a failure. For a shell-independent command
that waits for the executable and runs the complete release gate, use:

```powershell
python tests/run_console_gate.py bin/AutoHotkey64.exe
```

## How it works

`run.ahk` launches every `qa/tests/test_*.ahk` in its **own process** and reads
each one's exit code + stdout. Because each test is isolated:

- a test that throws at runtime or dies at **load time** (parse error, fatal)
  is a normal, assertable outcome — it does not abort the rest of the suite;
- the runner distinguishes **FAIL** (asserts failed, summary line present) from
  **CRASH** (process died before `Assert.Summary()`), echoing the child's error
  context in the crash case;
- a summary must agree with the actual child exit code; a passing-looking line
  cannot hide an unsuccessful process exit;
- every child receives `/Headless /ErrorStdOut` and has a 30-second timeout.
  A suspended launch assigns the child to a Windows job before it can execute.
  Closing that job terminates descendants, including after a timeout, and the
  runner proceeds to the next test;
- `RunSnippet()` uses the same bounded process helper for nested assertions.

Set `AHK_QA_TIMEOUT_MS` to an integer from 1 to 300000 to override the per-child
timeout. Invalid settings fail the suite. The outer release gate additionally
bounds each complete suite to 180 seconds.

This is the key difference from a single-process `#Include` runner, which
cannot survive a test that fails to load.

## Add a test

Create `qa/tests/test_<topic>.ahk`:

```autohotkey
#Requires AutoHotkey v2.1-alpha.31
#Include ..\Assert.ahk

Assert.eq(actual, expected, "label")
Assert.truthy(cond, "label")
Assert.throws(() => bad(), "label", "optional message substring")

Assert.Summary()   ; must be the last statement
```

`run.ahk` auto-discovers it — no registration needed. Each file is also runnable
standalone (its exit code = its own failure count).

## Assert API

| Call | Passes when |
|------|-------------|
| `Assert.eq(actual, expected, label)` | `actual == expected` |
| `Assert.truthy(cond, label)` | `cond` is truthy |
| `Assert.falsy(cond, label)` | `cond` is falsy |
| `Assert.throws(fn, label [, msgPart])` | `fn()` raises (msg contains `msgPart`) |
| `Assert.noThrow(fn, label)` | `fn()` does not raise |

## Runner regression checks

```powershell
python tests/test_qa_runner.py bin/AutoHotkey64.exe
```

These tests copy the runner into an isolated temporary suite and verify real
process outcomes: success/failure, empty discovery, summary/exit agreement,
headless child flags, timeout recovery, and descendant cleanup.

## Coverage

- `test_struct.ahk` — typed Struct sizes, raw-memory backing, nested-write
  commit, `Struct.Array` 1-based bounds checking (backlog #2).
- `test_language.ahk` — `StrGet(ptr,0)`→`String`, `Format` dispatch, `(fn?)()`
  maybe-call semantics (backlog #3/#4).

Additional automatically discovered suites cover Print, removed syntax,
crash logs, Struct pointer access, native JSON operations, JSON parser fixtures,
and JSON mutation/error regressions. The runner prints the actual files and
assertion counts for the selected binary; use that result to identify coverage.
