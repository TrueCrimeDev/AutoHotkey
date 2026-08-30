#Requires AutoHotkey v2.1-alpha.30
; test_check_bif.ahk - exercises the native Check(Source) BIF.
; Run:  bin\AutoHotkey64.exe tests\test_check_bif.ahk   ; exits 0 all pass, 1 otherwise.
; All multi-line sources are built via Chr(10) concatenation (no heredoc).
failures := 0
nl := Chr(10)
Ok(label) {
    Print("PASS  {}", label)
}
Bad(label, detail := "") {
    global failures
    failures += 1
    if (detail != "")
        Print("FAIL  {} -- {}", label, detail)
    else
        Print("FAIL  {}", label)
}
; Case 1: valid script -> Ok=1, no diagnostics.
r := Check("x := 42" nl "MsgBox(x)" nl)
if (r.Ok = 1 && r.Diagnostics.Length = 0)
    Ok("valid script -> Ok=1, no diagnostics")
else
    Bad("valid script", "Ok=" r.Ok " diagCount=" r.Diagnostics.Length " raw=" r.Raw)
; Case 2: broken script (unmatched paren) -> Ok=0 with a real diagnostic.
r := Check("x := (1 + " nl "MsgBox(")
if (r.Ok = 0) {
    if (r.Diagnostics.Length >= 1) {
        d := r.Diagnostics[1]
        if (d.Line > 0 && StrLen(d.Message) > 0)
            Ok("broken script -> Ok=0, Line>0, Message present")
        else
            Bad("broken script diagnostic fields", "Line=" d.Line " Message='" d.Message "'")
    } else
        Bad("broken script", "Ok=0 but no diagnostics; raw=" r.Raw)
} else
    Bad("broken script", "expected Ok=0, got Ok=" r.Ok " raw=" r.Raw)
; Case 3: fork-only syntax the engine accepts but the tree-sitter grammar mis-flags
; (typed Struct fields, fat-arrow methods, and a ^j:: hotkey -- all verified valid).
forkSrc := "Struct Pt {" nl
forkSrc .= "    x: Int32, y: Int32" nl
forkSrc .= "}" nl
forkSrc .= "class C {" nl
forkSrc .= "    M() => 42" nl
forkSrc .= "}" nl
forkSrc .= "^j::MsgBox('hi')" nl
r := Check(forkSrc)
ts := TSParse(forkSrc)
if (r.Ok = 1) {
    if (ts.HasError = 1)
        Ok("fork-valid trio -> Check Ok=1 AND TSParse.HasError=1 (grammar mis-flags)")
    else
        Ok("fork-valid trio -> Check Ok=1 (TSParse.HasError=0; grammar improved)")
} else
    Bad("fork-valid trio", "expected Check Ok=1, got Ok=" r.Ok " raw=" r.Raw)
; Case 4: host state untouched (Check runs in a CHILD process).
sentinel := 1234
AddOne(n) => n + 1
before := sentinel
Check("loop 3" nl "{" nl "  y := A_Index" nl "}" nl)
if (sentinel = before && sentinel = 1234 && AddOne(41) = 42)
    Ok("host state intact after Check (var + func still work)")
else
    Bad("host state intact", "sentinel=" sentinel " AddOne(41)=" AddOne(41))
; Case 5: cross-check Check.Ok against a direct CLI /Check invocation.
CliCheck(src) {
    tmp := A_Temp "\check_cli_" A_TickCount "_" Random(1, 99999) ".ahk"
    f := FileOpen(tmp, "w", "UTF-8")
    f.Write(src)
    f.Close()
    code := RunWait('"' A_AhkPath '" /Check "' tmp '"', , "Hide")
    try FileDelete(tmp)
    return code
}
validSrc  := "x := 1" nl "MsgBox(x)" nl
brokenSrc := "x := (1 + " nl
cv := Check(validSrc)
cb := Check(brokenSrc)
cliV := CliCheck(validSrc)
cliB := CliCheck(brokenSrc)
parityV := (cv.Ok = 1) && (cliV = 0)
parityB := (cb.Ok = 0) && (cliB = 13)
if (parityV && parityB)
    Ok("Check.Ok matches direct CLI /Check exit code (valid=0, broken=13)")
else
    Bad("CLI parity", "Check.Ok valid=" cv.Ok " cli=" cliV " | broken=" cb.Ok " cli=" cliB)
if (failures = 0) {
    Print("ALL PASS")
    ExitApp(0)
} else {
    Print("{} FAILED", failures)
    ExitApp(1)
}
