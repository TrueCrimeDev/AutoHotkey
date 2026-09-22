#Requires AutoHotkey v2.1-alpha.31
; Small synchronous client for THIS fork's native stdio MCP server.
; JSON and ProcessPipe are built in. This include has no startup side effects.
class McpClient {
    __New() {
        this.NextId := 0
        this.Pipe := ProcessPipe(A_AhkPath, ["mcp"], A_ScriptDir)
        try {
            params := JSON.Parse('{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"ahk-examples","version":"1"}}')
            this.Request("initialize", params)
            this.Pipe.SendLine('{"jsonrpc":"2.0","method":"notifications/initialized"}', 5)
            this.Tools := this.Request("tools/list")["tools"]
        } catch {
            this.Pipe.Kill()
            throw
        }
    }

    Request(method, params := unset, timeout := 10) {
        message := Map()
        message["jsonrpc"] := "2.0"
        message["id"] := ++this.NextId
        message["method"] := method
        if IsSet(params)
            message["params"] := params
        this.Pipe.SendLine(JSON.Stringify(message), 5)
        reply := JSON.Parse(this.Pipe.ReadLine(timeout))
        if reply.Get("jsonrpc", "") != "2.0" || reply.Get("id", -1) != this.NextId
            throw Error("Unexpected MCP response: " JSON.Stringify(reply))
        if reply.Has("error")
            throw Error("MCP: " reply["error"]["message"])
        return reply["result"]
    }

    Call(name, arguments := unset) {
        available := false
        for tool in this.Tools {
            if tool["name"] = name
                available := true
        }
        if !available
            throw Error("This executable does not expose MCP tool '" name "'. Use a current build.")
        params := Map()
        params["name"] := name
        params["arguments"] := IsSet(arguments) ? arguments : Map()
        ; Tool timeout_ms uses milliseconds; ProcessPipe uses seconds.
        timeout := params["arguments"].Get("timeout_ms", 30000) / 1000 + 5
        result := this.Request("tools/call", params, timeout)
        if result.Get("isError", false)
            throw Error("MCP tool failed: " JSON.Stringify(result["content"]))
        ; This native server returns its JSON payload in one text content block.
        return JSON.Parse(result["content"][1]["text"])
    }

    Close() {
        try {
            this.Pipe.Close()
            code := this.Pipe.Wait(5)
            stderr := this.Pipe.ReadStdErr()
            if code != 0 || stderr != ""
                throw Error("MCP shutdown failed: exit " code " " stderr)
        } finally {
            if this.Pipe.Running
                this.Pipe.Kill()
        }
    }
}

; Build named tool arguments without hiding the tool names or their schemas.
McpArgs(pairs*) {
    if Mod(pairs.Length, 2)
        throw ValueError("McpArgs expects name/value pairs.")
    args := Map()
    Loop pairs.Length // 2
        args[pairs[A_Index * 2 - 1]] := pairs[A_Index * 2]
    return args
}

RequireSuccess(result) {
    if !result["ok"] || result["timedOut"] || result["exitCode"] != 0
        throw Error("Child failed: " JSON.Stringify(result))
}

PrintContext(context) {
    for row in context["context"]
        Print("{} {:3} | {}", row["isTarget"] ? ">" : " ", row["line"], row["text"])
}
