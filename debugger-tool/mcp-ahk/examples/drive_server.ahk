#Requires AutoHotkey v2.1-alpha.30
#Include ..\mcp.ahk
/*
drive_server.ahk — AHK acting as an MCP *client*. It spawns mcp.ahk as a
separate server process and drives it over JSON-RPC, exactly the way a Node or
Python client would spawn and drive any MCP server.

(Including mcp.ahk here only defines McpClient/Json — it does NOT start a server
in this process; the server runs in the child we spawn below.)

Usage:  AutoHotkey64.exe drive_server.ahk
*/

; spawn THIS engine running mcp.ahk as the server
serverScript := A_ScriptDir "\..\mcp.ahk"
command := '"' A_AhkPath '" "' serverScript '"'

client := McpClient(command)
Print(Format("connected to '{}' v{}", client.serverInfo["name"], client.serverInfo["version"]))

Print("`ntools advertised by the server:")
for t in client.ListTools()
    Print("  - " t["name"])

; call a tool over the wire and unwrap the result
target := "C:\Users\uphol\Documents\Design\Coding\AutoHotkey\Lib\DarkMode.ahk"
Print("`ncalling ast_outline over the protocol...")
res := client.CallTool("ast_outline", Map("file", target))
data := Json.Parse(res["content"][1]["text"])
Print(Format("  -> {} reports {} symbols", target, data["count"]))

; ask the server about itself
status := Json.Parse(client.CallTool("server_status")["content"][1]["text"])
Print(Format("`nserver_status -> requests={} uptime={}s pid={}", status["requests"], status["uptimeSeconds"], status["pid"]))

client.Close()
