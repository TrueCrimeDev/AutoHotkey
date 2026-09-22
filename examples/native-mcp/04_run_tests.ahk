#Requires AutoHotkey v2.1-alpha.31
#Include McpClient.ahk
; Use case: a small CI-style test report with a machine-readable pass/fail status.
; Pass --fail to demonstrate how a failed assertion reaches the caller (exit 14).
injectFailure := A_Args.Length && A_Args[1] = "--fail"
mcp := McpClient()
try {
    file := A_ScriptDir "\sample\clean_text.test.ahk"
    RequireSuccess(mcp.Call("check", McpArgs("file", file, "timeout_ms", 5000)))
    result := mcp.Call("test", McpArgs("file", file, "args", injectFailure ? ["--fail"] : [], "timeout_ms", 5000))
    Print(result["stdout"])
    Print("ok={}, exitCode={}, timedOut={}", result["ok"], result["exitCode"], result["timedOut"])
    if !injectFailure
        RequireSuccess(result)
    else if result["ok"] || result["timedOut"] || result["exitCode"] != 14
        throw Error("Expected test failure exit 14: " JSON.Stringify(result))
    exitCode := result["exitCode"]
} finally {
    mcp.Close()
}
ExitApp(exitCode)
