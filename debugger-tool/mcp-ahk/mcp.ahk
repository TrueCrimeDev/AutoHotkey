#Requires AutoHotkey v2.1-alpha.30
#SingleInstance Off  ; stdio MCP servers spawn once per client; default Prompt deadlocks a 2nd launch
/*
mcp.ahk — a self-contained MCP server that runs inside AutoHotkey64.exe.

ONE file, no includes. Two ways to use it:

  1. Run it in the exe as an MCP server (stdio, for Claude Code / Cursor):
         AutoHotkey64.exe mcp.ahk

  2. Call a tool as a plain function from your own script:
         out := MCP("ast_outline", Map("file", "C:\path\x.ahk"))
         MsgBox out["count"]            ; out is a normal AHK Map
     (To call MCP() from a separate script, drop this file in the exe's Lib\
      folder and use  #Include <mcp>  — a single pathless line. The only way to
      need NO include at all is to bake MCP() into the engine as a C++ BIF.)

Tools (all native AHK — they call into TSParse / FileRead, so they belong here,
not in a separate runtime):
  ast_outline · get_source_context · source_outline · workspace_symbols

Requires the fork engine (TSParse / Print BIFs).
*/

; =========================================================================
;  Run-as-server (only when this file is the main script, not when included)
; =========================================================================

if (A_LineFile = A_ScriptFullPath)
    MCPServe(BuildToolRegistry(), { name: "ahk-mcp", version: "0.1.0" })

; =========================================================================
;  MCP() — run a tool as a function, get an AHK value back
; =========================================================================

MCP(name, args := "") {
    static reg := BuildToolRegistry()
    if (!reg.Has(name))
        throw ValueError("Unknown tool: " name, , name)
    return Json.Parse(reg[name].handler.Call(IsObject(args) ? args : Map()))
}

; =========================================================================
;  McpClient — drive an MCP server from AHK (the standard cross-language way)
; =========================================================================
;
; Modeled after the official SDK clients (TypeScript Client + StdioClientTransport,
; Python ClientSession + stdio_client): spawn a server process, run the initialize
; handshake, then ListTools() / CallTool(). Talks newline-delimited JSON-RPC over
; the child's stdin/stdout via WScript.Shell.Exec. Works against ANY stdio MCP
; server — your own mcp.ahk, or a Node/Python one.
;
;   c := McpClient('"' A_AhkPath '" "C:\path\mcp.ahk"')   ; or a node/python command
;   for t in c.ListTools()
;       Print(t["name"])
;   res := c.CallTool("ast_outline", Map("file", "C:\x.ahk"))
;   Print(res["content"][1]["text"])
;   c.Close()
;
; Note: WScript.Shell streams use the console codepage, so this is best for
; ASCII-safe payloads (tool names, ASCII paths). For full UTF-8, a CreateProcess
; pipe transport would be the next step.

class McpClient {
    __New(command, clientName := "ahk-mcp-client", clientVersion := "0.1.0") {
        this.exec := ComObject("WScript.Shell").Exec(command)
        this.nextId := 0
        this.serverInfo := Map()
        res := this.Request("initialize", Map(
            "protocolVersion", "2025-06-18",
            "capabilities", Map(),
            "clientInfo", Map("name", clientName, "version", clientVersion)))
        this.serverInfo := res.Has("serverInfo") ? res["serverInfo"] : Map()
        this.Notify("notifications/initialized")        ; required post-handshake notification
    }

    ; JSON-RPC request (has id) -> returns the result, throws on a protocol error.
    Request(method, params := "") {
        msg := Map("jsonrpc", "2.0", "id", ++this.nextId, "method", method)
        if (IsObject(params))
            msg["params"] := params
        this.exec.StdIn.WriteLine(Json.Stringify(msg))
        resp := Json.Parse(this._ReadLine())
        if (resp.Has("error"))
            throw Error("MCP error " resp["error"]["code"] ": " resp["error"]["message"])
        return resp.Has("result") ? resp["result"] : Map()
    }

