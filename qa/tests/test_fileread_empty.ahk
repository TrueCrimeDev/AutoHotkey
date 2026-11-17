#Requires AutoHotkey v2.1-alpha.39
; test_fileread_empty.ahk -- FileRead of a zero-byte file returns "" rather than
; no value. Upstream (source/lib/file.cpp) returned OK without setting a result,
; which v2.0 mode reads as "" but a top-level v2.1 #Requires turns into
; UnsetError "No value was returned.". Each case runs in a child process so the
; #Requires sits at the top of the child's own main file.
#Include ..\Assert.ahk
#Include ..\Harness.ahk

Lines(parts*) {
    out := ""
    for p in parts
        out .= p "`n"
    return out
}

Snippet(requires, readCall) => Lines(
    requires,
    "f := A_Temp '\qa_fileread_empty_' ProcessExist() '.txt'",
    "FileAppend('', f)",
    "try v := " readCall,
    "catch as e",
    "    v := Type(e)",
    "FileDelete(f)",
    "Print(Type(v) ' [' (v is Buffer ? v.Size : v) ']')")

r := RunSnippet(Snippet("#Requires AutoHotkey v2.1-alpha.39", "FileRead(f)"))
Assert.eq(r.code " " r.out, "0 String []`n", "fileread.empty.v21.string")

r := RunSnippet(Snippet("", "FileRead(f)"))
Assert.eq(r.code " " r.out, "0 String []`n", "fileread.empty.v20.string")

r := RunSnippet(Snippet("#Requires AutoHotkey v2.1-alpha.39", "FileRead(f, 'RAW')"))
Assert.eq(r.code " " r.out, "0 Buffer [0]`n", "fileread.empty.raw.buffer")

Assert.Summary()
