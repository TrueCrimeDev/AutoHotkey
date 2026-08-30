# qa/ — fork regression suite

Empirically-verified interpreter regression tests for this AutoHotkey fork.
Distinct from `tests/` (ad-hoc manual crashlog/debugger experiments).

## Run

```powershell
bin\AutoHotkey64.exe /ErrorStdOut qa\run.ahk
```

Suite exit code = failing assertions + crashes, so `$LASTEXITCODE`/`$?` of `0`
means the whole tree is green. Runs headless; no dialogs.

## How it works

`run.ahk` launches every `qa/tests/test_*.ahk` in its **own process** and reads
each one's exit code + stdout. Because each test is isolated:

- a test that throws at runtime or dies at **load time** (parse error, fatal)
  is a normal, assertable outcome — it does not abort the rest of the suite;
- the runner distinguishes **FAIL** (asserts failed, summary line present) from
  **CRASH** (process died before `Assert.Summary()`), echoing the child's error
  context in the crash case.

This is the key difference from a single-process `#Include` runner, which
cannot survive a test that fails to load.

## Add a test

Create `qa/tests/test_<topic>.ahk`:

```autohotkey
#Requires AutoHotkey v2.1-alpha.30
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

## Coverage

- `test_struct.ahk` — typed Struct sizes, raw-memory backing, nested-write
  commit, `Struct.Array` 1-based bounds checking (backlog #2).
- `test_language.ahk` — `StrGet(ptr,0)`→`String`, `Format` dispatch, `(fn?)()`
  maybe-call semantics (backlog #3/#4).

All facts verified against `2.1-alpha.30+Console` on 2026-07-09.
