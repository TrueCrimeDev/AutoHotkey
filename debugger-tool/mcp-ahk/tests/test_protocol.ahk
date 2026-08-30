#Requires AutoHotkey v2.1-alpha.30
#Include ..\mcp.ahk
/*
test_protocol.ahk — drives the MCP dispatch (_McpHandle) directly with JSON-RPC
request lines and asserts on the parsed responses. No stdin/stdout piping, so it
runs headless and deterministically.
Run:  AutoHotkey64.exe test_protocol.ahk      (exit 0 = pass, 1 = fail)
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

; Reply to a request line; return the parsed response Map ("" -> empty Map).
Reply(line) {
    global TOOLS
    resp := _McpHandle(line, TOOLS, "ahk-mcp", "0.1.0")
    return (resp = "") ? Map() : Json.Parse(resp)
}

; --- registry under test ---
global TOOLS := Map()
TOOLS["ast_outline"]   := { description: "outline", inputSchema: Map(), handler: Tool_AstOutline }
TOOLS["echo"]          := { description: "echo",    inputSchema: Map(), handler: (a) => "echoed:" (a.Has("msg") ? a["msg"] : "") }
TOOLS["server_status"] := { description: "status",  inputSchema: Map(), handler: Tool_ServerStatus }

; --- initialize ---
r := Reply('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}')
Check("init.id",        r["id"],                          1)
Check("init.proto",     r["result"]["protocolVersion"],   "2025-06-18")
Check("init.name",      r["result"]["serverInfo"]["name"], "ahk-mcp")
Check("init.caps",      r["result"]["capabilities"].Has("tools") ? "T" : "F", "T")

; --- notification: no response ---
r := Reply('{"jsonrpc":"2.0","method":"notifications/initialized"}')
Check("notif.empty",    r.Count,   0)

; --- ping ---
r := Reply('{"jsonrpc":"2.0","id":2,"method":"ping"}')
Check("ping.id",        r["id"],   2)
Check("ping.result",    r["result"].Count,   0)

; --- tools/list ---
r := Reply('{"jsonrpc":"2.0","id":3,"method":"tools/list"}')
list := r["result"]["tools"]
Check("list.count",     list.Length,   3)
names := ""
for t in list
    names .= t["name"] ","
Check("list.has-ast",   InStr(names, "ast_outline") ? "T" : "F",   "T")
Check("list.has-echo",  InStr(names, "echo") ? "T" : "F",          "T")

; --- tools/call: echo ---
r := Reply('{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"echo","arguments":{"msg":"hi"}}}')
Check("call.text",      r["result"]["content"][1]["text"],   "echoed:hi")
Check("call.notErr",    r["result"]["isError"] == Json.False ? "T" : "F",   "T")
Check("call.type",      r["result"]["content"][1]["type"],   "text")

; --- tools/call: ast_outline on a temp file ---
tmp := A_Temp "\mcp_ast_test.ahk"
try FileDelete(tmp)
FileAppend("class Foo {`n    Bar() {`n    }`n}`n`nBaz() {`n}`n", tmp, "UTF-8")
r := Reply('{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"ast_outline","arguments":{"file":"' StrReplace(tmp, "\", "\\") '"}}}')
astText := r["result"]["content"][1]["text"]
ast := Json.Parse(astText)
Check("ast.countMatch", ast["count"] == ast["symbols"].Length ? "T" : "F",   "T")
Check("ast.hasSymbols", ast["symbols"].Length >= 1 ? "T" : "F",              "T")
foundFoo := false
for s in ast["symbols"]
    if (s["name"] = "Foo")
        foundFoo := true
Check("ast.foundFoo",   foundFoo ? "T" : "F",   "T")
try FileDelete(tmp)

; --- errors ---
r := Reply('{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"nope","arguments":{}}}')
Check("err.unknownTool", r["error"]["code"],   -32602)

r := Reply('{"jsonrpc":"2.0","id":7,"method":"does/notexist"}')
Check("err.method",     r["error"]["code"],    -32601)

r := Reply('{bad json')
Check("err.parse",      r["error"]["code"],    -32700)

r := Reply('{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{}}')
Check("err.noName",     r["error"]["code"],    -32602)

; non-string method/name must not crash the dispatcher (JSON-RPC: method is a string)
r := Reply('{"jsonrpc":"2.0","id":10,"method":true}')
Check("err.boolMethod",   r["error"]["code"],  -32600)
r := Reply('{"jsonrpc":"2.0","method":null}')
Check("err.nullMethod",   r["error"]["code"],  -32600)
r := Reply('{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":true}}')
Check("err.boolToolName", r["error"]["code"],  -32602)

; --- server_status reports live stats ---
r := Reply('{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"server_status","arguments":{}}}')
st := Json.Parse(r["result"]["content"][1]["text"])
Check("status.hasUptime",  st.Has("uptimeSeconds") ? "T" : "F",   "T")
Check("status.requests",   st["requests"] >= 1 ? "T" : "F",       "T")
Check("status.toolCount",  st["toolsRegistered"] >= 4 ? "T" : "F","T")
Check("status.countedSelf", st["toolCalls"]["server_status"] >= 1 ? "T" : "F", "T")

Print("")
Print(Format("{}/{} passed, {} failed", gRun - gFails, gRun, gFails))
ExitApp(gFails > 0 ? 1 : 0)
