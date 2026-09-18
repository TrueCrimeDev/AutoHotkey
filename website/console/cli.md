# CLI & PowerShell

Use the Console-subsystem executable for terminal work. It attaches to the terminal, receives stdin, and lets PowerShell wait for completion. The GUI executable remains useful for normal desktop launches.

## Commands

```powershell
ahk --help
ahk --version
ahk --capabilities
ahk run .\hello.ahk
ahk check .\hello.ahk
ahk test .\tests.ahk
ahk repl
ahk mcp
```

`run` is optional: `ahk hello.ahk` also executes the file. Global flags can precede the command. Arguments after the script path belong to the script, through `A_Args`. Use `--` for a filename that would otherwise look like a flag or command.

## Paths with spaces

```powershell
& 'C:\Program Files\AHK Console\AutoHotkey64Console.exe' /Headless 'C:\My Scripts\hello.ahk'
$code = $LASTEXITCODE
```

Capture `$LASTEXITCODE` immediately after the native command. Later native programs can replace it.

## Shells and streams

```powershell
ahk /Headless /Diag=json .\hello.ahk 1>result.txt 2>diagnostics.jsonl
```

Windows PowerShell 5.1 and PowerShell 7 differ in native redirection and encoding behavior. If exact UTF-8 bytes matter, choose an explicit encoding/byte-preserving subprocess API and verify it. Do not assume a shell redirect preserves the engine's original encoding.

In WSL, invoke the Windows executable through `/mnt/c/...`, but pass Windows script paths to the Windows interpreter when needed. Python running under Linux expects Linux paths; Windows Python expects Windows paths.

## Headless is a launch behavior

`/Headless` suppresses engine-owned interactive error prompts. It does not sandbox the script or suppress every explicit `MsgBox`, GUI, native call, or side effect. Use bounded, deliberately selected scripts for automated checks.
