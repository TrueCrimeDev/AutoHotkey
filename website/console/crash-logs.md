# Crash logs & source context

A shell capture is useful until the launcher loses it. `/CrashLog` provides an additional append-only record of engine events.

## Enable a log

```powershell
ahk /Headless /CrashLog=events.log .\script.ahk
```

The `#CrashLog path` directive is another entry point. Event types include startup, script errors, fatal faults, and exit records. Each write is flushed so completed records can survive subsequent failure; no logger can promise a final record after every external termination.

## Inspect nearby source

```ahk
for line in _ScriptGetLines(A_LineFile, A_LineNumber, -3)
    Print("{:03}: {}", line.Number, line.Text)
```

`_ScriptGetLines` provides source text around a location. Native MCP `get_source_context` serves a related file-and-line workflow. Use the line in a diagnostic to inspect context, form a small repair, then rerun the failing case.

## Share a useful report

Include the executable's `--version`, relevant command, exit code, minimal script, and the relevant records. Logs can contain source text, absolute paths, and argument values. Use a neutral demo folder and review the actual artifact before sharing, as in the [gallery](/showcase).

For interactive stepping, the separate DBGp debugger integrations are distinct from the native stdio MCP server. See [MCP integration](/clautohotkey/mcp#three-different-tooling-layers).
