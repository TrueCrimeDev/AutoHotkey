# PowerShell CLI repair — September 7, 2026

The previous `ahk` function launched the GUI-subsystem executable. Its no-argument
branch piped version output to `Out-Host`, but other invocations did not reliably
wait or provide an interactive console. The repair uses a dedicated console
executable and a native PowerShell alias registered by `tools/ahk.ps1`.

## Use

After the profile is updated, reload an existing PowerShell window:

```powershell
. $PROFILE
ahk
ahk help
ahk run .\test.ahk
ahk check .\test.ahk
ahk repl
```

`test.ahk` must exist in the current directory. `ahk run` requires a filename;
omitting it now prints an explanation and exits with code 64. `ahk test.ahk`
also runs a script directly. `help`, `-h`, `--h`, `-help`, and `--help` display
usage. A missing script produces a visible error and exit code 12.

At the REPL prompt, enter `40 + 2` to get `42`, then `.exit` to return to
PowerShell. The native alias preserves console input, output redirection, and
`$LASTEXITCODE`. It points to `bin/AutoHotkey64Console.exe`; standard GUI launchers
remain available as `bin/AutoHotkey64.exe` and `bin/AutoHotkey32.exe`.

For readable executing statements in the terminal, use the trace option:

```powershell
ahk /Trace .\test.ahk
```

The [trace update](console-trace-20260907.md) shows `file:line` and the statement,
omits structural and raw-key rows, and stays quiet while idle. To print a hotkey's
name from its handler, use `Print("Hotkey fired: " A_ThisHotkey)`.

Windows PowerShell 5.1 applies its native argument quoting rules. For Unicode
piped input, explicitly select UTF-8 with
`$OutputEncoding = [Text.UTF8Encoding]::new($false)`. The MCP reader now accepts
one initial UTF-8 BOM, including the one emitted by Windows PowerShell 5.1.

## Verification

The repair includes ten real-shell regression tests, each exercised in both
PowerShell versions, covering discovery, errors, script arguments and exit codes,
check/test, REPL input, Unicode, and MCP. Interactive terminal checks additionally
verify that REPL input remains attached until `.exit`.

The CLI repair gate covered 586 AHK assertions, three Eval scripts, and 37 process
tests: CLI (8), REPL (12), MCP (10), and QA runner (7). Its build and shell results,
hashes, and backup paths are recorded in `bin/console-build-20260907.json`. The
subsequent trace update adds seven trace tests and has its own build record.
Changes are local and remain uncommitted.
