; Test with actual error to trigger _ScriptGetLines via debugger
MsgBox("AHK Version: " A_AhkVersion "`n`nThis build has _ScriptGetLines for the debugger MCP tool.`n`nClick OK to test error capture.", "Custom AutoHotkey Build")

; Trigger an intentional error to test the MCP debugger flow
x := undefined_variable
