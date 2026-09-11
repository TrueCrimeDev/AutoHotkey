# Readable terminal tracing — September 7, 2026

`/Trace` now prints the statement about to execute, with its source filename and
line number. Previously it printed bare line numbers and raw keyboard-hook rows.

```powershell
ahk /Trace .\script.ahk
```

Example for a two-line script:

```text
[trace] script.ahk:1  value := 40 + 2
[trace] script.ahk:2  Print(value)
42
```

Only executing statements produce trace records. Blank source lines, comments,
braces, internal module endings, generated lines without a source number, and
raw keyboard events are omitted. An idle script stays quiet; hotkey and timer
handlers produce entries when they execute. Repeated loop statements are still
reported because they execute repeatedly. `ListLines(false)` pauses statement
tracing and `ListLines(true)` resumes it.

Statement text comes from the parsed script and is not evaluated a second time.
It describes execution starting, not successful completion or current variable
values. Multiline strings are escaped onto one row; very long statements are
truncated with `...`. Console output supports Unicode; redirected traces use
UTF-8 on stderr. Normal script output remains on stdout. `/Diag=json` does not
turn trace records into JSON.

For no execution tracing, launch without `/Trace`. To print named hotkey events,
add `Print("Hotkey fired: " A_ThisHotkey)` inside the handler. Normal `KeyHistory()`
remains available as an on-demand snapshot.

## Verification and installation

The seven trace regressions cover actual execution versus skipped branches,
Unicode and multiline text, long lines, included files, `ListLines` toggling,
stdout separation, and quiet idle behavior followed by hotkey dispatch. The
hotkey test posts a message only to its own process's verified script window;
it does not inject global keyboard input or test physical hook delivery.

The aggregate gate now has nine suites: 586 AHK assertions, three Eval scripts,
and 44 process tests, including the seven trace regressions. Both architectures
and both launchers are built and gated. The GUI launcher also preserves inherited
stderr pipes instead of replacing them while attaching to a console.

`bin/console-trace-build-20260907.json` records the installed hashes, gate logs,
and backups. Already-running scripts keep their loaded engine; restart a script
to use this trace format. The work remains local and uncommitted.
