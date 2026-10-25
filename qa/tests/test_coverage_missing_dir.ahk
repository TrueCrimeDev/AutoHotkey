#Requires AutoHotkey v2.1-alpha.31
#Include ..\Assert.ahk
; test_coverage_missing_dir.ahk -- /Coverage=<path> when the directory that
; should hold <path> does not exist, or cannot exist.
;
; source/coverage.cpp (WriteWholeFile, ReportWriteFailure):
;   * a missing directory is created, every level of it, before the report is
;     written, whether the path is absolute or relative and whichever separator
;     it uses (FileCreateDir, DirCreate's helper);
;   * when the report still cannot be written, one line on stderr names the
;     report path and the Win32 error (a JSON diagnostic under /Diag=json);
;   * the exit code is left alone either way: coverage observes the run, so a
;     passing test still exits 0 and prints TEST PASS.
; Engines before ec684fd0 wrote nothing, printed nothing and exited 0 here, so
; a CI step that forgot to create its coverage directory lost its coverage;
; this test fails on them.
;
; Each case starts its own child engine through ProcessPipe, because the
; harness's RunQaChild/RunSnippet place extra arguments after the script path
; (where they become script arguments) and add their own /Coverage= flag when
; AHK_QA_COVERAGE_DIR is set.

root := A_Temp "\qa_cov_dir_" ProcessExist() "_" A_TickCount
DirCreate(root)
probe := root "\probe.ahk"
FileOpen(probe, "w", "UTF-8-RAW").Write('x := 1`nPrint("probe ran {}", x)`n')

; Runs `test probe.ahk` under /Coverage=<lcov> and any extra engine options,
; from workDir when given; returns {code, out, err}.
RunWithCoverage(lcov, extra := [], workDir?) {
    global probe
    args := ["/Headless"]
    args.Push(extra*)
    args.Push("/Coverage=" lcov, "test", probe)
    p := ProcessPipe(A_AhkPath, args, workDir?)
    out := ""
    loop {
        line := p.ReadLine(30)
        if (line = "" && p.AtEOF)
            break
        out .= line "`n"
    }
    code := p.Wait(30)
    return {code: code, out: out, err: p.ReadStdErr()}
}

; The probe's LCOV record, as in the control case.
AssertReport(lcov, label) {
    Assert.truthy(FileExist(lcov), label ": report written")
    report := FileExist(lcov) ? FileRead(lcov, "UTF-8") : ""
    Assert.truthy(InStr(report, "SF:") && InStr(report, "probe.ahk"), label ": report names the probe file")
    Assert.truthy(InStr(report, "DA:1,1") && InStr(report, "DA:2,1"), label ": both probe lines counted as hit")
    Assert.truthy(InStr(report, "end_of_record"), label ": record terminated")
}

StdErrLines(err) => StrSplit(Trim(err, "`r`n"), "`n", "`r")

try {
    ; --- control: the directory exists, so the report is written ---------------
    okDir := root "\existing"
    DirCreate(okDir)
    okLcov := okDir "\probe.lcov"
    r := RunWithCoverage(okLcov)
    Assert.eq(r.code, 0, "control: test run exits 0")
    Assert.truthy(InStr(r.out, "probe ran 1"), "control: probe executed")
    Assert.truthy(InStr(r.out, "TEST PASS"), "control: test verb reports TEST PASS")
    Assert.eq(r.err, "", "control: no diagnostic on stderr")
    AssertReport(okLcov, "control")

    ; --- missing nested directory: created, then the report is written ---------
    missingDir := root "\missing"
    missingLcov := missingDir "\sub\probe.lcov"
    r := RunWithCoverage(missingLcov)
    Assert.truthy(InStr(r.out, "probe ran 1"), "missing dir: probe executed")
    Assert.eq(r.code, 0, "missing dir: run exits 0")
    Assert.truthy(InStr(r.out, "TEST PASS"), "missing dir: test verb reports TEST PASS")
    Assert.eq(r.err, "", "missing dir: no diagnostic on stderr")
    Assert.truthy(DirExist(missingDir "\sub"), "missing dir: every missing level created")
    AssertReport(missingLcov, "missing dir")

    ; --- relative path with forward slashes, resolved against the child's cwd --
    r := RunWithCoverage("rel/a/b/probe.lcov", , root)
    Assert.eq(r.code, 0, "relative: run exits 0")
    Assert.eq(r.err, "", "relative: no diagnostic on stderr")
    Assert.truthy(DirExist(root "\rel\a\b"), "relative: directories created under the working directory")
    AssertReport(root "\rel\a\b\probe.lcov", "relative")

    ; --- unwritable: a path component is an existing FILE ------------------------
    blocker := root "\blocker.txt"
    FileAppend("not a directory", blocker)
    blockedLcov := blocker "\sub\probe.lcov"
    r := RunWithCoverage(blockedLcov)
    Assert.truthy(InStr(r.out, "probe ran 1"), "unwritable: probe executed")
    Assert.eq(r.code, 0, "unwritable: exit code unchanged")
    Assert.truthy(InStr(r.out, "TEST PASS"), "unwritable: test verb still reports TEST PASS")
    lines := StdErrLines(r.err)
    Assert.eq(lines.Length, 1, "unwritable: one diagnostic line on stderr")
    Assert.truthy(InStr(r.err, '"' blockedLcov '"'), "unwritable: diagnostic names the report path")
    Assert.truthy(RegExMatch(r.err, "Win32 error \d+"), "unwritable: diagnostic names the Win32 error")
    Assert.truthy(FileExist(blocker) && !InStr(FileExist(blocker), "D"), "unwritable: blocking file is still a file")
    Assert.falsy(FileExist(blockedLcov), "unwritable: no report written")

    ; --- unwritable under /Diag=json: the line is a JSON diagnostic --------------
    r := RunWithCoverage(blockedLcov, ["/Diag=json"])
    Assert.eq(r.code, 0, "unwritable json: exit code unchanged")
    Assert.truthy(InStr(r.out, '"status":"pass"'), "unwritable json: test verb reports pass")
    lines := StdErrLines(r.err)
    Assert.eq(lines.Length, 1, "unwritable json: one diagnostic line on stderr")
    diag := ""
    try diag := JSON.Parse(lines[1])
    Assert.truthy(IsObject(diag), "unwritable json: stderr line parses as JSON")
    if IsObject(diag) {
        Assert.eq(diag.Get("kind", ""), "diagnostic", "unwritable json: kind")
        Assert.eq(diag.Get("severity", ""), "warning", "unwritable json: severity")
        Assert.eq(diag.Get("type", ""), "OSError", "unwritable json: type")
        Assert.eq(diag.Get("extra", ""), blockedLcov, "unwritable json: extra is the report path")
        Assert.truthy(RegExMatch(diag.Get("message", ""), "Win32 error \d+"), "unwritable json: message names the Win32 error")
    }
} finally {
    try DirDelete(root, true)
}

Assert.Summary()
