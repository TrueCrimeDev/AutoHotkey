#Requires AutoHotkey v2.0
; This script prints to stdout/stderr and throws an error to test capture

FileAppend("This is STDOUT message`n", "*")
FileAppend("This is STDERR message`n", "**")

OutputDebug("This is OutputDebug message (should be captured if hooked, but async wrapper might miss it unless redirected)")

throw Error("This is a test error")
