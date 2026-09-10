; alpha.22 Change: `export a() => b` is a function call statement (as in v2.0)
; alpha.31 Change: the `export` keyword itself was removed.
;
; History:
;   - Early alphas: `export MyFunc(x) => x * 2` defined an exported fat-arrow function.
;   - alpha.22 reverted that: the line became a CALL to a function named `export`
;     (v2.0 semantics), so exported functions had to use block syntax.
;   - alpha.31 removed `export` entirely. Every module-level name is exported
;     implicitly, so `export Fn(x) {` now parses as a statement starting with the
;     unassigned global `export` and dies at run time (exit 10).
;
; --- Correct way to define module members in alpha.31 ---
; Just define them. Fat-arrow and block syntax both work.

#Requires AutoHotkey v2.1-alpha.31

#Module MyLib

MyFunc(x) => x * 2

Add(a, b) {
    return a + b
}

; Helpers you want to keep out of `{*}` imports: prefix with an underscore.
_Internal() => "not for import"

#Module __Main

#Import MyLib { MyFunc, Add }

FileAppend("MyFunc(21) = " MyFunc(21) "`n", "*")
FileAppend("Add(10, 5) = " Add(10, 5) "`n", "*")
