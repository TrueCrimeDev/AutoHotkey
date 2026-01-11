#Requires AutoHotkey v2.0
; Random test script - will generate an error

MsgBox("This script will error in 2 seconds...")
Sleep(2000)

; Intentional error
result := 100 / 0