    ; JSON-RPC notification (no id, no response).
    Notify(method, params := "") {
        msg := Map("jsonrpc", "2.0", "method", method)
        if (IsObject(params))
            msg["params"] := params
        this.exec.StdIn.WriteLine(Json.Stringify(msg))
    }

    ListTools() => this.Request("tools/list")["tools"]

    CallTool(name, args := "") {
        return this.Request("tools/call", Map("name", name, "arguments", IsObject(args) ? args : Map()))
    }

    Close() {
        try this.exec.StdIn.Close()
    }

    _ReadLine() {
        loop {
            if (this.exec.StdOut.AtEndOfStream)
                throw Error("MCP server closed the connection")
            line := this.exec.StdOut.ReadLine()
            if (Trim(line) != "")
                return line
        }
    }
}

; =========================================================================
;  Tools (native AHK handlers; each returns a JSON string)
; =========================================================================

Tool_AstOutline(args) {
    tree := TSParse(FileRead(args["file"], "UTF-8") ?? "")  ; v2.1: FileRead on a zero-byte file returns unset
    symbols := []
    _AstCollect(tree.Root, symbols)
    out := Map()
    out["file"] := args["file"]
    out["hasError"] := tree.HasError ? Json.True : Json.False
    out["count"] := symbols.Length
    out["symbols"] := symbols
    return Json.Stringify(out)
}

_AstCollect(node, symbols) {
    for child in node.NamedChildren {
        kind := ""
        switch child.Type {
            case "function_declaration": kind := "function"
            case "class_declaration":    kind := "class"
            case "method_declaration":   kind := "method"
            case "property_declaration": kind := "property"
        }
        if (kind != "") {
            s := Map()
            s["kind"]      := kind
            s["name"]      := _AstName(child)
            s["line"]      := child.StartRow + 1
            s["endLine"]   := child.EndRow + 1
            s["startByte"] := child.StartByte
            s["endByte"]   := child.EndByte
            symbols.Push(s)
        }
        _AstCollect(child, symbols)
    }
}

_AstName(node) {
    for c in node.NamedChildren
        if (c.Type = "identifier")
            return Trim(c.Text)
    return ""
}

Tool_GetSourceContext(args) {
    line   := args.Has("line")   ? Integer(args["line"])   : 1
    radius := args.Has("radius") ? Integer(args["radius"]) : 5
    lines := StrSplit(FileRead(args["file"], "UTF-8") ?? "", "`n", "`r")
    total := lines.Length
    startL := Max(1, line - radius), endL := Min(total, line + radius)

    ctx := []
    i := startL
    while (i <= endL) {
        o := Map()
        o["line"]     := i
        o["text"]     := lines[i]
        o["isTarget"] := (i = line) ? Json.True : Json.False
        ctx.Push(o)
        i++
    }
    out := Map()
    out["file"]    := args["file"]
    out["line"]    := line
    out["radius"]  := radius
    out["total"]   := total
    out["context"] := ctx
    return Json.Stringify(out)
}

Tool_SourceOutline(args) {
    lines := StrSplit(FileRead(args["file"], "UTF-8") ?? "", "`n", "`r")
    syms := []
    for idx, ln in lines {
        kind := "", nm := "", t := Trim(ln)
        if (RegExMatch(t, "i)^class\s+([A-Za-z_]\w*)", &m))
            kind := "class", nm := m[1]
        else if (RegExMatch(t, "^([A-Za-z_]\w*)\s*\([^)]*\)\s*\{\s*$", &m) && !_IsKeyword(m[1]))
            kind := "function", nm := m[1]
        else if (RegExMatch(t, "^(\S.*?)::", &m))
            kind := "hotkey", nm := m[1]
        else if (RegExMatch(t, "^([A-Za-z_]\w*):\s*$", &m) && !_IsKeyword(m[1]))
            kind := "label", nm := m[1]
        if (kind != "") {
            s := Map()
            s["kind"] := kind, s["name"] := nm, s["line"] := idx
            syms.Push(s)
        }
    }
    out := Map()
    out["file"] := args["file"], out["count"] := syms.Length, out["symbols"] := syms
    return Json.Stringify(out)
}

