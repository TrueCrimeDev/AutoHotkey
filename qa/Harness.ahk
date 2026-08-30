#Requires AutoHotkey v2.1-alpha.30
; qa/Harness.ahk -- spawn-a-child-snippet helper for tests that must assert on
; something the parent process can't observe directly: exact stdout bytes from
; the Print() BIF, or the load-time exit code / error text of a snippet that is
; supposed to fail to parse.
;
; A test #Includes both Assert.ahk and this file, then calls RunSnippet(src) to
; run `src` as its own AutoHotkey process and get back { code, out }:
;   * code -> the child's ExitApp / fatal exit code
;   * out  -> everything it wrote to stdout+stderr, decoded UTF-8
;
; Same A_ComSpec redirect form run.ahk uses, so /ErrorStdOut diagnostics land in
; `out`. The snippet is written to a unique temp .ahk, run, then deleted.

; Run one AHK source snippet in a child process. Returns { code, out }.
RunSnippet(src, args := "") {
    static seq := 0
    seq += 1
    stem := A_Temp "\qa_snip_" A_TickCount "_" seq
    script := stem ".ahk"
    tmp    := stem ".out"

    FileAppend(src, script, "UTF-8")
    engine := A_AhkPath
    ; A_ComSpec can be empty when the engine is launched from WSL (ComSpec is
    ; not in the translated environment), so fall back to the well-known path.
    shell := A_ComSpec != "" ? A_ComSpec : A_WinDir "\System32\cmd.exe"
    cmd := shell ' /c ""' engine '" /ErrorStdOut "' script '" ' args ' >"' tmp '" 2>&1"'
    code := RunWait(cmd, , "Hide")

    ; try: FileRead of a zero-byte file returns no value on this alpha, which
    ; a bare ternary turns into "No value was returned".
    out := ""
    if FileExist(tmp)
        try out := FileRead(tmp, "UTF-8")
    try FileDelete(tmp)
    try FileDelete(script)
    return { code: code, out: out }
}

; Convenience: the raw stdout of a snippet that is expected to succeed.
SnippetOut(src) => RunSnippet(src).out
