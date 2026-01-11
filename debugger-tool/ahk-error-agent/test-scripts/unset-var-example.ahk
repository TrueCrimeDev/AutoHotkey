#Requires AutoHotkey v2.0

; Test script that triggers an unset variable error

Calculate(a, b, operation) {
    ; Forgot to initialize result for some paths
    if (operation = "add") {
        result := a + b
    } else if (operation = "subtract") {
        result := a - b
    }
    ; Missing: else case doesn't set result!

    return result  ; Error: VarUnset when operation is neither
}

; Test with valid operations
sum := Calculate(10, 5, "add")
MsgBox("Sum: " . sum)

diff := Calculate(10, 5, "subtract")
MsgBox("Difference: " . diff)

; This will fail - unset variable
product := Calculate(10, 5, "multiply")
MsgBox("Product: " . product)
