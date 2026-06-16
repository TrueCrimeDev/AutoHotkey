#Requires AutoHotkey v2.1-alpha.30
#SingleInstance Off
;==============================================================================
; ahkmon-reader.ahk — windowless diagnostic snapshot reader (AHKMON protocol)
;
; Performs the WM_COPYDATA request/response round-trip against a *running*
; AutoHotkey +Console fork script and writes the raw @@AHKMON@@ blob (UTF-8, no
; BOM) to stdout. The target's main window never shows, activates, or takes focus.
;
; Usage:
;   AutoHotkey64.exe ahkmon-reader.ahk <target> [views] [timeoutMs]
;     <target>    target identifier: a decimal main-window HWND, "hwnd:<n>",
;                 or "pid:<n>" (resolved to that process's main window).
;     [views]     comma-separated subset of
;                 ListLines,ListHotkeys,ListVars,KeyHistory
;                 (default: all four, in that order). Case-insensitive.
;     [timeoutMs] max wait for the reply (default 4000).
;
; Exit codes: 0 = blob written to stdout; 1 = no/!window/no reply; 2 = bad args.
; Spawn this from your editor/extension and read its stdout.
;==============================================================================
DetectHiddenWindows(true)

AHKQ := 0x41484B51   ; 'AHKQ' request
AHKR := 0x41484B52   ; 'AHKR' reply
WM_COPYDATA := 0x4A

if (A_Args.Length < 1) {
    Stderr("usage: ahkmon-reader.ahk <hwnd|hwnd:N|pid:N> [views] [timeoutMs]   |   ahkmon-reader.ahk list")
    ExitApp(2)
}

; --- discovery: `list` prints one running AutoHotkey script per line as ---
;     <mainHwndDecimal>\t<pid>\t<title>   (title = script path + " - AutoHotkey <ver>")
; The extension matches the title's path to the open file; querying a listed
; target that does not reply (exit 1) means it is stock AHK or a non-AHKMON fork.
if (A_Args[1] = "list" || A_Args[1] = "--list") {
    out := ""
    for hwnd in WinGetList("ahk_class AutoHotkey")
        out .= hwnd "`t" WinGetPID("ahk_id " hwnd) "`t" WinGetTitle("ahk_id " hwnd) "`n"
    FileOpen("*", "w", "UTF-8-RAW").Write(out)
    ExitApp(0)
}

; --- resolve the target's MAIN window HWND ---
arg := A_Args[1]
target := 0
if (SubStr(arg, 1, 4) = "pid:") {
    pid := Integer(SubStr(arg, 5))
    target := WinExist("ahk_pid " pid)          ; AHK's main window for that process
} else if (SubStr(arg, 1, 5) = "hwnd:") {
    target := Integer(SubStr(arg, 6))
} else {
    target := Integer(arg)
}
if (!target || !DllCall("IsWindow", "Ptr", target)) {
    Stderr("error: could not resolve a live target window from '" arg "'")
    ExitApp(1)
}

views := A_Args.Length >= 2 && A_Args[2] != "" ? A_Args[2] : "ListLines,ListHotkeys,ListVars,KeyHistory"
timeoutMs := A_Args.Length >= 3 ? Integer(A_Args[3]) : 4000

; --- receive the reply (delivered synchronously during our SendMessage) ---
global g_reply := ""
global g_got := false
OnMessage(WM_COPYDATA, Recv)
Recv(wParam, lParam, msg, hwnd) {
    global g_reply, g_got, AHKR
    if (NumGet(lParam, 0, "UPtr") != AHKR)
        return 0
    cb := NumGet(lParam, A_PtrSize, "UInt")
    p  := NumGet(lParam, A_PtrSize * 2, "Ptr")
    g_reply := (p && cb) ? StrGet(p, cb, "UTF-8") : ""
    g_got := true
    return 1
}

; --- send the request: payload = "<replyHwndDecimal>\n<views CSV>" (UTF-8) ---
payload := A_ScriptHwnd "`n" views
buf := Buffer(StrPut(payload, "UTF-8"))
StrPut(payload, buf, "UTF-8")
cds := Buffer(A_PtrSize * 2 + 8, 0)             ; COPYDATASTRUCT
NumPut("UPtr", AHKQ,         cds, 0)            ; dwData
NumPut("UInt", buf.Size - 1, cds, A_PtrSize)   ; cbData = byte length (no NUL)
NumPut("Ptr",  buf.Ptr,      cds, A_PtrSize * 2) ; lpData
DllCall("SendMessageW", "Ptr", target, "UInt", WM_COPYDATA, "Ptr", A_ScriptHwnd, "Ptr", cds.Ptr)

waited := 0
while (!g_got && waited < timeoutMs) {
    Sleep(10)
    waited += 10
}
if (!g_got) {
    Stderr("error: no AHKR reply within " timeoutMs "ms (is the target running the +Console fork with AHKMON support?)")
    ExitApp(1)
}

FileOpen("*", "w", "UTF-8-RAW").Write(g_reply)  ; raw blob to stdout, no BOM
ExitApp(0)

Stderr(text) => FileOpen("**", "w", "UTF-8-RAW").Write(text "`n")
