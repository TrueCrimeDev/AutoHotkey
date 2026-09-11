#Requires AutoHotkey v2.1-alpha.30
; No #EnableEval directive: the caller must supply /Eval.
if Eval("6 * 7") != 42
    ExitApp(14)
Print("/Eval enables evaluation")
ExitApp(0)
