# A JSON command-line tool

Save this as `json-summary.ahk`:

```ahk
#Requires AutoHotkey v2.1-alpha.31
if A_Args.Length != 1
    throw ValueError("Expected one JSON argument")
config := JSON.Parse(A_Args[1])
result := {name: config["name"], doubled: config["count"] * 2}
Print(JSON.Stringify(result))
```

## Run and parse its result

In PowerShell 7:

```powershell
$payload = '{"name":"demo","count":21}'
$raw = ahk /Headless /Diag=json .\json-summary.ahk $payload
$code = $LASTEXITCODE
if ($code -ne 0) { throw "Script failed: $code" }
$result = $raw | ConvertFrom-Json
$result.doubled
```

Expected value: `42`. Native argument quoting differs in Windows PowerShell 5.1; use PowerShell 7 or test your exact argument transport there.

## Exercise the failure path

```powershell
ahk /Headless /Diag=json .\json-summary.ahk '{' 2>invalid-input.jsonl
$LASTEXITCODE
```

Invalid JSON should fail, emit a diagnostic, and return a nonzero exit code. Do not treat successful parsing of one happy-path result as sufficient validation.

## Bring ClautoHotkey into the task

Ask Claude to add assertions for missing fields, unexpected value types, and invalid JSON, using the configured engine. Have it retain diagnostics and report the exit code for each case. Use the [test recipe](/recipes/testing-ci) to make those cases repeatable.

[Download the script](/examples/json-summary.ahk).
