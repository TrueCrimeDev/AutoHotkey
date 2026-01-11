#Requires AutoHotkey v2.0
#Include DebugClient.ahk

; Wait for connection
Sleep(1000)
FileAppend("Test script started`n", "test_debug_marker.txt")

; Send some debug messages
OutputDebug("Test Debug Message 1")
Sleep(100)
OutputDebug("Test Debug Message 2: Variable x = " 42)

; Trigger an error to ensure mixed content works
try {
    throw Error("Test Error after Debug", -1, "This error should appear after debug messages")
} catch {
    ; Let it bubble up to DebugClient
    throw
}
