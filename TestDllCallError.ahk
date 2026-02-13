#Requires AutoHotkey v2.0
OutputDebug("Starting TestDllCallError.ahk")
; Try to call a non-existent function in a system DLL to force an error
DllCall("kernel32.dll\NonExistentFunction", "Ptr", 0)
