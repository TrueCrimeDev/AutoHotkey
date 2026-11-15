#Requires AutoHotkey v2.1-alpha.39
; test_alpha39.ahk -- pins behaviour from upstream v2.1-alpha.39 (tag
; v2.1-alpha.39 = 768d9bdc, released 2026-11-14), merged into the fork as
; ca5b713b. Every fact below was verified against 2.1-alpha.39+Console; the
; "OLD:" note on a section records what 2.1-alpha.38+Console (a6763d81) did,
; so an assert that only passes here is genuinely pinning the change.
;
; The alpha.39 struct and module fixes (#371-#381) are the fork's own patches
; and are already pinned by test_alpha37.ahk section 9, test_alpha38.ahk
; sections 9 and 10, and test_alpha33.ahk. Each case here runs in a child
; process: the old engine fails the first at load time, and the others depend
; on fixed line numbers or a top-level #Requires.
#Include ..\Assert.ahk
#Include ..\Harness.ahk

Lines(parts*) {
    out := ""
    for p in parts
        out .= p "`n"
    return out
}

; 1. A function definition expression is allowed as the single-line body of
;    if/else (1c1994e1).
; OLD (alpha.38): "Unexpected function" at load time.
r := RunSnippet(Lines(
    "if true",
    "    f := G() {",
    "        return 5",
    "    }",
    "else",
    "    f := H() => 6",
    "Print(f())"))
Assert.eq(r.code " " r.out, "0 5`n", "a function definition expression may be the body of if")

; 2. Function bodies are separate line lists (1c1994e1), and consecutive
;    definitions leave the outer list consistent (42ddbabc, upstream #370).
;    _ScriptGetLines walks the same links as the error dialog.
; OLD (alpha.38): a range around line 8 started at line 7, F2's closing
;      brace; a range from line 2 ran on into the function body.
r := RunSnippet(Lines(
    "x := 1",
    "F1() {",
    "    return 1",
    "}",
    "F2() {",
    "    return 2",
    "}",
    "for l in _ScriptGetLines(A_LineFile, 8, 1)",
    "    Print(l.Number)"))
Assert.eq(r.code " " r.out, "0 1`n8`n9`n", "the line before two consecutive functions precedes the next outer line")
r := RunSnippet(Lines(
    "a := 1",
    "F() {",
    "    x := 1",
    "    y := 2",
    "}",
    "b := 2",
    "for l in _ScriptGetLines(A_LineFile, 4, 3)",
    "    Print(l.Number)",
    "for l in _ScriptGetLines(A_LineFile, 1, 2)",
    "    Print(l.Number)"))
Assert.eq(r.code " " r.out, "0 2`n3`n4`n5`n1`n6`n7`n",
    "a range stops at a function's braces inside it and skips its body outside it")

; 3. A line inside a function is still found by line number. The fork's
;    Script::GetLine walked only the module line list until ec2f18d9.
r := RunSnippet(Lines(
    "F() {",
    "    x := 1",
    "    return _ScriptGetLines(A_LineFile, 2)",
    "}",
    "Print(F()[1].Text)"))
Assert.eq(r.code " " r.out, "0 x := 1`n", "_ScriptGetLines finds a line inside a function")

; 4. WinGetTransparent returns "" rather than no value for a window without
;    transparency (f3291c14).
; OLD (alpha.38): under a v2.1 #Requires, UnsetError "No value was returned."
r := RunSnippet(Lines(
    "#Requires AutoHotkey v2.1-alpha.38",
    "DetectHiddenWindows(true)",
    "v := WinGetTransparent(A_ScriptHwnd)",
    "Print('[' v '] ' Type(v))"))
Assert.eq(r.code " " r.out, "0 [] String`n", "WinGetTransparent returns an empty string")

Assert.Summary()
