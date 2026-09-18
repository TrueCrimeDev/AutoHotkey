# Commands & exit codes

Use `ahk --help` and `ahk --capabilities` on your actual executable for the final authority.

## Commands

| Command | Behavior |
| --- | --- |
| `run script.ahk [args...]` | Execute a script; `run` can be omitted |
| `check script.ahk` | Parse without normal script execution |
| `test script.ahk [args...]` | Execute in test mode |
| `repl [script.ahk]` | Persistent expression session |
| `mcp` | Native local MCP server over stdio |
| `--help` | Usage and available flags |
| `--version` | Engine version, build/compiler/architecture identity |
| `--capabilities` | Machine-readable commands, features, protocol information |

## Selected flags

| Flag | Purpose |
| --- | --- |
| `/Headless` | Suppress engine-owned interactive prompts; not a sandbox |
| `/Diag=json` | Structured diagnostic/result mode |
| `/ErrorStdOut` | Human-readable error reporting; despite the legacy name, diagnostics use stderr |
| `/ErrorStdOut:color` | ANSI-colored error reporting |
| `/Eval` | Opt into Eval |
| `/Trace` | Human-readable executing statements on stderr |
| `/Trace=json` | Structured statement events; development capability |
| `/Coverage=path` | LCOV file; development capability |
| `/CrashLog=path` | Append-only engine event log |
| `/Debug` | Connect to a DBGp debugger; separate from native MCP |

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success |
| `10` | Uncaught script exception |
| `11` | Critical/internal/fatal interpreter error |
| `12` | Parse or load failure |
| `13` | `check` failed |
| `14` | `test` failed |
| `64` | CLI usage error |
| `130` | External interruption such as Ctrl+C |

Other explicit `ExitApp(n)` values can pass through. Capture the code immediately and retain stderr to explain it.

## API quick index

`Print(Fmt?, Values*)` · `Eval(expr)` · `JSON.Parse(text, options?)` · `JSON.Stringify(value)` · `Inspect(value, depth?, maxItems?)` · `Check(source)` · `ProcessPipe(command, args?, workingDir?)` · `_ScriptGetLines(file, line, range?)`.

See the relevant feature guides for semantics, build requirements, and limits; this index is not a complete upstream language reference.
