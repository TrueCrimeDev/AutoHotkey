#Requires AutoHotkey v2.1-alpha.30
#Include ..\mcp.ahk
/*
test_tools.ahk — exercises every tool through the MCP() function API against a
known fixture file. Verifies the tools as functions (not just dispatch).
Run:  AutoHotkey64.exe test_tools.ahk      (exit 0 = pass, 1 = fail)
*/

global gFails := 0, gRun := 0

Check(label, got, want) {
    global gFails, gRun
    gRun++
    if (got == want)
        Print(Format("ok   {}", label))
    else {
        gFails++
        Print(Format("FAIL {}  want={} got={}", label, want, got))
    }
}

HasSym(arr, kind, name) {
    for s in arr
        if (s["kind"] = kind && s["name"] = name)
            return true
    return false
}

HasKind(arr, kind) {
    for s in arr
        if (s["kind"] = kind)
            return true
    return false
}

; --- build an isolated fixture (own dir, so workspace_symbols stays clean) ---
dir := A_Temp "\mcp_tools_test"
try DirDelete(dir, true)
DirCreate(dir)
fix := dir "\fixture.ahk"
lines := [
    "class Animal {",          ; 1
    "    Speak() {",           ; 2
    "    }",                   ; 3
    "    Name {",              ; 4
    "        get => this._n",  ; 5
    "    }",                   ; 6
    "}",                       ; 7
    "",                        ; 8
    "Greet(who) {",            ; 9
    '    return "hi " who',    ; 10
    "}",                       ; 11
    "",                        ; 12
    "^j::Reload()",            ; 13
    "",                        ; 14
    "MyLabel:",                ; 15
    "return"                   ; 16
]
src := ""
for i, ln in lines
    src .= (i = 1 ? "" : "`n") ln      ; join, no trailing newline -> 16 lines exactly
FileAppend(src, fix, "UTF-8")

; --- ast_outline (accurate, TSParse) ---
ast := MCP("ast_outline", Map("file", fix))
Check("ast.countMatch", ast["count"] == ast["symbols"].Length ? "T" : "F", "T")
Check("ast.class",      HasSym(ast["symbols"], "class", "Animal") ? "T" : "F", "T")
Check("ast.function",   HasSym(ast["symbols"], "function", "Greet") ? "T" : "F", "T")

; --- get_source_context ---
ctx := MCP("get_source_context", Map("file", fix, "line", 9, "radius", 1))
Check("ctx.len",        ctx["context"].Length, 3)            ; lines 8,9,10
Check("ctx.total",      ctx["total"], 16)
target := ""
for c in ctx["context"]
    if (c["isTarget"] == Json.True)
        target := c["text"] . "@" . c["line"]
Check("ctx.target",     target, "Greet(who) {@9")

; --- source_outline (fast regex) ---
so := MCP("source_outline", Map("file", fix))
Check("so.class",   HasSym(so["symbols"], "class", "Animal") ? "T" : "F", "T")
Check("so.function",HasSym(so["symbols"], "function", "Greet") ? "T" : "F", "T")
Check("so.hotkey",  HasKind(so["symbols"], "hotkey") ? "T" : "F", "T")
Check("so.label",   HasKind(so["symbols"], "label") ? "T" : "F", "T")

; --- workspace_symbols (scoped to the fixture dir) ---
ws := MCP("workspace_symbols", Map("root", dir, "query", "Greet"))
Check("ws.found",   HasSym(ws["symbols"], "function", "Greet") ? "T" : "F", "T")
Check("ws.scoped",  ws["count"] >= 1 ? "T" : "F", "T")

; --- server_status returns the expected shape ---
st := MCP("server_status")
Check("status.uptime",   st.Has("uptimeSeconds") ? "T" : "F", "T")
Check("status.requests", st.Has("requests") ? "T" : "F", "T")
Check("status.tools",    st["toolsRegistered"] >= 5 ? "T" : "F", "T")

; --- unknown tool throws ---
threw := false
try MCP("does_not_exist", Map())
catch
    threw := true
Check("mcp.throws", threw ? "T" : "F", "T")

try DirDelete(dir, true)

Print("")
Print(Format("{}/{} passed, {} failed", gRun - gFails, gRun, gFails))
ExitApp(gFails > 0 ? 1 : 0)