Tool_WorkspaceSymbols(args) {
    root  := args.Has("root")  ? args["root"]  : A_WorkingDir
    query := args.Has("query") ? args["query"] : ""
    maxN  := args.Has("max_results") ? Integer(args["max_results"]) : 200
    results := [], truncated := false

    Loop Files, root "\*.ahk", "R" {
        if (results.Length >= maxN) {
            truncated := true
            break
        }
        path := A_LoopFileFullPath, content := ""
        try content := FileRead(path, "UTF-8") ?? ""
        catch
            continue
        for idx, ln in StrSplit(content, "`n", "`r") {
            if (results.Length >= maxN) {
                truncated := true
                break
            }
            kind := "", nm := "", t := Trim(ln)
            if (RegExMatch(t, "i)^class\s+([A-Za-z_]\w*)", &m))
                kind := "class", nm := m[1]
            else if (RegExMatch(t, "^([A-Za-z_]\w*)\s*\([^)]*\)\s*\{\s*$", &m) && !_IsKeyword(m[1]))
                kind := "function", nm := m[1]
            if (kind = "")
                continue
            if (query != "" && !InStr(nm, query))
                continue
            s := Map()
            s["kind"] := kind, s["name"] := nm, s["file"] := path, s["line"] := idx
            results.Push(s)
        }
    }
    out := Map()
    out["root"] := root, out["query"] := query
    out["count"] := results.Length
    out["truncated"] := truncated ? Json.True : Json.False
    out["symbols"] := results
    return Json.Stringify(out)
}

_IsKeyword(name) {
    static kw := "|if|while|for|loop|switch|catch|else|return|until|case|throw|try|finally|break|continue|"
    return InStr(kw, "|" StrLower(name) "|") > 0
}

Tool_ServerStatus(args) {
    s := _McpStats()
    now := A_TickCount
    out := Map()
    out["name"]            := "ahk-mcp"
    out["version"]         := "0.1.0"
    out["ahkVersion"]      := A_AhkVersion
    out["pid"]             := DllCall("GetCurrentProcessId", "uint")
    out["uptimeSeconds"]   := Round((now - s["started"]) / 1000, 1)
    out["requests"]        := s["requests"]
    out["errors"]          := s["errors"]
    out["lastActivitySecondsAgo"] := s["lastTick"] ? Round((now - s["lastTick"]) / 1000, 1) : Json.Null
    out["byMethod"]        := s["methods"]
    out["toolCalls"]       := s["tools"]
    out["toolsRegistered"] := BuildToolRegistry().Count
    return Json.Stringify(out)
}

BuildToolRegistry() {
    tools := Map()
    tools["ast_outline"] := {
        description: "Tree-sitter symbol outline (classes/functions/methods/properties with line ranges and byte spans) for one AHK file. Real parse, not regex.",
        inputSchema: _Schema(Map("file", _Prop("string", "Absolute path to the .ahk file")), ["file"]),
        handler: Tool_AstOutline }
    tools["get_source_context"] := {
        description: "Return source lines around file:line, with the target line flagged.",
        inputSchema: _Schema(Map(
            "file",   _Prop("string",  "Absolute path to the file"),
            "line",   _Prop("integer", "1-based line number to center on"),
            "radius", _Prop("integer", "Lines of context before/after (default 5)")), ["file", "line"]),
        handler: Tool_GetSourceContext }
    tools["source_outline"] := {
        description: "List functions, classes, hotkeys and labels in one AHK file (fast regex scan).",
        inputSchema: _Schema(Map("file", _Prop("string", "Absolute path to the .ahk file")), ["file"]),
        handler: Tool_SourceOutline }
    tools["workspace_symbols"] := {
        description: "Scan all *.ahk files under a root for function and class definitions.",
        inputSchema: _Schema(Map(
            "root",        _Prop("string",  "Root directory to scan (default: working dir)"),
            "query",       _Prop("string",  "Only return symbols whose name contains this substring"),
            "max_results", _Prop("integer", "Cap on returned symbols (default 200)")), []),
        handler: Tool_WorkspaceSymbols }
    tools["server_status"] := {
        description: "Live status/health of this MCP server: uptime, total requests, request counts by method, per-tool call counts, error count, PID and engine version.",
        inputSchema: _Schema(Map(), []),
        handler: Tool_ServerStatus }
    return tools
}

