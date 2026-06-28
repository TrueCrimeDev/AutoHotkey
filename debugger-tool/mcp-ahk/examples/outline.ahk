#Requires AutoHotkey v2.1-alpha.30
#Include ..\mcp.ahk
/*
outline.ahk — print the symbol outline of an AHK file, then show the source
around the first symbol. A practical use of the in-process MCP server as a
plain function: MCP(tool, args) returns a normal AHK Map.

Usage:  AutoHotkey64.exe outline.ahk [C:\path\to\file.ahk]
        (defaults to this script if no path is given)
*/

file := A_Args.Length >= 1 ? A_Args[1] : A_ScriptFullPath

; --- 1. outline: accurate tree-sitter parse, returned as an AHK Map ---
ast := MCP("ast_outline", Map("file", file))

Print(Format("{}  —  {} symbols", file, ast["count"]))
Print("")
for s in ast["symbols"] {
    indent := (s["kind"] = "method" || s["kind"] = "property") ? "    " : ""
    Print(Format("{1}{2:-9} {3}  (L{4}-{5})", indent, s["kind"], s["name"], s["line"], s["endLine"]))
}

; --- 2. source context around the first symbol ---
if (ast["symbols"].Length >= 1) {
    first := ast["symbols"][1]
    Print("")
    Print(Format("--- source around '{}' (line {}) ---", first["name"], first["line"]))
    ctx := MCP("get_source_context", Map("file", file, "line", first["line"], "radius", 2))
    for c in ctx["context"] {
        mark := (c["isTarget"] == Json.True) ? ">" : " "
        Print(Format("{1} {2:4} {3}", mark, c["line"], c["text"]))
    }
}
