# Versions & availability

This site documents two related things: the Console/ClautoHotkey workflow, and the **alpha.31 development build demonstrated on September 17, 2026**. The demo executable reports base revision `a72a652123b7-dirty`; its working-tree additions are not a tagged public release.

## Ask the executable

```powershell
ahk --version
$caps = ahk --capabilities | ConvertFrom-Json
$caps.commands
$caps.features
```

| Capability | How to check | Use it for |
| --- | --- | --- |
| `json` | `features.json` | Native JSON conversion |
| `eval` | `features.eval` is `opt-in` | Expression evaluation with explicit enablement |
| `repl` | `features.repl` / `commands` | Persistent expression sessions |
| `check` | `features.check` / `commands` | Parse-only validation |
| `coverage` | `features.coverage` | LCOV line coverage |
| `inspect` | `features.inspect` | Value descriptions |
| `processPipe` | `features.processPipe` | Child-process communication |
| JSON trace | `features.traceFormats` contains `json` | Structured statement events |
| MCP tools | MCP `tools/list` | Discover actual callable tools |

## Published source versus demonstrated additions

Treat **Inspect, ProcessPipe, LCOV coverage, JSON statement tracing, and native MCP execution tools** as development features unless your executable advertises them. Do not infer their presence from `alpha.31` alone. The test result describes the tested binary, not every binary with that version string.

The public source branch and development checkout can differ. This site does not silently publish unrelated engine changes alongside the documentation. [Verification & sources](/reference/verification) records the evidence boundaries.

## Alpha language versus fork features

`#Requires AutoHotkey v2.1-alpha.31` checks a language version requirement. It does not identify this fork. `Print`, `Eval`, native `JSON`, `Inspect`, `Check`, and `ProcessPipe` are fork APIs and need separate capability/source verification.

ClautoHotkey can target stock v2 with `AHK_DIAG_JSON=0`. Its rules consider the configured target; setting `AHK_DIAG_JSON=1` on stock AHK does not add Console features.

## Architecture matters

The x64 and x86 interpreters can run the engine tests. The bundled tree-sitter grammar DLL is x64-only. Headless checks also do not establish GUI, DPI, keyboard/mouse, or third-party application behavior.