_Prop(type, desc) {
    p := Map()
    p["type"] := type, p["description"] := desc
    return p
}

_Schema(props, required) {
    reqArr := []
    for r in required
        reqArr.Push(r)
    s := Map()
    s["type"] := "object", s["properties"] := props, s["required"] := reqArr
    return s
}

; =========================================================================
;  MCP dispatch + stdio transport
; =========================================================================

MCPServe(tools, opts := "") {
    name    := (IsObject(opts) && opts.HasOwnProp("name"))    ? opts.name    : "ahk-mcp"
    version := (IsObject(opts) && opts.HasOwnProp("version")) ? opts.version : "0.1.0"
    _McpStats()["started"] := A_TickCount        ; reset uptime to server start
    stdin := FileOpen("*", "r", "UTF-8")
    loop {
        line := stdin.ReadLine()             ; blocks until a line or real EOF
        if (line = "" && stdin.AtEOF)        ; check AtEOF AFTER the read — checking
            break                            ; before it falsely fires on a momentarily
        line := Trim(line, " `t`r`n")        ; empty pipe between a client's messages
        if (line = "")
            continue
        resp := _McpHandle(line, tools, name, version)
        if (resp != "")
            _StdoutWrite(resp "`n")
    }
}

; Raw WriteFile — the buffered FileObject has no flush, and the client must see
; each response immediately.
_StdoutWrite(text) {
    static hOut := DllCall("GetStdHandle", "int", -11, "ptr")
    size := StrPut(text, "UTF-8")
    buf := Buffer(size)
    StrPut(text, buf, "UTF-8")
    DllCall("WriteFile", "ptr", hOut, "ptr", buf, "uint", size - 1, "uint*", &written := 0, "ptr", 0)
}

_McpHandle(line, tools, name, version) {
    try
        req := Json.Parse(line)
    catch as e
        return _McpError(Json.Null, -32700, "Parse error: " e.Message)
    ; method MUST be a string (JSON-RPC 2.0); a non-string (true/null/{}) would
    ; otherwise blow up string concatenation below and poison the stats Map.
    if (!(req is Map) || !req.Has("method") || IsObject(req["method"]))
        return _McpError(req is Map && req.Has("id") ? req["id"] : Json.Null, -32600, "Invalid Request")

    method := req["method"], hasId := req.Has("id")
    id := hasId ? req["id"] : Json.Null
    _McpStatsRecord(method)
    switch method {
        case "initialize":
            return _McpResult(id, _McpInitialize(req, name, version))
        case "notifications/initialized", "notifications/cancelled":
            return ""
        case "ping":
            return _McpResult(id, Map())
        case "tools/list":
            return _McpResult(id, _McpToolsList(tools))
        case "tools/call":
            return _McpToolsCall(id, req, tools)
        default:
            return hasId ? _McpError(id, -32601, "Method not found: " method) : ""
    }
}

_McpInitialize(req, name, version) {
    reqVer := ""
    if (req.Has("params") && req["params"] is Map && req["params"].Has("protocolVersion"))
        reqVer := req["params"]["protocolVersion"]
    caps := Map(), caps["tools"] := Map()
    si := Map(), si["name"] := name, si["version"] := version
    r := Map()
    r["protocolVersion"] := (reqVer != "") ? reqVer : "2024-11-05"
    r["capabilities"] := caps, r["serverInfo"] := si
    return r
}

_McpToolsList(tools) {
    arr := []
    for nm, spec in tools {
        t := Map()
        t["name"] := nm, t["description"] := spec.description, t["inputSchema"] := spec.inputSchema
        arr.Push(t)
    }
    r := Map(), r["tools"] := arr
    return r
}

