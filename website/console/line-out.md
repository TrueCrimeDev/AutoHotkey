---
title: Line Out — live execution in your terminal
description: Follow AutoHotkey executing statements with Line Out. Add /Trace to see filenames, line numbers, and statement text in your terminal.
---

# Line Out

See your AutoHotkey script run, line by line. **Line Out is the live execution output enabled by `/Trace`** in the Console fork. Each entry shows the source filename, line number, and statement as it begins executing.

```powershell
ahk /Trace .\script.ahk
```

There is no extra library to include or logging call to add to each line. Use a [compatible Console build](/guide/compatibility); if you are starting fresh, follow [Build & install](/guide/installation) and the [PowerShell alias setup](/guide/installation#add-a-temporary-powershell-alias).

## Try it in four lines

Download [line-out.ahk](/examples/line-out.ahk), or save this as `line-out.ahk`:

```ahk
#Requires AutoHotkey v2.1-alpha.30
value := 40
value += 2
Print(value)
```

Run it from the folder where you saved it:

```powershell
ahk /Trace .\line-out.ahk
```

The trace goes to stderr:

```text
[trace] line-out.ahk:2  value := 40
[trace] line-out.ahk:3  value += 2
[trace] line-out.ahk:4  Print(value)
```

The script's result, `42`, goes to stdout. Both are visible in your terminal, and you can capture them separately.

Without an `ahk` alias, use the Console executable directly:

```powershell
& 'C:\Tools\AutoHotkey64Console.exe' /Trace .\line-out.ahk
```

Replace the example executable path with your installation path.

## Follow what actually runs

- **Branches and loops:** see the statements reached on this run, including repeated loop statements. Skipped branch bodies produce no entries.
- **Hotkeys and timers:** entries appear when their handlers execute. An idle script stays quiet.
- **Included files:** each entry identifies the source file and line.
- **Readable statements:** comments, blank lines, braces, and raw keyboard events are omitted. Multiline text is escaped onto one row; very long statements are truncated.

The statement text comes from the parsed script. A trace entry means execution started; it does not show current variable values or prove successful completion. Use [Print](/console/print-json) for values and [assertions](/recipes/testing-ci) for expected results.

## Save the trace

```powershell
ahk /Trace .\line-out.ahk 1>result.txt 2>trace.txt
$runExit = $LASTEXITCODE
Get-Content trace.txt
Get-Content result.txt
"Exit: $runExit"
```

Redirected trace output uses UTF-8. Diagnostics can also appear on stderr, so keep them when reviewing the trace.

## Pause or turn it off

Use `ListLines(false)` inside your script to pause statement tracing and `ListLines(true)` to resume it. Launch without `/Trace` when you do not need execution output.

## Extras for deeper inspection

Need structured statement events or line hit counts? See [JSON trace & coverage](/console/trace-coverage). For the rest of the tools, explore [the Console toolkit](/console/overview) or the optional [ClautoHotkey integration](/clautohotkey/setup).
