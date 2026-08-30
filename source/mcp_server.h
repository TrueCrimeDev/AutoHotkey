#pragma once

// `AutoHotkey64.exe mcp` — a native stdio MCP server (newline-delimited JSON-RPC
// 2.0). Behavior mirrors debugger-tool/mcp-ahk/mcp.ahk, the reference
// implementation, so the same conformance tests drive both. Runs before any
// script is loaded: no windows, no hooks, no message pump.
// Returns the process exit code (0 on clean stdin EOF).
int McpServerMain();
