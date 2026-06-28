#Requires AutoHotkey v2.1-alpha.30
#Include mcp.ahk
/*
cli.ahk — command-line front-end for the AHK MCP tools.

Run a tool and print its result, no server / protocol involved (it calls MCP()
in-process). Use the ahkmcp.cmd / ahkmcp launchers so you can just type `ahkmcp`.

Usage:
  AutoHotkey64.exe cli.ahk <tool> [positional...] [key=value...] [--raw]
  AutoHotkey64.exe cli.ahk list          list available tools
  AutoHotkey64.exe cli.ahk help          this help

Examples:
  ahkmcp ast_outline C:\x.ahk
  ahkmcp get_source_context C:\x.ahk 42 3
  ahkmcp workspace_symbols C:\proj query=Foo max_results=50
  ahkmcp server_status
*/

; positional-argument order per tool (anything can also be given as key=value)
global POSITIONAL := Map(
    "ast_outline",        ["file"],
    "source_outline",     ["file"],
    "get_source_context", ["file", "line", "radius"],
    "workspace_symbols",  ["root", "query", "max_results"],
    "server_status",      [])

global STDERR := FileOpen("**", "w", "UTF-8")

main()

main() {
    if (A_Args.Length < 1 || A_Args[1] = "help" || A_Args[1] = "--help" || A_Args[1] = "-h") {
        Usage()
        ExitApp(0)
    }
    tool := A_Args[1]

    reg := BuildToolRegistry()
    if (tool = "list") {
        for name, spec in reg
            Print(Format("{:-20} {}", name, spec.description))
        ExitApp(0)
    }
    if (!reg.Has(tool)) {
        Fail("unknown tool: " tool "  (run 'list' to see tools)", 2)
    }

    raw := false
    args := Map()
    posNames := POSITIONAL.Has(tool) ? POSITIONAL[tool] : []
    posIdx := 1
    i := 2
    while (i <= A_Args.Length) {
        a := A_Args[i++]
        if (a = "--raw")
            raw := true
        else if (InStr(a, "=")) {
            eq := InStr(a, "=")
            args[SubStr(a, 1, eq - 1)] := SubStr(a, eq + 1)
        } else if (posIdx <= posNames.Length)
            args[posNames[posIdx++]] := a
        else
            Fail("unexpected argument: " a, 2)
    }

    try
        result := MCP(tool, args)
    catch as e
        Fail("error: " e.Message, 1)

    Print(raw ? Json.Stringify(result) : Pretty(result))
    ExitApp(0)
}

Fail(msg, code) {
    STDERR.Write(msg "`n")
    ExitApp(code)
}

Usage() {
    Print("AHK MCP command-line tool")
    Print("")
    Print("  ahkmcp <tool> [positional...] [key=value...] [--raw]")
    Print("  ahkmcp list            list available tools")
    Print("  ahkmcp help            this help")
    Print("")
    Print("Examples:")
    Print("  ahkmcp ast_outline C:\path\file.ahk")
    Print("  ahkmcp get_source_context C:\path\file.ahk 42 3")
    Print("  ahkmcp workspace_symbols C:\proj query=Foo max_results=50")
    Print("  ahkmcp server_status")
    Print("")
    Print("  --raw   emit compact JSON (default: pretty-printed)")
}

; pretty-print a parsed JSON value (Map/Array/primitive/sentinel)
Pretty(v, indent := "") {
    if (IsObject(v) && !v.HasOwnProp("__json")) {
        t := Type(v)
        if (t = "Map") {
            if (v.Count = 0)
                return "{}"
            inner := indent "  ", out := "{`n", sep := ""
            for k, val in v {
                out .= sep inner Json.Stringify(String(k)) ": " Pretty(val, inner)
                sep := ",`n"
            }
            return out "`n" indent "}"
        }
        if (t = "Array") {
            if (v.Length = 0)
                return "[]"
            inner := indent "  ", out := "[`n", sep := ""
            for val in v {
                out .= sep inner Pretty(val, inner)
                sep := ",`n"
            }
            return out "`n" indent "]"
        }
    }
    return Json.Stringify(v)        ; primitives & true/false/null
}
