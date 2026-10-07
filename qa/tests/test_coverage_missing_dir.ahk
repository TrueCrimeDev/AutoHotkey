#Requires AutoHotkey v2.1-alpha.31
#Include ..\Assert.ahk
; test_coverage_missing_dir.ahk -- /Coverage=<path> when the directory that
; should hold <path> does not exist.
;
; KNOWN BUG, pinned here as the CURRENT behavior so that a change is noticed:
; the engine neither creates the missing directory nor reports that it could
; not write the report. The run exits 0 (the test verb prints TEST PASS),
; stderr stays empty, and no LCOV file appears, so a CI step that forgot to
; create its coverage directory silently loses its coverage.
;
; Cause, in source/coverage.cpp (2.1-alpha.31+Console):
;   * WriteWholeFile (anonymous namespace, about lines 88-99) calls
;     CreateFile(aPath, GENERIC_WRITE, ..., CREATE_ALWAYS, ...). With a missing
;     parent directory that fails (ERROR_PATH_NOT_FOUND), and
;     `if (h == INVALID_HANDLE_VALUE) return;` drops the report silently.
;   * Coverage::SetPath (about lines 102-114) only stores GetFullPathName's
;     result; it never checks or creates the directory.
;   * Coverage::Flush (about lines 145-185) returns void, so the exit code
;     cannot reflect the failed write.
;
; When the engine is fixed, FLIP the assertions labelled "CURRENT BUG":
;   * if it creates the directory: expect the directory and the report to
;     exist and to hold the probe's SF/DA records, as in the control case;
;   * if it reports the failure instead: expect a diagnostic on stderr that
;     names the path, and whichever exit code the fix chooses.
; The control case (an existing directory) must keep passing either way.
;
; Each case starts its own child engine through ProcessPipe, because the
; harness's RunQaChild/RunSnippet place extra arguments after the script path
; (where they become script arguments) and add their own /Coverage= flag when
; AHK_QA_COVERAGE_DIR is set.

root := A_Temp "\qa_cov_dir_" ProcessExist() "_" A_TickCount
DirCreate(root)
probe := root "\probe.ahk"
FileOpen(probe, "w", "UTF-8-RAW").Write('x := 1`nPrint("probe ran {}", x)`n')

; Runs `test probe.ahk` under /Coverage=<lcov>; returns {code, out, err}.
RunWithCoverage(lcov) {
    global probe
    p := ProcessPipe(A_AhkPath, ["/Headless", "/Coverage=" lcov, "test", probe])
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

try {
    ; --- control: the directory exists, so the report is written ---------------
    okDir := root "\existing"
    DirCreate(okDir)
    okLcov := okDir "\probe.lcov"
    r := RunWithCoverage(okLcov)
    Assert.eq(r.code, 0, "control: test run exits 0")
    Assert.truthy(InStr(r.out, "probe ran 1"), "control: probe executed")
    Assert.truthy(InStr(r.out, "TEST PASS"), "control: test verb reports TEST PASS")
    Assert.truthy(FileExist(okLcov), "control: report written into an existing directory")
    report := FileExist(okLcov) ? FileRead(okLcov, "UTF-8") : ""
    Assert.truthy(InStr(report, "SF:") && InStr(report, "probe.ahk"), "control: report names the probe file")
    Assert.truthy(InStr(report, "DA:1,1") && InStr(report, "DA:2,1"), "control: both probe lines counted as hit")
    Assert.truthy(InStr(report, "end_of_record"), "control: record terminated")

    ; --- missing directory: nothing is written and nothing is reported ---------
    missingDir := root "\missing"
    missingLcov := missingDir "\sub\probe.lcov"
    r := RunWithCoverage(missingLcov)
    Assert.truthy(InStr(r.out, "probe ran 1"), "missing dir: probe executed")
    Assert.eq(r.code, 0, "missing dir: CURRENT BUG - run still exits 0")
    Assert.truthy(InStr(r.out, "TEST PASS"), "missing dir: CURRENT BUG - test verb still reports TEST PASS")
    Assert.eq(r.err, "", "missing dir: CURRENT BUG - no diagnostic on stderr")
    Assert.falsy(FileExist(missingLcov), "missing dir: CURRENT BUG - no report written")
    Assert.falsy(DirExist(missingDir), "missing dir: CURRENT BUG - directory not created")
} finally {
    try DirDelete(root, true)
}

Assert.Summary()
