#Requires AutoHotkey v2.1-alpha.30
; test_print.ahk -- stdout contract of the fork's variadic Print() BIF.
;
; Print's own output can't be asserted from within the same process, so each
; case runs as a child snippet (RunSnippet) and we assert on its exact captured
; stdout bytes. Empirically probed against 2.1-alpha.30+Console first:
;   * line terminator is a single LF (no CR), even on Windows;
;   * a lone Print() emits just that LF;
;   * the SINGLE-arg form is written verbatim -- it never calls Format, so
;     literal { } survive untouched;
;   * with 2+ args the first arg is a Format() template: {} sequential,
;     {1} reusable, {2},{1} reorderable.
#Include ..\Assert.ahk
#Include ..\Harness.ahk

; --- line terminator + blank line ---
Assert.eq(SnippetOut('Print("hello")'), "hello`n",
    "single-arg text ends in one LF")
Assert.eq(SnippetOut("Print()"), "`n",
    "argless Print emits a blank line (lone LF)")
Assert.eq(SnippetOut('Print("a")`nPrint("b")'), "a`nb`n",
    "successive Prints concatenate, each LF-terminated")

; --- single-arg form bypasses Format: literal braces survive ---
Assert.eq(SnippetOut('Print("{not a placeholder}")'), "{not a placeholder}`n",
    "single arg keeps literal braces")
Assert.eq(SnippetOut('Print("{}")'), "{}`n",
    "single arg does not treat {} as a placeholder")
Assert.eq(SnippetOut('Print("{1}")'), "{1}`n",
    "single arg does not treat {1} as a placeholder")

; --- 2+ args: first arg is a Format template ---
Assert.eq(SnippetOut('Print("x={}, y={}", 1, 2)'), "x=1, y=2`n",
    "{} placeholders fill sequentially")
Assert.eq(SnippetOut('Print("{1} {1}", "a")'), "a a`n",
    "{1} reuses the same argument")
Assert.eq(SnippetOut('Print("{2},{1}", "a", "b")'), "b,a`n",
    "{2},{1} reorders arguments")

Assert.Summary()
