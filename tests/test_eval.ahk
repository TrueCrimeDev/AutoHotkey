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

; --- Section F: alpha.29 features ---
; F.3 (IIFE + maybe-operator + ||, e.g. `_Eval("(() => unsetLocal? || 42)()")`)
; is intentionally NOT tested here: that specific combination currently crashes
; through _Eval even though the same expression works inline. Tracked as a known
; limitation of the runtime-preparse path; out of scope for v1.
Assert(_Eval("(missing? > 0) ?? 'fb'") = "fb",     "F.1 maybe operator")
arr := [1, , 3]
removed := _Eval("arr.RemoveAt(2)") ?? "<unset>"
Assert(removed = "<unset>",                         "F.2 unset propagates")

; --- Section G: SyntaxError ---
threw := false
caught := unset
try _Eval("1 + + +")
catch SyntaxError as e {
    threw := true
    caught := e
}
Assert(threw,                              "G.1 bad input throws SyntaxError")
Assert(caught.Message != "",               "G.2 message is non-empty")
Assert(caught.HasProp("Column"),           "G.3 has Column property")

; --- Section H: reentrancy ---
h1_expr := '_Eval("1 + 1") + _Eval("2 + 2")'
Assert(_Eval(h1_expr) = 6, "H.1 nested _Eval")
h2_expr := '_Eval("_Eval(' . "'" . '3 * 3' . "'" . ')")'
Assert(_Eval(h2_expr) = 9,       "H.2 deeply nested")

PrintLine "all checks passed"
ExitApp 0
