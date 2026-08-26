#Requires AutoHotkey v2.1-alpha.30
; test_removed_syntax.ahk -- pins the load-time rejection of operators this fork
; removed, and confirms the surviving replacements still parse. Each snippet is
; run as its own process (RunSnippet) so a *load-time* failure is an assertable
; nonzero exit code rather than something that would abort this suite.
;
; Empirically probed against 2.1-alpha.30+Console first. A failed parse exits 12
; and writes an /ErrorStdOut diagnostic; a clean parse exits 0. We assert both
; the exit code and a stable fragment of the diagnostic text.
#Include ..\Assert.ahk
#Include ..\Harness.ahk

; The maybe-call operator a?.() was removed; it no longer parses as an action.
r := RunSnippet('f := () => 1`nf?.()')
Assert.truthy(r.code, "a?.() fails to load (nonzero exit)")
Assert.truthy(InStr(r.out, "does not contain a recognized action"),
    "a?.() reports an unrecognized action")

; The maybe-index operator a?[i] was removed.
r := RunSnippet('a := [1]`na?[1]')
Assert.truthy(r.code, "a?[i] fails to load (nonzero exit)")
Assert.truthy(InStr(r.out, 'Unexpected "?"'),
    "a?[i] reports an unexpected ?")

; !a ?? b is rejected as ambiguous (does ! bind before ??).
r := RunSnippet('a := 0`nx := !a ?? 5')
Assert.truthy(r.code, "!a ?? b fails to load (nonzero exit)")
Assert.truthy(InStr(r.out, 'Unexpected "?"'),
    "!a ?? b reports an unexpected ?")

; --- surviving replacements must still parse and run cleanly ---

; (fn?)() -- parenthesized maybe-deref then call: invokes when the var is set.
r := RunSnippet('f := () => Print("called")`n(f?)()')
Assert.eq(r.code, 0, "(fn?)() loads and runs")
Assert.eq(r.out, "called`n", "(fn?)() invokes the set function")

; (unset?)() -- no-ops silently when the var is unset, control continues.
r := RunSnippet('(g?)()`nPrint("after")')
Assert.eq(r.code, 0, "(unset?)() loads and runs")
Assert.eq(r.out, "after`n", "(unset?)() is a no-op, execution continues")

Assert.Summary()
