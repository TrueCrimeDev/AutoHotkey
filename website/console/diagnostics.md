# Structured diagnostics

`/Diag=json` emits machine-readable diagnostics. A tool can locate the source line and classify a failure without scraping an error dialog.

## Produce a failure deliberately

Save `failure.ahk`:

```ahk
#Requires AutoHotkey v2.1-alpha.31
Print("starting")
throw Error("demonstration failure")
```

```powershell
ahk /Headless /Diag=json .\failure.ahk 1>output.txt 2>diagnostics.jsonl
$code = $LASTEXITCODE
Get-Content diagnostics.jsonl | ConvertFrom-Json |
    Select-Object type, message, file, line, code
"Exit: $code"
```

The uncaught runtime error is expected to exit `10`; `test` mode instead maps a failed test to `14`.

## Diagnostic schema

| Field | Meaning |
| --- | --- |
| `kind`, `format`, `schema` | Diagnostic record identity; JSON diagnostics use schema 2 |
| `severity`, `type`, `code` | Warning/error, AHK error class, mapped exit code |
| `message`, `what`, `extra` | Error text and context |
| `file`, `line`, `column` | Location; column can be zero or best-effort |
| `source`, `stack` | Source text and stack when available |

The successful `check` verdict is a separate record: `{"kind":"check","status":"pass"}`. Warnings are diagnostics too; distinguish severity from process success.

## In ClautoHotkey

Set `AHK_DIAG_JSON=1` only for a compatible Console build. The hook uses the configured interpreter; native MCP `check`, `run`, and `test` also return captured streams and parsed diagnostics. Keep original stderr when investigating records that could not be parsed.

See [exit-code reference](/reference/commands) and [MCP integration](/clautohotkey/mcp).
