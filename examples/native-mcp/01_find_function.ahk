#Requires AutoHotkey v2.1-alpha.31
#Include McpClient.ahk
; Use case: find an unfamiliar function, then read its implementation.
mcp := McpClient()
try {
    status := mcp.Call("server_status")
    Print("Connected: {} | {} tools discovered", status["ahkVersion"], mcp.Tools.Length)
    root := A_ScriptDir "\sample"
    matches := mcp.Call("workspace_symbols", McpArgs("root", root, "query", "CleanText", "max_results", 10))
    if !matches["count"]
        throw Error("Expected to find CleanText in the sample project.")
    hit := matches["symbols"][1]
    Print("`nFound {} at {}:{}", hit["name"], hit["file"], hit["line"])
    outline := mcp.Call("source_outline", McpArgs("file", hit["file"]))
    Print("Fast outline: {} definition(s)", outline["count"])
    ast := mcp.Call("ast_outline", McpArgs("file", hit["file"]))
    if !ast["count"]
        throw Error("Expected an AST definition for the sample function.")
    for symbol in ast["symbols"]
        Print("AST: {} {} spans lines {}-{}", symbol["kind"], symbol["name"], symbol["line"], symbol["endLine"])
    context := mcp.Call("get_source_context", McpArgs("file", hit["file"], "line", hit["line"], "radius", 5))
    Print("`nSource context:")
    PrintContext(context)
} finally {
    mcp.Close()
}
