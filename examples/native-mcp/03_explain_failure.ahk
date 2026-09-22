#Requires AutoHotkey v2.1-alpha.31
#Include McpClient.ahk
; Use case: turn a failed run into an error report with the exact nearby source.
; Whitespace-only input deliberately triggers the sample worker's validation.
mcp := McpClient()
try {
    result := mcp.Call("run", McpArgs("file", A_ScriptDir "\sample\clean_text.ahk", "args", ["   "], "timeout_ms", 5000))
    if result["ok"] || result["timedOut"] || result["exitCode"] != 10
        throw Error("Expected a normal runtime error: " JSON.Stringify(result))
    if !result["diagnostics"].Length
        throw Error("No structured diagnostic returned.")
    for diagnostic in result["diagnostics"] {
        Print("{}: {}", diagnostic["type"], diagnostic["message"])
        Print("At {}:{}", diagnostic["file"], diagnostic["line"])
        context := mcp.Call("get_source_context", McpArgs("file", diagnostic["file"], "line", diagnostic["line"], "radius", 3))
        PrintContext(context)
    }
    Print("`nExpected failure captured successfully; the MCP session is still usable.")
    mcp.Call("server_status")
} finally {
    mcp.Close()
}
