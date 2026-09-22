# Four practical native MCP examples

These are **AHK scripts calling the MCP built into this fork**. Each starts
`A_AhkPath mcp`, discovers its tools, makes real requests over stdin/stdout,
and closes the child process. No Node, Python, API key, AI subscription, or
network server is needed to run them.

The same tools can be used by an MCP-connected assistant. These examples make
that workflow visible and repeatable without requiring an assistant to drive it.
They use the native server's existing tools; they do not register custom tools.

## Try them

From the repository root in PowerShell:

```powershell
.\examples\native-mcp\run.ps1

# Just the text-cleanup workflow, with your own input:
.\examples\native-mcp\run.ps1 -Demo 2 -Text '  Follow   up with   Alex.  '

# Demonstrate a failed test; this command intentionally exits 14:
.\examples\native-mcp\run.ps1 -Demo 4 -FailTest
```

The launcher defaults to `bin_review\AutoHotkey64Console.exe`. Use `-Engine`
to select another compatible build explicitly. This machine's `bin` Console
executable is older; do not rely on a file association or the `ahk` alias.
These scripts require the fork's `ProcessPipe`, native `JSON`, and MCP tools.
The AST example also needs the fork's tree-sitter DLL in its normal location.

You can also run an example directly:

```powershell
& .\bin_review\AutoHotkey64Console.exe /Headless /Diag=json .\examples\native-mcp\02_check_then_run.ahk
```

## What each script demonstrates

| Script | Useful workflow | Native MCP calls |
| --- | --- | --- |
| [01_find_function.ahk](01_find_function.ahk) | Find `CleanText`, get its full source range, and print nearby code. Useful for navigating an unfamiliar project. | `server_status`, `workspace_symbols`, `source_outline`, `ast_outline`, `get_source_context` |
| [02_check_then_run.ahk](02_check_then_run.ahk) | Check a text-processing worker, run it with arguments, and read its JSON output. Useful for an assistant or script orchestrating small workers. | `check`, `run` |
| [03_explain_failure.ahk](03_explain_failure.ahk) | Capture a deliberate input error and print the exact source line with context. Useful for diagnosis without a blocking error dialog. | `run`, `get_source_context`, `server_status` |
| [04_run_tests.ahk](04_run_tests.ahk) | Run four assertions and propagate the test result to the caller. Useful for a pre-commit or CI check. `--fail` demonstrates exit 14. | `check`, `test` |

Example text-cleanup output:

```text
Syntax check passed. Running the worker...
Before: [  Follow   up with   Alex.  ]
After:  [Follow up with Alex.]
Characters: 28 -> 20
```

Example error report:

```text
ValueError: Provide at least one non-whitespace character.
...
    5 |     if cleaned = ""
>   6 |         throw ValueError("Provide at least one non-whitespace character.")
    7 |     return cleaned
```

## Read or adapt the scripts

[McpClient.ahk](McpClient.ahk) contains the shared handshake, tool discovery,
JSON-RPC framing, and process cleanup. The individual demos keep the tool
names and arguments visible:

```autohotkey
checked := mcp.Call("check", McpArgs("file", file, "timeout_ms", 5000))
RequireSuccess(checked)
result := mcp.Call("run", McpArgs("file", file, "args", [input], "timeout_ms", 5000))
RequireSuccess(result)
data := JSON.Parse(result["stdout"])
```

The helper is intentionally a small synchronous client for this native server,
not a general MCP SDK. A tool response can arrive successfully while the child
script fails: inspect `ok`, `exitCode`, `timedOut`, and `diagnostics`.
Tool timeouts use milliseconds; `ProcessPipe` timeouts use seconds.

`check` verifies syntax without running the script. The outlines support source
navigation; neither is a substitute for `check`. `run` and `test` execute real
code. `/Headless` is not a sandbox. These supplied workers only process sample
text and print results; they do not manipulate the desktop or write files.

## Verification

Executed on 2026-09-18 using `bin_review\AutoHotkey64Console.exe`, reporting
`2.1-alpha.31+Console`, revision `a72a652123b7-dirty`, MSVC x64.
All eight AHK files passed the engine's syntax/load check. All four default demos
completed over native MCP, exercising all eight discovered tools. The sample
suite passed four assertions, and the deliberate failure returned exit 14.
The repository console gate also passed all 11 suites, including 749 QA
assertions with zero failures or crashes. No engine rebuild was performed.
