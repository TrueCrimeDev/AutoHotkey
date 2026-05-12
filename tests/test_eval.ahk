#Requires AutoHotkey v2.1-alpha.29

; Lightweight Assert: exits the process with code 14 on first failure.
Assert(cond, msg := "assertion failed") {
    if !cond {
        FileAppend("FAIL: " . msg . "`n", "**")
        ExitApp 14
    }
}

stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")

PrintLine "=== _Eval test (with /Eval enabled) ==="

; Sections B+ will be added by later tasks as the BIF gains real behavior.

; --- Section A: presence ---
Assert(IsSet(_Eval),     "A.1 _Eval is defined")
Assert(_Eval is Func,    "A.2 _Eval is a function")

; --- Section B: SyntaxError class exists ---
Assert(IsSet(SyntaxError),                                          "B.1 SyntaxError exists")
Assert(HasBase(SyntaxError.Prototype, Error.Prototype),             "B.2 SyntaxError extends Error")

; --- Section C: basic expressions ---
Assert(_Eval("1 + 2") = 3,                       "C.1 arithmetic")
Assert(_Eval("'hi ' . 'there'") = "hi there",    "C.2 string concat")
Assert(_Eval("[1,2,3].Length") = 3,              "C.3 method call")
Assert(_Eval("(()=> 7)()") = 7,                  "C.4 fat-arrow IIFE")

; --- Section D: caller-scope read ---
x := 10
y := 20
Assert(_Eval("x + y") = 30,           "D.1 reads caller locals")
Assert(_Eval("A_AhkVersion") != "",   "D.2 reads built-in globals")

; --- Section E: caller-scope write ---
x := 10
_Eval("x := 99")
Assert(x = 99,                                "E.1 mutates caller local")
_Eval("x += 1")
Assert(x = 100,                               "E.2 compound assignment")

PrintLine "all checks passed"
ExitApp 0
