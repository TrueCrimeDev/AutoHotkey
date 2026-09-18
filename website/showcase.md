---
title: Real session gallery
description: Actual Claude Code sessions using Console and ClautoHotkey, with neutral-path screenshots and downloadable AHK fixtures.
---
# See the two projects working together

These are **actual Claude Code terminal captures**, made on September 17, 2026. The demonstration runs from `C:\ClautoHotkey-Demo`; the shared captures contain no Windows username. The feature capture is a full session view; the harness capture frames the results portion of its terminal.

## Edit, validate, execute, inspect

[![Claude Code edits an AHK script, invokes ClautoHotkey validation, runs six feature sections, and calls native MCP tools.](/images/features.png)](/images/features.png)

The session uses the real ClautoHotkey plugin, the configured Console executable, a Write operation, validation-hook execution, runtime assertions, and actual native MCP calls. The visible hook replay captures its stdout/stderr for inspection.

| Runtime behavior | What the fixture asserts |
| --- | --- |
| Print | Formatted values and literal braces through child stdout |
| JSON | Parsing, ordered round trip, boolean/null handling |
| Inspect | Array type, length, and primitive items |
| Check | Valid source accepted; invalid source has diagnostics |
| Eval | Expression result, caller scope, SyntaxError |
| ProcessPipe | Child launch, stdout lines, exit code, empty stderr |

**Result: 26 assertions, zero failures.** MCP `check` returned success with no diagnostics. `server_status` reported eight registered tools; only the calls shown and recorded were exercised, not every possible MCP operation.

## Harness, trace, and coverage

[![Claude Code reports static and dry-run gate outcomes, distinguishes a raw checker failure from an extracted result pass, and reports trace and coverage counts.](/images/harness.png)](/images/harness.png)

| Evidence | Observed result |
| --- | --- |
| Static gate | Pass, zero findings, **partial** tree-sitter parse |
| Dry-run result row | Pass; exited; zero intercepted actions |
| Raw dry-run stream checker | **Failed: 42 flagged records** because candidate stdout mixes with gate output |
| Static plus extracted actual result row | Two clean, zero flagged |
| JSON trace | 174 records, all valid JSON |
| LCOV | 77 of 84 instrumented lines hit |

The raw-stream issue remains a limitation. Extracting a result row for analysis does not make the original stream valid. `actions=0` also does not prove absence of real side effects: the controlled child process and check temporary files actually ran.

## Run the fixture locally

Download [feature_demo.ahk](/examples/feature_demo.ahk) and [child_echo.ahk](/examples/child_echo.ahk) into one directory. Use a [compatible development build](/guide/compatibility):

```powershell
ahk --capabilities
ahk /Headless /Diag=json test .\feature_demo.ahk
```

[Download the screenshot pack](/downloads/ClautoHotkey-screenshots.zip). Click either image to inspect the original-resolution PNG.

## What this does not prove

This is a controlled console demonstration. It does not verify arbitrary GUI interactions, keyboard/mouse automation, Excel/COM workflows, external services, or a generic pure/live harness tier. See [verification & sources](/reference/verification) for the broader test context.
