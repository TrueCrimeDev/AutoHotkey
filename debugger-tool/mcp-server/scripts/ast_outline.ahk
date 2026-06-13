#Requires AutoHotkey v2.1-alpha.30
/*
ast_outline.ahk — emit a tree-sitter outline of an AHK file as JSON on stdout.

Used by the MCP server's `ast_outline` tool. Requires a TSParse-enabled engine
(the native BIF). Output shape:
  {"hasError":0,"count":N,"symbols":[
     {"kind":"class","name":"Foo","line":3,"endLine":20,"startByte":..,"endByte":..}, ...]}

Usage: AutoHotkey64.exe ast_outline.ahk <absolute-file-path>
*/

global symbols := []

try {
    if (A_Args.Length < 1) {
        Print('{"error":"no file argument"}')
        ExitApp(2)
    }
    src := FileRead(A_Args[1])
    tree := TSParse(src)
    Collect(tree.Root)

    out := '{"hasError":' (tree.HasError ? 1 : 0) ',"count":' symbols.Length ',"symbols":['
    sep := ""
    for s in symbols {
        out .= sep s
        sep := ","
    }
    out .= "]}"
    Print(out)
    ExitApp(0)
} catch as e {
    Print('{"error":"' Esc(e.Message) '"}')
    ExitApp(3)
}

Collect(node) {
    global symbols
    for child in node.NamedChildren {
        kind := ""
        switch child.Type {
        case "function_declaration": kind := "function"
        case "class_declaration":    kind := "class"
        case "method_declaration":   kind := "method"
        case "property_declaration": kind := "property"
        }
        if (kind != "") {
            obj := '{"kind":"' kind '","name":"' Esc(GetName(child)) '"'
            obj .= ',"line":' (child.StartRow + 1)
            obj .= ',"endLine":' (child.EndRow + 1)
            obj .= ',"startByte":' child.StartByte
            obj .= ',"endByte":' child.EndByte "}"
            symbols.Push(obj)
        }
        Collect(child)
    }
}

GetName(node) {
    for c in node.NamedChildren
        if (c.Type = "identifier")
            return Trim(c.Text)
    return ""
}

Esc(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`t", "\t")
    return s
}
