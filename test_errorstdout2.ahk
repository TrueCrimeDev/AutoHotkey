; Test script for /ErrorStdOut runtime error handling
#Requires AutoHotkey v2.0

; Directly cause a runtime error
throw Error("This is a test runtime error")
