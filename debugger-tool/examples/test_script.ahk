; Simple AHK v2 test script for debugging
#Requires AutoHotkey v2.0

myVar := "Hello"
myNumber := 0

Loop 5 {
    myNumber := A_Index
    MsgBox "Iteration " myNumber
}

MsgBox "Done! myVar = " myVar