_McpToolsCall(id, req, tools) {
    params := (req.Has("params") && req["params"] is Map) ? req["params"] : Map()
    if (!params.Has("name") || IsObject(params["name"])) ; name must be a string
        return _McpError(id, -32602, "Invalid params: missing tool name")
    nm := params["name"]
    if (!tools.Has(nm))
        return _McpError(id, -32602, "Unknown tool: " nm)
    _McpStatsTool(nm)
    args := (params.Has("arguments") && params["arguments"] is Map) ? params["arguments"] : Map()
    fn := tools[nm].handler
    try
        text := fn(args)
    catch as e
        return _McpError(id, -32603, "Tool '" nm "' failed: " e.Message)
    block := Map()
    block["type"] := "text", block["text"] := text
    r := Map(), r["content"] := [block], r["isError"] := Json.False
    return _McpResult(id, r)
}

_McpResult(id, result) {
    o := Map()
    o["jsonrpc"] := "2.0", o["id"] := id, o["result"] := result
    return Json.Stringify(o)
}

_McpError(id, code, message) {
    _McpStats()["errors"]++
    err := Map()
    err["code"] := code, err["message"] := message
    o := Map()
    o["jsonrpc"] := "2.0", o["id"] := id, o["error"] := err
    return Json.Stringify(o)
}

; ---- server stats (single persistent snapshot, read by the server_status tool) ----

_McpStats() {
    static s := Map("started", A_TickCount, "requests", 0, "errors", 0
                  , "methods", Map(), "tools", Map(), "lastTick", 0)
    return s
}

_McpStatsRecord(method) {
    s := _McpStats()
    s["requests"]++
    s["lastTick"] := A_TickCount
    s["methods"][method] := (s["methods"].Has(method) ? s["methods"][method] : 0) + 1
}

_McpStatsTool(name) {
    t := _McpStats()["tools"]
    t[name] := (t.Has(name) ? t[name] : 0) + 1
}

; =========================================================================
;  JSON parse + stringify (true/false/null via Json.True/False/Null sentinels)
; =========================================================================

class Json {
    static True  := { __json: "true" }
    static False := { __json: "false" }
    static Null  := { __json: "null" }

    static Parse(text) {
        p := { s: text, i: 1, n: StrLen(text) }
        Json._SkipWs(p)
        v := Json._Value(p)
        Json._SkipWs(p)
        if (p.i <= p.n)
            throw Error("JSON: trailing characters at position " p.i)
        return v
    }

    static Stringify(v) => Json._Str(v)

    static _Value(p) {
        Json._SkipWs(p)
        if (p.i > p.n)
            throw Error("JSON: unexpected end of input")
        c := SubStr(p.s, p.i, 1)
        switch c {
            case "{": return Json._Object(p)
            case "[": return Json._Array(p)
            case '"': return Json._String(p)
        }
        if (c = "t" || c = "f" || c = "n")
            return Json._Keyword(p)
        if (c = "-" || Json._IsDigit(c))
            return Json._Number(p)
        throw Error("JSON: unexpected character '" c "' at position " p.i)
    }

    static _IsDigit(c) {
        code := Ord(c)
        return code >= 48 && code <= 57
    }

    static _Object(p) {
        obj := Map()
        p.i++
        Json._SkipWs(p)
        if (SubStr(p.s, p.i, 1) = "}") {
            p.i++
            return obj
        }
        loop {
            Json._SkipWs(p)
            if (SubStr(p.s, p.i, 1) != '"')
                throw Error("JSON: expected string key at position " p.i)
            key := Json._String(p)
            Json._SkipWs(p)
            if (SubStr(p.s, p.i, 1) != ":")
                throw Error("JSON: expected ':' at position " p.i)
            p.i++
            obj[key] := Json._Value(p)
            Json._SkipWs(p)
            c := SubStr(p.s, p.i, 1)
            if (c = ",") {
                p.i++
                continue
            }
            if (c = "}") {
                p.i++
                return obj
            }
            throw Error("JSON: expected ',' or '}' at position " p.i)
        }
    }

