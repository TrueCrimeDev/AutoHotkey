# Native MCP integration

The Console executable can expose local tools directly over stdin/stdout. There is no network listener to start for this native server.

## Configure a client

For a client that starts Windows commands:

```json
{
  "mcpServers": {
    "ahk-console": {
      "command": "C:\\Tools\\AutoHotkey64Console.exe",
      "args": ["mcp"]
    }
  }
}
```

For Claude Code running in WSL, use `/mnt/c/Tools/AutoHotkey64Console.exe` as the command. The child remains a Windows process; provide Windows paths for its source-file arguments.

The MCP client handles initialization and protocol framing. `ahk mcp` is not a human REPL; use `ahk repl` for typed expressions.

## Tools in the demonstrated build

| Tool | Purpose | Main arguments |
| --- | --- | --- |
| `ast_outline` | Tree-sitter outline with source ranges | `file` |
| `source_outline` | Fast regex-based definitions | `file` |
| `get_source_context` | Lines around a location | `file`, `line`, `radius?` |
| `workspace_symbols` | Definitions across AHK files | `root?`, `query?`, `max_results?` |
| `server_status` | Engine identity and server counters | None |
| `check` | Parse a file without executing it | `file`, `cwd?`, `timeout_ms?` |
| `run` | Run a file and capture results | `file`, `args?`, `cwd?`, `timeout_ms?` |
| `test` | Run a file in test mode | Same as `run` |

Always discover `tools/list`: older builds may not have the execution tools. The demonstrated `server_status` reports eight tools; this is not a promise for every alpha.31 executable.

## Execution result

`check`, `run`, and `test` use the same executable in a child process with `/Headless /Diag=json`. Results expose `ok`, `exitCode`, captured `stdout` and `stderr`, and parsed `diagnostics`. Execution tools also identify timeouts and terminate the child process tree on timeout.

`timeout_ms` is in milliseconds (default 30,000; documented maximum 600,000). Contrast ProcessPipe's timeout values, which are in seconds. A persistent GUI or timer script may time out rather than exit by itself.

## Three different tooling layers

1. **Native Console MCP:** source inspection and check/run/test in this executable.
2. **ClautoHotkey:** Claude Code plugin hooks, rules, skills, and grading gates.
3. **Other MCP/DBGp services:** optional documentation, UI automation, or debugger integrations, configured separately.

Do not assume installing the plugin starts every optional service. The native eight-tool server does not imply debugger stepping or arbitrary desktop automation tools.
