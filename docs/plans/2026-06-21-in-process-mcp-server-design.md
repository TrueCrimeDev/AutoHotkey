# In-Process MCP Server (native AHK, hosted by autohotkey.exe)

Date: 2026-06-21
Status: Approved (design) — pending implementation plan
Branch target: `alpha`

## Summary

A pure-AHK Model Context Protocol (MCP) server that runs **inside** a normal
`AutoHotkey64.exe` process. It is started by calling a function — `MCPServe(tools)` —
which takes over stdin/stdout and runs a JSON-RPC loop until the input stream closes.

No Node.js, no embedded JS engine, no engine (C++) rebuild. The server logic is
ordinary AHK v2 running in the AHK interpreter, using fork BIFs (`Print`, `TSParse`,
`_ScriptGetLines`) and standard file I/O.

An MCP client (Claude Code / Cursor) launches it exactly like any stdio MCP server:

```
AutoHotkey64.exe  debugger-tool\mcp-ahk\server.ahk
```

## Goals

- `MCPServe(tools)` — a callable function that turns the current AHK process into a
  working MCP server over stdio.
- Serve a useful first set of **source-intelligence** tools that are naturally
  implemented in AHK (they mostly call *into* AHK).
- Zero new runtime dependencies; self-contained under `debugger-tool/mcp-ahk/`.
- Headless-testable from WSL via the fork `AutoHotkey64.exe`.

## Non-Goals (this iteration)

- Bundling the existing Node/TypeScript server into a standalone `.exe` (dropped).
- Embedding Node/libnode or QuickJS into the C++ fork (rejected: huge binary,
  MSVC/CI build pain, dual event-loop hazards; poor fit since tools call into AHK).
- DBGp live-debugger tools (`debug_*`, `breakpoint_*`, `variables_get`,
  `capture_error`) — they require a connection to a *separate* debuggee.
- `analyze_error` / `apply_fix` (network + verified edits) — phase 2.

## Architecture

```
MCP client (Claude Code / Cursor)
        │  stdio, newline-delimited JSON-RPC 2.0
        ▼
AutoHotkey64.exe  ── server.ahk ──> MCPServe(tools)
        │
        ├── lib/Mcp.ahk    transport + JSON-RPC/MCP dispatch loop
        ├── lib/Json.ahk   JSON parse + stringify (no external dep)
        └── lib/Tools.ahk  native AHK tool handlers
```

Single-threaded and synchronous — matches the AHK interpreter model and avoids the
threading hazards the Node-embed path would have introduced.

## File Layout

```
debugger-tool/mcp-ahk/
  server.ahk        ; entry point: builds the tool registry, calls MCPServe(tools)
  lib/Mcp.ahk       ; MCPServe() + JSON-RPC/MCP dispatch
  lib/Json.ahk      ; minimal JSON parse + stringify
  lib/Tools.ahk     ; native AHK tool handlers
  tests/            ; headless tests (Json round-trip, scripted-stdin protocol)
  README.md         ; how to register with a client; tool reference
```

## Components & Interfaces

### `Json.ahk`

The one genuinely new building block — the repo has no JSON library, and incoming
requests must be parsed.

- `Json.Parse(text)` → AHK value (`Map` for objects, `Array` for arrays, `String`,
  `Number`, `true`/`false` via `1`/`0` or dedicated tokens, `""`/unset for null).
- `Json.Stringify(value)` → compact JSON string. Objects are `Map`; arrays are
  `Array`. Handles string escaping (`" \ / b f n r t`, `\uXXXX`).
- Self-contained, ~150 lines, no dependencies. Unit-tested by round-trip.

Note: AHK v2 `Map` is **unordered**, so object key order is not preserved in
output. This is irrelevant to MCP (key-addressed), but tests must verify objects
by re-parsing rather than matching a literal string.

### `Mcp.ahk` — `MCPServe(tools)`

- Signature: `MCPServe(tools, opts?)`.
  - `tools` — a `Map` of `name → { description, inputSchema, handler }` where
    `handler` is `(args) => result`. `args` is the parsed `arguments` object (`Map`).
    `inputSchema` is an AHK `Map` mirroring a JSON Schema object.
  - `opts` (optional) — `{ name, version }` for the `serverInfo` block.
- Behavior:
  1. Open stdin `FileOpen("*", "r", "UTF-8")` and stdout `FileOpen("*", "w", "UTF-8")`.
  2. Loop: read one line (newline-delimited JSON-RPC). On EOF, return.
  3. `Json.Parse` the line; dispatch by `method`.
  4. Write exactly one framed JSON line per request that has an `id`. Notifications
     (no `id`) produce no response.
