#Requires AutoHotkey v2.1-alpha.30
; test_ahkmon.ahk - windowless diagnostic snapshot (WM_COPYDATA AHKQ/AHKR).
; Spawns a hidden target script, queries its four lists, and asserts:
;   * a reply arrives with the @@AHKMON@@ sentinel blob,
;   * requested views appear in requested order, with the probe var/hotkey present,
;   * the target's main window never becomes visible and the foreground never changes.
; Run:  bin\AutoHotkey64.exe tests\test_ahkmon.ahk   ; exits 0 all pass, 1 otherwise.
#SingleInstance Off
DetectHiddenWindows(true)

global g_reply := ""
failures := 0
WM_COPYDATA := 0x4A
AHKQ := 0x41484B51
AHKR := 0x41484B52
WS_VISIBLE := 0x10000000

Fail(msg) {
    global failures
    failures += 1
    Print("FAIL  {}", msg)
}
Pass(msg) => Print("PASS  {}", msg)

OnCopyData(wParam, lParam, msg, hwnd) {
    global g_reply, AHKR
    if (NumGet(lParam, 0, "UPtr") != AHKR)
        return 0
    cb := NumGet(lParam, A_PtrSize, "UInt")
    p  := NumGet(lParam, A_PtrSize * 2, "Ptr")
    g_reply := (p && cb) ? StrGet(p, cb, "UTF-8") : ""
    return 1
}
OnMessage(WM_COPYDATA, OnCopyData)

SendReq(target, replyHwnd, views) {
    global g_reply, AHKQ, WM_COPYDATA
    g_reply := ""
    payload := replyHwnd "`n" views
    nbytes := StrPut(payload, "UTF-8") - 1            ; bytes, excluding NUL
    buf := Buffer(nbytes + 1)
    StrPut(payload, buf, "UTF-8")
    cds := Buffer(A_PtrSize * 2 + 8, 0)
    NumPut("UPtr", AHKQ,    cds, 0)
    NumPut("UInt", nbytes,  cds, A_PtrSize)
    NumPut("Ptr",  buf.Ptr, cds, A_PtrSize * 2)
    DllCall("SendMessageW", "Ptr", target, "UInt", WM_COPYDATA, "Ptr", replyHwnd, "Ptr", cds.Ptr)
    loop 50 {                                          ; reply normally arrives synchronously
        if (g_reply != "")
            break
        Sleep(10)
    }
    return g_reply
}

; --- write + launch a hidden target script ---
nl := Chr(10)
hwndFile := A_Temp "\ahkmon_tgt_hwnd_" A_TickCount ".txt"
try FileDelete(hwndFile)
tgt := "#Requires AutoHotkey v2.1-alpha.30" nl
tgt .= "Persistent" nl
tgt .= "global g_ahkmon_probe := 'PROBE_VALUE_31337'" nl
tgt .= "ProbeFn(a, b) => a + b" nl
tgt .= "^!+F12::MsgBox('probe hotkey')" nl
tgt .= "fh := FileOpen('" hwndFile "', 'w')" nl  ; AHK string literals keep backslashes literal
tgt .= "fh.Write(A_ScriptHwnd '')" nl
tgt .= "fh.Close()" nl
tgtFile := A_Temp "\ahkmon_tgt_" A_TickCount ".ahk"
f := FileOpen(tgtFile, "w", "UTF-8")
f.Write(tgt)
f.Close()
Run('"' A_AhkPath '" "' tgtFile '"', , "Hide", &tgtPid)

target := 0
loop 100 {
    if FileExist(hwndFile) {
        try target := Integer(Trim(FileRead(hwndFile)))
        if target
            break
    }
    Sleep(50)
}
if !target {
    Fail("target did not start / publish its main window hwnd")
    Print("1 FAILED")
    ExitApp(1)
}

Cleanup() {
    global tgtPid, tgtFile, hwndFile
    try ProcessClose(tgtPid)
    try FileDelete(tgtFile)
    try FileDelete(hwndFile)
}

; --- baseline foreground + target visibility ---
fgBefore  := DllCall("GetForegroundWindow", "Ptr")
visBefore := WinGetStyle("ahk_id " target) & WS_VISIBLE
if (visBefore != 0)
    Fail("target main window was already VISIBLE before any request")

; --- request all four views ---
reply := SendReq(target, A_ScriptHwnd, "ListLines,ListHotkeys,ListVars,KeyHistory")
fgAfter  := DllCall("GetForegroundWindow", "Ptr")
visAfter := WinGetStyle("ahk_id " target) & WS_VISIBLE

if (reply != "")
    Pass("reply received (AHKR)")
else
    Fail("no AHKR reply received")

if (fgBefore = fgAfter)
    Pass("foreground window unchanged across request")
else
    Fail("foreground CHANGED: " fgBefore " -> " fgAfter)

if (visAfter = 0 && visBefore = 0)
    Pass("target main window stayed hidden (WS_VISIBLE clear)")
else
    Fail("target visibility changed: before=" visBefore " after=" visAfter)

if InStr(reply, "@@AHKMON snapshot ") && InStr(reply, "@@AHKMON end@@")
    Pass("header + end sentinels present")
else
    Fail("missing snapshot/end sentinels")

for v in ["ListLines", "ListHotkeys", "ListVars", "KeyHistory"]
    if InStr(reply, "@@AHKMON view=" v "@@")
        Pass("view block present: " v)
    else
        Fail("view block missing: " v)

if InStr(reply, "g_ahkmon_probe")
    Pass("ListVars contains the target's probe var")
else
    Fail("ListVars missing g_ahkmon_probe")

if InStr(reply, "F12")
    Pass("ListHotkeys contains the target's hotkey")
else
    Fail("ListHotkeys missing the ^!+F12 hotkey")

; --- order is honored: ListVars before ListLines when requested that way ---
r2 := SendReq(target, A_ScriptHwnd, "ListVars,ListLines")
pv := InStr(r2, "@@AHKMON view=ListVars@@")
pl := InStr(r2, "@@AHKMON view=ListLines@@")
if (pv && pl && pv < pl)
    Pass("views returned in requested order (ListVars before ListLines)")
else
    Fail("view order not honored (pv=" pv " pl=" pl ")")

; --- repeatable: 100 requests, no visibility change, foreground stable ---
ok100 := true
loop 100 {
    rr := SendReq(target, A_ScriptHwnd, "ListVars")
    if (rr = "" || (WinGetStyle("ahk_id " target) & WS_VISIBLE))
        ok100 := false
}
if (ok100 && DllCall("GetForegroundWindow", "Ptr") = fgBefore)
    Pass("100x requests: all replied, never shown, foreground stable")
else
    Fail("100x stress failed (replies/visibility/foreground)")

Cleanup()
if (failures = 0) {
    Print("ALL PASS")
    ExitApp(0)
} else {
    Print("{} FAILED", failures)
    ExitApp(1)
}
