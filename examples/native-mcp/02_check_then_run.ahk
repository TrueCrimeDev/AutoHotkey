#Requires AutoHotkey v2.1-alpha.31
#Include McpClient.ahk
; Use case: check a worker before running it, then consume its structured output.
; Optional first argument is the text to clean. No clipboard or files are changed.
input := A_Args.Length ? A_Args[1] : "  Meeting`t notes:   follow up   tomorrow.  "
mcp := McpClient()
try {
    file := A_ScriptDir "\sample\clean_text.ahk"
    checked := mcp.Call("check", McpArgs("file", file, "timeout_ms", 5000))
    RequireSuccess(checked)
    Print("Syntax check passed. Running the worker...")
    result := mcp.Call("run", McpArgs("file", file, "args", [input], "timeout_ms", 5000))
    RequireSuccess(result)
    data := JSON.Parse(result["stdout"])
    Print("Before: [{}]", data["original"])
    Print("After:  [{}]", data["cleaned"])
    Print("Characters: {} -> {}", data["beforeLength"], data["afterLength"])
} finally {
    mcp.Close()
}
