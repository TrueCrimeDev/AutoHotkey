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

1. AHK resolves `"*"` as standard output in `TextFile::_Open(...)` (`source/TextIO.cpp`).
2. The mapping uses `STD_OUTPUT_HANDLE` (the `*aFileSpec == '*'` branch of `TextFile::_Open`).
3. Output bytes are written by `TextFile::_Write(...)`, which uses `WriteFile`.

Related source notes:

- `FileOpen("*", "r|w")` support is explicitly documented in a code comment in that branch ("v1.1.17: Allow FileOpen("*", "r|w") ...").
- `"**"` maps to `STD_ERROR_HANDLE` for stderr in the same branch.

This note names functions rather than line numbers, which move with every merge.

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

- option parse: the `/ErrorStdOut` branch of the command-line loop in `source/AutoHotkey.cpp`, which calls `Script::SetErrorStdOut` (`source/error.cpp`)
- runtime error redirect logic: `Script::ShowError` (`source/error.cpp`), whose `if (mErrorStdOut || mHeadless)` block formats the report
- actual write target: that block calls `PrintErrorStdOut(buf, ..., _T("**"))`, i.e. stderr
- compatibility comment: "For backward compatibility, this actually prints to stderr, not stdout." above the line-oriented `Script::PrintErrorStdOut` overload

So:

- regular script output should use `"*"`
- runtime error output under `/ErrorStdOut` goes to `"**"`

## Debugger interaction with stdout

The debugger engine supports DBGp stream commands `stdout` and `stderr`:

- command registration: the `stdout` and `stderr` entries of `Debugger::sCommands` (`source/Debugger.cpp`)
- stream packet writer: `Debugger::WriteStreamPacket`
- hook methods: `Debugger::OutputStdOut`, `Debugger::OutputStdErr`

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
