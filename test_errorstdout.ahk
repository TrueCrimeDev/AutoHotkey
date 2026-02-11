; Test script for /ErrorStdOut runtime error handling
#Requires AutoHotkey v2.0

MsgBox("About to cause an error...")

; This will cause a runtime error
nonexistent_variable.method()
