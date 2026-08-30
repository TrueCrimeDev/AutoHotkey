#Requires AutoHotkey v2.1-alpha.30
; test_crashlog.ahk -- the fork's #CrashLog directive (backlog #8).
;
; #CrashLog <path> installs a structured event log. Unlike Print/stderr, the
; records land in a FILE, so each case runs a child snippet (RunSnippet) that
; enables the directive against a unique temp log, then the parent reads that
; log back and asserts on the records. Empirically probed against
; 2.1-alpha.30+Console first (see crashlog.cpp LogStart/LogError/LogParse/
; LogExitWithCode):
;   * uncaught throw    -> [START] + [ERROR] (type/mode + Message/File/Line/
;                          What/Extra/Stack) + [EXIT] code=10 reason=Error.
;   * clean ExitApp 0   -> [START] + [EXIT] code=0 reason=Normal, no [ERROR].
;   * load-time parse   -> [PARSE] (file/line/Message) + [EXIT] code=12
;                          reason=Parse, and NO [START] -- LogStart only runs
;                          once the script parses and begins executing.
#Include ..\Assert.ahk
#Include ..\Harness.ahk

; A unique temp log path per case, so parallel/rerun cases never collide.
LogPath() {
    static seq := 0
    seq += 1
    return A_Temp "\qa_crashlog_" A_TickCount "_" seq ".log"
}

; Run `body` as a child with #CrashLog pointed at a fresh log; return
; { code, log } where log is the file's UTF-8 contents (then delete it).
RunWithCrashLog(body) {
    path := LogPath()
    try FileDelete(path)
    r := RunSnippet("#CrashLog " path "`n" body)
    log := FileExist(path) ? FileRead(path, "UTF-8") : ""
    try FileDelete(path)
    return { code: r.code, log: log }
}

; --- uncaught runtime error: START + ERROR + EXIT(code=10) ---
e := RunWithCrashLog('throw Error("boom msg", "MyFn", "extra bits")')
Assert.eq(e.code, 10, "uncaught error exits 10")
Assert.truthy(InStr(e.log, "[START] pid="), "error run logs a START record")
Assert.truthy(InStr(e.log, "[ERROR] pid="), "error run logs an ERROR record")
Assert.truthy(InStr(e.log, "type=Error mode=Exit"), "ERROR record carries type + mode")
Assert.truthy(InStr(e.log, "Message: boom msg"), "ERROR record logs the message")
Assert.truthy(InStr(e.log, "What: MyFn"),        "ERROR record logs What")
Assert.truthy(InStr(e.log, "Extra: extra bits"), "ERROR record logs Extra")
Assert.truthy(InStr(e.log, "code=10 reason=Error"), "EXIT record is code=10 reason=Error")

; --- clean exit: START + EXIT(code=0), and NO error record ---
c := RunWithCrashLog('ExitApp 0')
Assert.eq(c.code, 0, "clean ExitApp 0 exits 0")
Assert.truthy(InStr(c.log, "[START] pid="), "clean run still logs a START record")
Assert.truthy(InStr(c.log, "code=0 reason=Normal"), "EXIT record is code=0 reason=Normal")
Assert.falsy(InStr(c.log, "[ERROR]"), "clean run logs no ERROR record")

; --- load-time parse error: PARSE + EXIT(code=12), and NO START ---
; ("x := + +" is a missing-operand parse error; the directive on the line
;  above is already active when the parser reaches it.)
p := RunWithCrashLog('x := + +')
Assert.eq(p.code, 12, "parse error exits 12")
Assert.truthy(InStr(p.log, "[PARSE] pid="), "parse error logs a PARSE record")
Assert.truthy(InStr(p.log, "line=2"),       "PARSE record pins the offending line")
Assert.truthy(InStr(p.log, "code=12 reason=Parse"), "EXIT record is code=12 reason=Parse")
Assert.falsy(InStr(p.log, "[START]"), "parse error logs no START (never began executing)")

Assert.Summary()
