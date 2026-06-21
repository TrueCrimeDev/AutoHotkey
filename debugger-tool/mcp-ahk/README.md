# mcp.ahk — an MCP server that runs inside AutoHotkey64.exe

**One self-contained file. No includes, no separate runtime.** It runs inside the
AutoHotkey process (the script *is* the server), and its tools are also callable
as a plain function.

Requires the fork engine (`bin/AutoHotkey64.exe`, `2.1-alpha.30+Console`) for the
`TSParse` / `Print` BIFs.

## Two ways to use it

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

`mcp.ahk` contains, in one file: a JSON parser/stringifier (`class Json`), the four
tool handlers, `MCP()` (call a tool as a function), and `MCPServe()` (the stdio
JSON-RPC loop). The server starts only when the file is run as the main script.

## Tests

```
bin\AutoHotkey64.exe debugger-tool\mcp-ahk\tests\test_json.ahk        # 38 codec tests
bin\AutoHotkey64.exe debugger-tool\mcp-ahk\tests\test_protocol.ahk    # 20 dispatch tests
```

## Notes / limits

- JSON object key order is not preserved (AHK `Map` is unordered); irrelevant to
  MCP, which is key-addressed.
- Deferred: `check` (must shell to a throwaway process — in-process parsing has
  side-effects), `apply_fix`, `analyze_error`, and the DBGp live-debugger tools.
