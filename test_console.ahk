; Test console output
#Requires AutoHotkey v2.0

FileAppend "=== AHK Console Test ===`n", "*"
FileAppend "Version: " A_AhkVersion "`n", "*"
FileAppend "Script: " A_ScriptName "`n", "*"
FileAppend "Working Dir: " A_WorkingDir "`n", "*"
FileAppend "`nAbout to throw an error...`n", "*"

; Cause a runtime error
throw Error("Test error from console mode", -1, "Extra info")
