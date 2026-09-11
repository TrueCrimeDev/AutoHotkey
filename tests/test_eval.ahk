#Requires AutoHotkey v2.1-alpha.29
#EnableEval

; Lightweight Assert: exits the process with code 14 on first failure.
Assert(cond, msg := "assertion failed") {
    if !cond {
        FileAppend("FAIL: " . msg . "`n", "**")
        ExitApp 14
    }
}

stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")

PrintLine "=== Eval test (with /Eval enabled) ==="

; Sections B+ will be added by later tasks as the BIF gains real behavior.

; --- Section A: presence ---
Assert(IsSet(Eval),     "A.1 Eval is defined")
Assert(Eval is Func,    "A.2 Eval is a function")

; --- Section B: SyntaxError class exists ---
Assert(IsSet(SyntaxError),                                          "B.1 SyntaxError exists")
Assert(HasBase(SyntaxError.Prototype, Error.Prototype),             "B.2 SyntaxError extends Error")

; --- Section C: basic expressions ---
Assert(Eval("1 + 2") = 3,                       "C.1 arithmetic")
Assert(Eval("'hi ' . 'there'") = "hi there",    "C.2 string concat")
Assert(Eval("[1,2,3].Length") = 3,              "C.3 method call")
Assert(Eval("(()=> 7)()") = 7,                  "C.4 fat-arrow IIFE")

; --- Section D: caller-scope read ---
x := 10
y := 20
Assert(Eval("x + y") = 30,           "D.1 reads caller locals")
Assert(Eval("A_AhkVersion") != "",   "D.2 reads built-in globals")

; --- Section E: caller-scope write ---
x := 10
Eval("x := 99")
Assert(x = 99,                                "E.1 mutates caller local")
Eval("x += 1")
Assert(x = 100,                               "E.2 compound assignment")

; --- Section F: alpha.29 features ---
Assert(Eval("(missing? > 0) ?? 'fb'") = "fb",     "F.1 maybe operator")
arr := [1, , 3]
removed := Eval("arr.RemoveAt(2)") ?? "<unset>"
Assert(removed = "<unset>",                         "F.2 unset propagates")
Assert((Eval("(() => unsetLocal? || 42)()") ?? "<unset>") = "<unset>", "F.3 IIFE maybe operator")

; --- Section G: SyntaxError ---
threw := false
caught := unset
try Eval("1 + + +")
catch SyntaxError as e {
    threw := true
    caught := e
}
Assert(threw,                              "G.1 bad input throws SyntaxError")
Assert(caught.Message != "",               "G.2 message is non-empty")
Assert(caught.HasProp("Column"),           "G.3 has Column property")

; --- Section H: reentrancy ---
h1_expr := 'Eval("1 + 1") + Eval("2 + 2")'
Assert(Eval(h1_expr) = 6, "H.1 nested Eval")
h2_expr := 'Eval("Eval(' . "'" . '3 * 3' . "'" . ')")'
Assert(Eval(h2_expr) = 9,       "H.2 deeply nested")

PrintLine "all checks passed"
ExitApp 0
