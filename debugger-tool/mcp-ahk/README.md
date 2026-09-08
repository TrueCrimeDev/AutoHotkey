# mcp.ahk — an MCP server that runs inside AutoHotkey64.exe

**One self-contained file. No includes, no separate runtime.** It runs inside the
AutoHotkey process (the script *is* the server), and its tools are also callable
as a plain function.

> **Native verb:** the same server is also compiled into the fork engine as
> `AutoHotkey64.exe mcp` (C++, `source/mcp_server.cpp`) — zero files needed
> beyond the exe + `tree-sitter-ahk.dll`. Same five tools, same protocol, same
> payloads; `tests/conformance_native.py` diffs it against this script. This
> file remains the reference implementation and the function-call / client API
> (`MCP()`, `McpClient`).

Requires the fork engine (`2.1-alpha.31+Console`) for the
`TSParse` / `Print` BIFs.

## Three ways to use it

**1. Run it in the exe as an MCP server** (stdio — for Claude Code / Cursor):

```
bin\AutoHotkey64.exe debugger-tool\mcp-ahk\mcp.ahk
```

Register with a client:

```json
{ "mcpServers": { "ahk-mcp": {
  "command": "C:\\Users\\...\\AutoHotkey\\bin\\AutoHotkey64.exe",
  "args": ["C:\\Users\\...\\AutoHotkey\\debugger-tool\\mcp-ahk\\mcp.ahk"] } } }
```

**2. Call a tool as a function:**

```ahk
#Include mcp.ahk        ; or  #Include <mcp>  if placed in the exe's Lib\ folder

out := MCP("ast_outline", Map("file", "C:\path\x.ahk"))
MsgBox out["count"]      ; 73 — out is a normal AHK Map
for s in out["symbols"]
    ...                  ; s["kind"], s["name"], s["line"]
```

Including `mcp.ahk` only defines the functions — it does **not** start the server
(that happens only when `mcp.ahk` is the file you run directly).

> Zero includes — calling `MCP()` from any script with no `#Include` at all — is
> only possible by compiling it into the engine as a native C++ BIF (like
> `TSParse`). That's the only mechanism AHK v2 offers; there is no auto-include.

**3. Drive an MCP server from AHK** (AHK as the *client*):

```ahk
#Include mcp.ahk

; spawn any stdio MCP server — your own mcp.ahk, or a node/python one
c := McpClient('"' A_AhkPath '" "C:\path\mcp.ahk"')
for t in c.ListTools()
    Print(t["name"])
res := c.CallTool("ast_outline", Map("file", "C:\x.ahk"))
Print(res["content"][1]["text"])
c.Close()
```

`McpClient` is modeled after the official SDK clients (TypeScript
`Client` + `StdioClientTransport`, Python `ClientSession`): it spawns the server
as a child process, runs the `initialize` handshake, then `ListTools()` /
`CallTool()` over newline-delimited JSON-RPC. It works against **any** stdio MCP
server, not just this one. See `examples/drive_server.ahk` for a full run.

(Transport is `WScript.Shell.Exec`, whose streams use the console codepage — best
for ASCII-safe payloads. A `CreateProcess` pipe transport would add full UTF-8.)

## Command line

`ahkmcp` runs any tool from the shell and prints the result (pretty JSON by
default, `--raw` for compact/pipeable). Launchers are path-relative, so the repo
can live anywhere — put `debugger-tool\mcp-ahk` on your PATH and:

```
ahkmcp list                                     list tools
ahkmcp ast_outline C:\proj\x.ahk                outline a file
ahkmcp get_source_context C:\proj\x.ahk 42 3    lines 39-45, line 42 flagged
ahkmcp workspace_symbols C:\proj query=Foo      find defs named *Foo*
ahkmcp server_status
ahkmcp ast_outline C:\proj\x.ahk --raw          compact JSON (pipe to jq)
```

- Windows / PowerShell: `ahkmcp.cmd`
- WSL / bash: `ahkmcp` (auto-translates `/mnt/...` path args to Windows form)

Args are positional per tool, or `key=value` in any order. It calls `MCP()`
in-process — no server, no protocol.

## Tools

| Tool | Arguments | Returns |
|------|-----------|---------|
| `ast_outline` | `file` | Tree-sitter symbol outline (kind/name/line/endLine/byte spans). Real parse via `TSParse`. |
| `get_source_context` | `file`, `line`, `radius?` | Source lines around `file:line`, target flagged. |
| `source_outline` | `file` | Functions / classes / hotkeys / labels in one file (regex). |
| `workspace_symbols` | `root?`, `query?`, `max_results?` | Function/class defs across `*.ahk` under a root. |
| `server_status` | — | Live server health: uptime, total requests, counts by method, per-tool call counts, errors, PID, engine version. |

> `ast_outline` reports `hasError: true` on valid fork code (typed Structs,
> fat-arrow methods, hotkeys) — the bundled grammar is incomplete, so treat the
> output as **structure only**. For "does it parse?", use the engine `check`.

## What's in the file

`mcp.ahk` contains, in one file: a JSON parser/stringifier (`class Json`), the
tool handlers, `MCP()` (call a tool as a function), `MCPServe()` (the stdio
JSON-RPC server loop), and `McpClient` (drive another MCP server). The server
starts only when the file is run as the main script.

`cli.ahk` + `ahkmcp` / `ahkmcp.cmd`: the command-line front-end and its launchers.

`examples/`: `outline.ahk` (use the tools as functions), `drive_server.ahk`
(AHK driving the script server as a client), and `native_verb.ahk` (AHK driving
the engine's built-in `mcp` verb — all five tools, no server script).

## Tests

```
bin\AutoHotkey64.exe debugger-tool\mcp-ahk\tests\test_json.ahk        # 38 codec tests
bin\AutoHotkey64.exe debugger-tool\mcp-ahk\tests\test_protocol.ahk    # 27 dispatch tests
bin\AutoHotkey64.exe debugger-tool\mcp-ahk\tests\test_tools.ahk       # 16 tool tests

# Native `mcp` verb: 42 protocol-conformance checks + differential tests that
# require every tool payload to deep-equal this script's output (from WSL):
python3 debugger-tool/mcp-ahk/tests/conformance_native.py bin/AutoHotkey64.exe
```

## Notes / limits

- JSON object key order is not preserved (AHK `Map` is unordered); irrelevant to
  MCP, which is key-addressed.
- Deferred: `check` (must shell to a throwaway process — in-process parsing has
  side-effects), `apply_fix`, `analyze_error`, and the DBGp live-debugger tools.

Deliberate divergences of the native `mcp` verb (native is the better behavior;
everything else is verified payload-identical by `tests/conformance_native.py`):

- Request lines are unbounded; this script's `ReadLine` caps at 64 KB and
  fragments longer requests into `-32700`s.
- Tool file reads are capped at 100 MB (`-32603`) so a pathological file cannot
  abort the process; this script has no cap.
- `workspace_symbols` never follows directory junctions/symlinks (cycles hang
  the scan); `Loop Files "R"` follows them.
- `workspace_symbols` default `root` is the process working directory, as the
  schema documents; this script's default is its own directory (script CWD).