    static _Array(p) {
        arr := []
        p.i++
        Json._SkipWs(p)
        if (SubStr(p.s, p.i, 1) = "]") {
            p.i++
            return arr
        }
        loop {
            arr.Push(Json._Value(p))
            Json._SkipWs(p)
            c := SubStr(p.s, p.i, 1)
            if (c = ",") {
                p.i++
                continue
            }
            if (c = "]") {
                p.i++
                return arr
            }
            throw Error("JSON: expected ',' or ']' at position " p.i)
        }
    }

    static _String(p) {
        p.i++
        out := ""
        loop {
            if (p.i > p.n)
                throw Error("JSON: unterminated string")
            c := SubStr(p.s, p.i, 1)
            if (c = '"') {
                p.i++
                return out
            }
            if (c = "\") {
                p.i++
                e := SubStr(p.s, p.i, 1)
                switch e {
                    case '"': out .= '"'
                    case "\": out .= "\"
                    case "/": out .= "/"
                    case "b": out .= Chr(8)
                    case "f": out .= Chr(12)
                    case "n": out .= "`n"
                    case "r": out .= "`r"
                    case "t": out .= "`t"
                    case "u":
                        out .= Chr(Integer("0x" SubStr(p.s, p.i + 1, 4)))
                        p.i += 4
                    default:
                        throw Error("JSON: invalid escape '\" e "' at position " p.i)
                }
                p.i++
                continue
            }
            out .= c
            p.i++
        }
    }

    static _Number(p) {
        start := p.i
        if (SubStr(p.s, p.i, 1) = "-")
            p.i++
        while (p.i <= p.n) {
            c := SubStr(p.s, p.i, 1)
            if (Json._IsDigit(c) || c = "." || c = "e" || c = "E" || c = "+" || c = "-")
                p.i++
            else
                break
        }
        numStr := SubStr(p.s, start, p.i - start)
        if (InStr(numStr, ".") || InStr(numStr, "e") || InStr(numStr, "E"))
            return Float(numStr)
        return Integer(numStr)
    }

    static _Keyword(p) {
        if (SubStr(p.s, p.i, 4) = "true") {
            p.i += 4
            return Json.True
        }
        if (SubStr(p.s, p.i, 5) = "false") {
            p.i += 5
            return Json.False
        }
        if (SubStr(p.s, p.i, 4) = "null") {
            p.i += 4
            return Json.Null
        }
        throw Error("JSON: invalid keyword at position " p.i)
    }

    static _SkipWs(p) {
        while (p.i <= p.n) {
            c := SubStr(p.s, p.i, 1)
            if (c = " " || c = "`t" || c = "`n" || c = "`r")
                p.i++
            else
                break
        }
    }

    static _Str(v) {
        if (IsObject(v)) {
            if (v.HasOwnProp("__json"))
                return v.__json
            t := Type(v)
            if (t = "Map")
                return Json._StrObject(v)
            if (t = "Array")
                return Json._StrArray(v)
            throw Error("JSON: cannot stringify object of type " t)
        }
        t := Type(v)
        if (t = "Integer" || t = "Float")
            return String(v)
        return Json._Quote(v)
    }

    static _StrObject(m) {
        out := "{", sep := ""
        for k, val in m {
            out .= sep Json._Quote(String(k)) ":" Json._Str(val)
            sep := ","
        }
        return out "}"
    }

    static _StrArray(a) {
        out := "[", sep := ""
        for val in a {
            out .= sep Json._Str(val)
            sep := ","
        }
        return out "]"
    }

    static _Quote(s) {
        out := '"'
        loop parse s {
            c := A_LoopField
            switch c {
                case '"':     out .= '\"'
                case "\":     out .= "\\"
                case "`n":    out .= "\n"
                case "`r":    out .= "\r"
                case "`t":    out .= "\t"
                case Chr(8):  out .= "\b"
                case Chr(12): out .= "\f"
                default:
                    code := Ord(c)
                    out .= (code < 32) ? Format("\u{:04x}", code) : c
            }
        }
        return out '"'
    }
}
