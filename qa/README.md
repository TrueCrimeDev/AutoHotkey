# qa/ — fork regression suite

Empirically-verified interpreter regression tests for this AutoHotkey fork.
Distinct from `tests/`, which holds the single-process `Test.ahk` framework
suite (`tests/run.ahk`), the Python CLI/REPL/MCP checks, and manual
crashlog/debugger experiments.

## Run

```powershell
bin\AutoHotkey64Console.exe /Headless /ErrorStdOut qa\run.ahk
```

From Git Bash, which rewrites an argument that starts with `/` into a path:

```bash
./bin/AutoHotkey64Console.exe --headless //ErrorStdOut qa/run.ahk
```

Use the console engine. PowerShell does not wait for the GUI `AutoHotkey64.exe`
unless its output is piped, so `$LASTEXITCODE` would not hold the suite's result.
Every child runs under the same executable as the runner (`A_AhkPath`), so pass
the engine you want to validate, such as an isolated `out\msvc\x64` build.

Suite exit code = failing assertions + crashes/timeouts, so `0` means the whole
tree is green. Empty discovery is a failure. For a shell-independent command
that waits for the executable and runs the complete release gate, use:

```powershell
python tests/run_console_gate.py bin/AutoHotkey64Console.exe
```

## How it works

`run.ahk` launches every `qa/tests/test_*.ahk` in its **own process** and reads
each one's exit code + stdout. Because each test is isolated:

- a test that throws at runtime or dies at **load time** (parse error, fatal)
  is a normal, assertable outcome — it does not abort the rest of the suite;
- the runner distinguishes **FAIL** (asserts failed, summary line present) from
  **CRASH** (process died before `Assert.Summary()`), echoing the child's error
  context in the crash case, and its `  FAIL ` and `  SKIP ` lines otherwise. A
  `SKIP` line marks assertions that need something the host lacks, such as
  `test_alpha31.ahk`'s `PixelSearch` pins without a readable screen (session 0,
  or `tools/run_hidden.py`); the skipped ones are not counted as passed;
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

Set `AHK_QA_COVERAGE_DIR` to a directory and every child also gets
`/Coverage=<dir>\<test>_<pid>_<n>.lcov`; the runner creates the directory
first, so it may be missing. CI does this and merges the reports with
`tools/lcov_summary.py`.

This is the key difference from a single-process `#Include` runner, which
cannot survive a test that fails to load.

## JUnit XML

Set `AHK_QA_JUNIT=<path>` and the runner also writes a JUnit XML report there,
in the shape `tests/Test.ahk` writes under `AHK_TEST_JUNIT`, so one consumer (a
CI reporter, the VS Code Test Explorer) reads both:

```xml
<testsuites name="qa" tests="862" failures="1" errors="0" skipped="0" time="5.625">
  <testsuite name="test_json.ahk" tests="151" failures="1" errors="0" skipped="0" time="0.312">
    <testcase name="parse: nested object" classname="test_json.ahk" />
    <testcase name="parse: bad input" classname="test_json.ahk">
      <failure message="expected: 1  actual: 2">C:\fork\qa\tests\test_json.ahk:42</failure>
    </testcase>
  </testsuite>
</testsuites>
```

- One `testsuite` per test file (`time` is the child's wall clock) and one
  `testcase` per assertion, named by its label. The runner hands the variable
  to every child, and `Assert.ahk` then prints `  PASS <label>` for each
  passing assertion; a failing one always prints
  `  FAIL <label> -- <detail>  (<file>:<line>)`, which becomes a `failure`
  with the detail as its `message` and `file:line` as its text. A
  `  SKIP <text>` line becomes a `skipped` testcase.
- A crashed or timed-out file is one testcase with an `error` whose message is
  the runner's reason and whose text is the child's output (capped at 64 KiB).
- The counts match the stdout summary: `tests` minus `failures`, `errors` and
  `skipped` is the passed count; `failures` plus `errors` is the failed count,
  which is also the exit code; `errors` is the crashed count. A test that
  prints its own summary line without `Assert.ahk` gets unnamed `pass #n` and
  `fail #n` cases, so each suite's element counts still equal its summary.
- The document is written whole to `<path>.<pid>.tmp` beside the report and
  moved into place, so a reader never sees a partial file; a missing report
  directory is created. When the report cannot be written the runner prints
  `qa: JUnit report "<path>" not written: <reason>` and the exit code stays
  the suite's own.

CI sets it to `junit-qa.xml` and uploads that next to `tests/run.ahk`'s
`junit.xml`.

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

A failed assertion prints `  FAIL <label> -- <detail>  (<file>:<line>)`, where
the location is the test line that called it.

## Runner regression checks

```powershell
python tests/test_qa_runner.py bin/AutoHotkey64Console.exe
```

These tests copy the runner into an isolated temporary suite and verify real
process outcomes: success/failure, empty discovery, summary/exit agreement,
headless child flags, timeout recovery, descendant cleanup, and the
`AHK_QA_JUNIT` report (suite and case counts match the summary, failures carry
the assertion message and location, no temp file is left behind, and an
unwritable path leaves the exit code alone).

## Coverage

- `test_struct.ahk` — typed Struct sizes, raw-memory backing, nested-write
  commit, `Struct.Array` 1-based bounds checking (backlog #2).
- `test_language.ahk` — `StrGet(ptr,0)`→`String`, `Format` dispatch, `(fn?)()`
  maybe-call semantics (backlog #3/#4).

Additional automatically discovered suites cover Print, removed syntax,
crash logs, Struct pointer access, native JSON operations, JSON parser fixtures,
and JSON mutation/error regressions. The runner prints the actual files and
assertion counts for the selected binary; use that result to identify coverage.
