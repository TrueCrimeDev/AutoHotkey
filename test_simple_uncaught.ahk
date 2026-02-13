#Requires AutoHotkey v2.0
FileAppend "Before error`n", "*"
obj := {}
obj.Fail()
FileAppend "After error`n", "*"
