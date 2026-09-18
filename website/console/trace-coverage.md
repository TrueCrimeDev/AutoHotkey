# Trace & coverage

Tracing tells you **which statement began executing**. Coverage tells you **which instrumented lines were hit**. Assertions tell you **whether the result was correct**.

## Keep the output channels separate

```powershell
ahk /Headless /Trace=json /Coverage=coverage.lcov .\demo.ahk 1>output.txt 2>trace.jsonl
$runExit = $LASTEXITCODE
Get-Content trace.jsonl | ConvertFrom-Json | Select-Object -First 5
```

Both LCOV coverage and JSON trace are development capabilities. Plain `/Trace` is the human-readable statement format.

## JSON statement records

```json
{"event":"statement","file":"C:\\Scripts\\demo.ahk","line":7,"function":"SaveRecord","thread":1,"text":"count += 1"}
```

This is an illustrative record. `thread` represents AHK pseudo-thread count, not an OS thread identifier. Do not treat a statement event as evidence that the statement finished successfully. Errors and other stderr records may share the stream; retain and classify them rather than discarding parse failures.

## LCOV records

```text
SF:C:\Scripts\demo.ahk
DA:7,1
DA:8,0
LF:2
LH:1
end_of_record
```

`DA` records line hit counts; `LF` is instrumented lines, `LH` is hit lines. Structural syntax such as braces or function headers is not a coverage target. Coverage is collected by the interpreter, so a separate parser does not have to guess alpha syntax.

The engine attempts to flush coverage on exit, including error paths. External forced termination cannot be assumed to produce a complete artifact.

## Real demo result

The [gallery fixture](/showcase) produced **174 valid JSON trace records** and **77 of 84 instrumented lines hit**. These values describe that run and fixture, not overall engine coverage. Failure branches in an all-pass run may remain unhit.
