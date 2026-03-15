; alpha.22 Change: `export a() => b` is a function call statement (as in v2.0)
; This reverts the alpha-only behavior where `export a() => b` was treated
; as an exported fat-arrow function definition.
; Now it behaves as v2.0: `export` is called as a function with `a() => b` as argument.

; --- The change ---
; In earlier alphas, this was an exported fat-arrow function definition:
;   export MyFunc(x) => x * 2
;
; In alpha.22, that same line is now a FUNCTION CALL: calling export()
; with the result of the fat-arrow expression.

; --- Correct way to export from a module in alpha.22 ---
; Use block syntax for exported functions, not fat-arrow.

#Module MyLib

export MyFunc(x) {
    return x * 2
}

export Add(a, b) {
    return a + b
}

#Module __Main

#Import MyLib { MyFunc, Add }

FileAppend("MyFunc(21) = " MyFunc(21) "`n", "*")
FileAppend("Add(10, 5) = " Add(10, 5) "`n", "*")
