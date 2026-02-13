; Simple error test
#Requires AutoHotkey v2.0

FileAppend "Starting...`n", "*"

; Access undefined variable (causes error)
x := undefined_var.property

FileAppend "This should not print`n", "*"