- Methods handled:
  - `initialize` → `{ protocolVersion, capabilities: { tools: {} }, serverInfo }`.
  - `notifications/initialized` → no response.
  - `ping` → `{}`.
  - `tools/list` → `{ tools: [ { name, description, inputSchema } ... ] }`.
  - `tools/call` → look up `params.name` in `tools`, run `handler(params.arguments)`,
    wrap as `{ content: [ { type: "text", text: <result> } ], isError: false }`.
- Output discipline: **nothing but framed JSON is ever written to stdout.** Tool
  handlers must not `Print` to stdout; diagnostics (if any) go to stderr (`**`).

### `Tools.ahk`

Plain functions, one per tool, returning a string (usually JSON text the client can
render). v1 set:

| Tool | Input | Implementation |
|------|-------|----------------|
| `ast_outline` | `{ file }` | `TSParse()` outline — reuse existing `scripts/ast_outline.ahk` logic |
| `get_source_context` | `{ file, line, radius? }` | `FileRead` + slice; `_ScriptGetLines` where applicable |
| `source_outline` | `{ file }` | functions / classes / hotkeys / labels from one file |
| `workspace_symbols` | `{ root?, query?, max_results? }` | `Loop Files *.ahk`, outline each, filter |

### `server.ahk`

```ahk
#Requires AutoHotkey v2.1-alpha.30
#Include lib/Json.ahk
#Include lib/Mcp.ahk
#Include lib/Tools.ahk

tools := Map()
tools["ast_outline"]        := { description: "...", inputSchema: ..., handler: Tool_AstOutline }
tools["get_source_context"] := { ... }
tools["source_outline"]     := { ... }
tools["workspace_symbols"]  := { ... }

MCPServe(tools, { name: "ahk-mcp", version: "0.1.0" })
```

## Request Lifecycle

1. Client writes one JSON line to the process's stdin.
2. `MCPServe` reads the line, `Json.Parse` → request `Map`.
3. Dispatch by `method`; for `tools/call`, resolve handler in the `tools` `Map`.
4. Run handler → result string.
5. Wrap as MCP result, `Json.Stringify`, write one line to stdout.

## Error Handling

| Condition | JSON-RPC error |
|-----------|----------------|
| Malformed JSON line | `-32700` Parse error |
| Unknown `method` | `-32601` Method not found |
| Unknown tool name | `-32602` Invalid params |
| Handler throws | `-32603` Internal error (message = exception text) |

A handler exception may alternatively be returned as `tools/call` content with
`isError: true` — chosen per-tool; default is `-32603`.

## Testing

- **`Json.ahk`**: round-trip unit tests (objects, nested arrays, escapes, numbers,
  null/bool) — assert `Parse(Stringify(x)) == x` and known-string fixtures.
- **`Mcp.ahk`**: scripted-stdin protocol test — pipe `initialize`,
  `notifications/initialized`, `tools/list`, and a `tools/call` into
  `AutoHotkey64.exe server.ahk`, assert the framed responses. Runs headless in WSL.
- All tests runnable via the fork `bin/AutoHotkey64.exe`.

## Phasing

1. **v1 (this spec):** `Json.ahk`, `MCPServe`, the four source-intelligence tools,
   `server.ahk`, tests, README.
2. **Later:** `check` (shell to throwaway `AutoHotkey64.exe check`), `apply_fix`,
   `analyze_error` (WinHTTP). DBGp tools remain out of scope for the in-process model.

## Addendum: HTTP transport (added on request)

The server also exposes an **HTTP transport** so any script can call it like a web
request, not only an MCP client over stdio. Both transports share `_McpHandle()`
— dispatch, tools, and JSON are identical.

- `MCPServeHttp(tools, port, opts?)` — a Winsock TCP listener on `127.0.0.1:port`
  speaking minimal HTTP/1.1. One JSON-RPC message per request body; `Connection:
  close`. No SSE / sessions (that's the MCP Streamable HTTP spec — deferred until
  an MCP client needs HTTP).
- Consumer: arbitrary scripts (AHK `WinHttpRequest`, curl, Python). Spec-compliant
  MCP-over-HTTP for Claude/Cursor is out of scope for this iteration.
- Single entry `mcp-server.ahk` picks the transport: stdio by default, `--http
  [port]` for HTTP.
- Integration-tested by `tests/http_client.ahk` against a live listener.

File layout updated: the per-transport entry scripts collapsed into one
`mcp-server.ahk`; the tool registry + schema helpers moved into `lib/Tools.ahk`
(`BuildToolRegistry()`); the HTTP transport lives alongside stdio in `lib/Mcp.ahk`.

## Open Items / Assumptions

- Standalone Node-exe bundle is dropped (confirmed by "Go ahead").
- v1 tool set is the four source-intelligence tools (`check`/`apply_fix` deferred).
- MCP stdio framing is newline-delimited JSON-RPC 2.0 (not LSP Content-Length).
- HTTP transport is simple JSON-RPC-over-POST (localhost), not MCP Streamable HTTP.
