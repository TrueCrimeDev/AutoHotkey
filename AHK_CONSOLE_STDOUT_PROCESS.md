# AHK Console Stdout Process (This Repo)

This document is specific to how stdout works in this AutoHotkey v2 fork when running from a console.

## What "stdout" means in AHK

For script code, stdout is the stream target `"*"` used by `FileAppend`/`FileOpen`.

Example:

```autohotkey
FileAppend "Hello from AHK`n", "*"
```

In this repo, `tests/test_console.ahk` demonstrates this pattern (`tests/test_console.ahk:4`).

## Internal pipeline for stdout

When a script writes to `"*"`:

1. AHK resolves `"*"` as standard output in `TextFile::_Open(...)` (`source/TextIO.cpp:601`).
2. The mapping uses `STD_OUTPUT_HANDLE` (`source/TextIO.cpp:639`).
3. Output bytes are written by `TextFile::_Write(...)`, which uses `WriteFile` (`source/TextIO.cpp:688`).

Related source notes:

- `FileOpen("*", "r|w")` support is explicitly documented in code comments (`source/TextIO.cpp:629`).
- `"**"` maps to `STD_ERROR_HANDLE` for stderr (`source/TextIO.cpp:641`).

## Stdout vs stderr in console mode

- Stdout: `"*"`
- Stderr: `"**"`

Example:

```autohotkey
FileAppend "normal output`n", "*"
FileAppend "error output`n", "**"
```

## `/ErrorStdOut` is mostly a stderr path

`/ErrorStdOut` is historically named, but in this fork runtime error text is formatted and written to stderr (`"**"`), not stdout:

- option parse: `source/AutoHotkey.cpp:131`
- runtime error redirect logic: `source/error.cpp:835`
- actual write target: `source/error.cpp:845`
- compatibility comment: `source/error.cpp:325`

So:

- regular script output should use `"*"`
- runtime error output under `/ErrorStdOut` goes to `"**"`

## Debugger interaction with stdout

The debugger engine supports DBGp stream commands `stdout` and `stderr`:

- command registration: `source/Debugger.cpp:73`, `source/Debugger.cpp:74`
- stream packet writer: `source/Debugger.cpp:2311`
- hook methods: `source/Debugger.cpp:2333`, `source/Debugger.cpp:2326`

This is separate from shell handles. It is for debugger transport (`<stream type="stdout|stderr">` packets), not normal console redirection.

## "LineOut" clarification

AHK does not have a separate built-in API named `LineOut` for console output.

What people call "line output" is usually:

- writing text that ends with `` `n `` to stdout/stderr
- a host process reading that stream and splitting on newlines

## Quick verification commands

```powershell
# stdout test
bin\AutoHotkey64.exe tests/test_console.ahk 1>out.txt 2>err.txt

# runtime error test under /ErrorStdOut
bin\AutoHotkey64.exe /ErrorStdOut tests/test_errorstdout.ahk 1>out.txt 2>err.txt
```

Expected behavior:

- `tests/test_console.ahk` text goes to `out.txt`
- runtime error details from `tests/test_errorstdout.ahk` go to `err.txt`
