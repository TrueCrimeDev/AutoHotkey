# Static & dry-run gates

The grading harness writes a common result schema, `ahk-harness/result@1`. It lets tools preserve a script's identity, checks, findings, and evidence level across a workflow.

## Static gate

From PowerShell, with a local ClautoHotkey checkout:

```powershell
$engine = 'C:\Tools\AutoHotkey64Console.exe'
$plugin = 'C:\Source\ClautoHotkey'
$script = 'C:\Scripts\Demo\demo.ahk'
& $engine "$plugin\Tools\harness\GateStatic.ahk" $script --label demo-static --run demo-001 --out C:\Scripts\evidence\static 1>static.ndjson 2>static.stderr.txt
python "$plugin\Tools\harness\CheckResults.py" static.ndjson
```

The gate checks existence, v1 patterns, the engine's parse check, validation, code intelligence, and lint. Inspect findings **and** parser confidence. `status=pass` or checker exit zero does not mean every check had complete source understanding.

The demonstrated fixture passes with `parse=partial`: the bundled tree-sitter grammar encounters syntax regions it cannot fully model. Interpreter acceptance and tree-sitter completeness are separate facts.

## Dry-run gate

After reviewing the script and accepting the earlier checks:

```powershell
& $engine "$plugin\Tools\harness\GateDryRun.ahk" $script --label demo-dryrun --run demo-001 --out C:\Scripts\evidence\dryrun --timeout 30 1>dryrun.raw.ndjson 2>dryrun.stderr.txt
python "$plugin\Tools\harness\CheckResults.py" static.ndjson dryrun.raw.ndjson
```

The shim records selected operations and reports `residency`, `actions`, and `intent`. A result can record an exited, idle, or wedged candidate. Do not interpret `actions=0` as proof of no side effects: native calls, some file/clipboard operations, ProcessPipe, and other gaps remain real.

## Stdout and result records

In the demonstrated build, candidate stdout can be mixed into the dry-run gate's NDJSON output. The feature fixture prints text and JSON; checking its **raw stream failed with 42 flagged records**. Keep that raw file. If investigating, extract the uniquely identified actual harness row into a separate file and label the distinction explicitly.

The demo's static result plus separately extracted dry-run row passed the checker: two clean, zero flagged. That does **not** repair or erase the raw-stream failure.

## Read the contract

| Field | What to preserve |
| --- | --- |
| `run`, `label`, `script`, `tier` | Identity and claimed evidence level |
| `status`, `checks` | Script outcome versus tool error or timeout |
| `parse` | Clean, partial, failed, not-parsed, or error |
| `findings`, `counts` | Severity, rule, line, confidence, message |
| `sentinel` | Completed record marker |
| `residency`, `actions`, `intent` | Dry-run-specific observations |

The contract describes `static → pure → dryrun → live`. The supplied generic gates are static and dry-run; do not invent a pure/live gate result. A failed or missing check is a stop condition for that branch until investigated.

Source: [harness contract](https://github.com/TrueCrimeDev/ClautoHotkey/blob/main/Tools/harness/CONTRACT.md).
