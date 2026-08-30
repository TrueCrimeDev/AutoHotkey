#Requires AutoHotkey v2.1-alpha.30
#SingleInstance Off
#Include ..\mcp.ahk
/*
native_verb.ahk — drive the MCP server that lives INSIDE the engine binary.

`AutoHotkey64.exe mcp` (source/mcp_server.cpp) is a complete stdio MCP server:
no script file, no runtime — the exe is the server. This example spawns a second
engine process in that mode via McpClient, runs the initialize handshake, then
uses every native tool to analyze THIS script and its own repo.

Run:  bin\AutoHotkey64.exe debugger-tool\mcp-ahk\examples\native_verb.ahk
*/

; A small class + functions, so the outline tools below have symbols to find.
class DemoReport {
    Header(title) {
        Print("")
        Print(title)
    }
    Sym(s) {
        Print("  {:-8} {:-20} lines {}-{}  bytes {}-{}", s["kind"], s["name"], s["line"], s["endLine"], s["startByte"], s["endByte"])
    }
}

JoinCounts(counts) {
    line := ""
    for key, n in counts
        line .= Format("{}{} x{}", (line = "" ? "" : ", "), key, n)
    return line
}

report := DemoReport()
c := McpClient('"' A_AhkPath '" mcp')
Print("connected: {} v{} (the engine itself, no server script)", c.serverInfo["name"], c.serverInfo["version"])

; ---- tools/list ----------------------------------------------------------
names := ""
for t in c.ListTools()
    names .= (names = "" ? "" : ", ") t["name"]
Print("tools:     {}", names)

; ---- ast_outline: real tree-sitter parse of this very file ---------------
res := c.CallTool("ast_outline", Map("file", A_LineFile))
out := Json.Parse(res["content"][1]["text"])
report.Header(Format("ast_outline of {} - {} symbols (real parse):", A_ScriptName, out["count"]))
for s in out["symbols"]
    report.Sym(s)

; ---- source_outline: the fast regex scan of the same file ----------------
res := c.CallTool("source_outline", Map("file", A_LineFile))
so := Json.Parse(res["content"][1]["text"])
report.Header(Format("source_outline of {} - {} symbols (regex scan):", A_ScriptName, so["count"]))
for s in so["symbols"]
    Print("  {:-8} {:-20} line {}", s["kind"], s["name"], s["line"])

; ---- get_source_context: the lines around THIS line ----------------------
res := c.CallTool("get_source_context", Map("file", A_LineFile, "line", A_LineNumber, "radius", 2))
ctx := Json.Parse(res["content"][1]["text"])
report.Header(Format("get_source_context {}:{} (of {} lines):", A_ScriptName, ctx["line"], ctx["total"]))
for row in ctx["context"]
    Print(" {}{:4}| {}", (row["isTarget"] = Json.True) ? ">" : " ", row["line"], row["text"])

; ---- workspace_symbols: find Mcp* definitions across the project ---------
res := c.CallTool("workspace_symbols", Map("root", A_ScriptDir "\..", "query", "Mcp", "max_results", 8))
ws := Json.Parse(res["content"][1]["text"])
report.Header(Format("workspace_symbols query='Mcp' - {} hit(s){}:", ws["count"], (ws["truncated"] = Json.True) ? " (truncated at max_results)" : ""))
for s in ws["symbols"]
    Print("  {:-8} {:-20} {}:{}", s["kind"], s["name"], s["file"], s["line"])

; ---- protocol errors surface as clean exceptions, not dead servers -------
Print("")
try
    c.CallTool("ast_outline", Map("file", "C:\nope\missing.ahk"))
catch as e
    Print("error handling: {}", e.Message)

; ---- server_status: the server audits the conversation we just had -------
res := c.CallTool("server_status")
st := Json.Parse(res["content"][1]["text"])
report.Header(Format("server_status: engine {} pid {} uptime {}s - {} requests, {} error(s)", st["ahkVersion"], st["pid"], st["uptimeSeconds"], st["requests"], st["errors"]))
Print("  byMethod:  {}", JoinCounts(st["byMethod"]))
Print("  toolCalls: {}", JoinCounts(st["toolCalls"]))

c.Close()
Print("")
Print("server closed cleanly (stdin EOF -> exit 0)")
