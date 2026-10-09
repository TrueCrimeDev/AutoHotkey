#Requires AutoHotkey v2.1-alpha.30
#Include Harness.ahk
; qa/run.ahk -- subprocess regression runner for this AHK fork.
;
; Every qa/tests/test_*.ahk is a standalone script that #Includes ..\Assert.ahk
; and ends with Assert.Summary(). The runner launches each one in its OWN
; process, so a test that throws at runtime or dies at load time (parse error,
; fatal) is a normal, assertable outcome instead of aborting the whole suite --
; which the NewLoop single-process #Include model cannot do.
;
; Per test we capture stdout + the process exit code:
;   * a "qa: P passed, F failed" line present  -> tally P/F, status PASS/FAIL
;   * that line absent                          -> the test crashed before
;                                                  Summary(); count 1 failure,
;                                                  status CRASH, echo its output
;
; Suite exit code = total failing assertions + crashes, so `$? -eq 0` from any
; shell means the whole tree is green.
;
; Usage (PowerShell or cmd, from the repo root):
;   bin\AutoHotkey64Console.exe /Headless /ErrorStdOut qa\run.ahk
; Usage (Git Bash, which rewrites a leading / into a path):
;   ./bin/AutoHotkey64Console.exe --headless //ErrorStdOut qa/run.ahk
; Use the console engine: PowerShell does not wait for the GUI AutoHotkey64.exe
; unless its output is piped, so $LASTEXITCODE would not be the suite's result.
; AHK_QA_TIMEOUT_MS overrides the 30000 ms per-child timeout.
; AHK_QA_JUNIT=<path> also writes a JUnit XML report: one testsuite per test
; file, one testcase per assertion (qa/README.md describes the shape).

engine  := A_AhkPath
testDir := A_ScriptDir "\tests"

files := []
Loop Files testDir "\test_*.ahk"
    files.Push(A_LoopFileFullPath)

; Deterministic order regardless of filesystem enumeration.
StableSort(files)

if !files.Length {
    Print("qa: no test files found in {}", testDir)
    ExitApp 1
}

totalPassed := 0
totalFailed := 0
crashes     := 0
idx         := 0
suites      := []
junitPath   := EnvGet("AHK_QA_JUNIT")
suiteStarted := A_TickCount

Print("qa: running {} test file(s) with {}", files.Length, engine)
Print("")

for file in files {
    idx += 1
    name := NameOf(file)
    suite := NewSuite(name)
    suites.Push(suite)
    started := A_TickCount
    try result := RunQaChild(file)
    catch as error {
        crashes += 1
        Print("  [CRASH] {}  (could not run: {})", name, error.Message)
        suite["ms"] := A_TickCount - started
        SuiteCrash(suite, "could not run: " error.Message, "")
        continue
    }
    code := result.code, out := result.out
    suite["ms"] := A_TickCount - started
    if result.timedOut {
        crashes += 1
        Print("  [TIMEOUT] {}  (exceeded {} ms; child tree terminated)", name, result.timeoutMs)
        EchoIndented(out)
        SuiteCrash(suite, "exceeded " result.timeoutMs " ms; child tree terminated", out)
    } else if RegExMatch(out, "m)^qa: (\d+) passed, (\d+) failed\r?$", &m) {
        p := Integer(m[1]), f := Integer(m[2])
        if code != f {
            crashes += 1
            Print("  [CRASH] {}  (exit {} disagrees with summary failures {})", name, code, f)
            EchoIndented(out)
            SuiteCrash(suite, "exit " code " disagrees with summary failures " f, out)
            continue
        }
        totalPassed += p
        totalFailed += f
        status := f ? "FAIL" : "PASS"
        Print("  [{}] {}  ({} passed, {} failed)", status, name, p, f)
        EchoFailLines(out)
        SuiteCases(suite, out, p, f)
    } else {
        crashes += 1
        Print("  [CRASH] {}  (exit {}, no summary line)", name, code)
        EchoIndented(out)
        SuiteCrash(suite, "exit " code ", no summary line", out)
    }
}

Print("")
grandFail := totalFailed + crashes
Print("qa: {} passed, {} failed, {} crashed across {} file(s)",
      totalPassed, grandFail, crashes, files.Length)
if junitPath != "" {
    try WriteJUnit(junitPath, suites, A_TickCount - suiteStarted)
    catch as error
        Print('qa: JUnit report "{}" not written: {}', junitPath, error.Message)
}
ExitApp grandFail

; ---- helpers ----

NameOf(path) => RegExReplace(path, "^.*[\\/]", "")

; Echo only the "  FAIL ..." and "  SKIP ..." detail lines a test emitted.
EchoFailLines(out) {
    for line in StrSplit(out, "`n", "`r")
        if RegExMatch(line, "^\s*(FAIL|SKIP) ")
            Print("    {}", Trim(line))
}

; Echo every non-empty line, indented, for a crashed test.
EchoIndented(out) {
    for line in StrSplit(out, "`n", "`r")
        if Trim(line) != ""
            Print("      {}", Trim(line, "`r`n"))
}

; In-place insertion sort -- avoids relying on a fork Sort() BIF signature.
StableSort(arr) {
    Loop arr.Length - 1 {
        i := A_Index + 1
        key := arr[i]
        j := i - 1
        while (j >= 1 && StrCompare(arr[j], key) > 0) {
            arr[j + 1] := arr[j]
            j -= 1
        }
        arr[j + 1] := key
    }
}

; One Map per test file for the JUnit report: counts, elapsed ms and the
; testcases (Maps with name, status pass|fail|error|skipped, message, text).
NewSuite(name) => Map("name", name, "tests", 0, "failures", 0, "errors", 0, "skipped", 0, "ms", 0, "cases", [])

; A file with no usable summary is one errored testcase carrying the runner's
; reason and the child's output (capped so a runaway child cannot bloat the report).
SuiteCrash(suite, message, out) {
    suite["tests"] := 1, suite["errors"] := 1
    text := Trim(out, " `t`r`n")
    if StrLen(text) > 65536
        text := SubStr(text, 1, 65536) "`n... (truncated)"
    suite["cases"].Push(Map("name", suite["name"], "status", "error",
        "message", message, "text", text))
}

; Testcases from a child's "  PASS/FAIL/SKIP ..." lines, in output order. The
; counts come from the summary line; unnamed cases pad any difference so the
; report's element counts always equal the summary (a test may print its own
; summary without Assert.ahk, which prints PASS lines only under AHK_QA_JUNIT).
SuiteCases(suite, out, passed, failed) {
    cases := suite["cases"]
    seenPass := 0, seenFail := 0, skipped := 0
    for line in StrSplit(out, "`n", "`r") {
        if !RegExMatch(line, "^\s*(PASS|FAIL|SKIP) (.*?)\s*$", &m)
            continue
        if m[1] = "PASS" && seenPass < passed {
            cases.Push(Map("name", m[2], "status", "pass"))
            seenPass += 1
        } else if m[1] = "FAIL" && seenFail < failed {
            cases.Push(FailCase(m[2]))
            seenFail += 1
        } else if m[1] = "SKIP" {
            cases.Push(Map("name", m[2], "status", "skipped", "message", m[2]))
            skipped += 1
        }
    }
    while seenPass < passed {
        seenPass += 1
        cases.Push(Map("name", "pass #" seenPass, "status", "pass"))
    }
    while seenFail < failed {
        seenFail += 1
        cases.Push(Map("name", "fail #" seenFail, "status", "fail",
            "message", "assertion failed (no FAIL line)", "text", ""))
    }
    suite["tests"] := passed + failed + skipped
    suite["failures"] := failed, suite["skipped"] := skipped
}

; Splits "label -- detail  (file:line)" as Assert.fail prints it: the detail
; becomes the failure message and file:line its text, as tests/Test.ahk writes.
FailCase(text) {
    tc := Map("name", text, "status", "fail", "message", text, "text", "")
    if RegExMatch(text, "^(.*?) -- (.*?)(?:  \((.+):(\d+)\))?$", &m) {
        tc["name"] := m[1], tc["message"] := m[2]
        if m[3] != ""
            tc["text"] := m[3] ":" m[4]
    }
    return tc
}

; JUnit XML with one testsuite per file and one testcase per assertion, in the
; shape tests/Test.ahk writes. The document goes to a temp file beside <path>
; and is moved into place, so a reader never sees a partial file. Any failure
; propagates to the caller, which reports it without changing the exit code.
WriteJUnit(path, suites, totalMs) {
    tests := 0, failures := 0, errors := 0, skipped := 0
    body := ""
    for suite in suites {
        tests += suite["tests"], failures += suite["failures"]
        errors += suite["errors"], skipped += suite["skipped"]
        body .= Format('  <testsuite name="{}" tests="{}" failures="{}" errors="{}" skipped="{}" time="{:.3f}">`n',
            XmlEscape(suite["name"]), suite["tests"], suite["failures"], suite["errors"], suite["skipped"], suite["ms"] / 1000)
        for tc in suite["cases"] {
            body .= Format('    <testcase name="{}" classname="{}"', XmlEscape(tc["name"]), XmlEscape(suite["name"]))
            switch tc["status"] {
                case "pass":
                    body .= " />`n"
                case "skipped":
                    body .= Format('>`n      <skipped message="{}" />`n    </testcase>`n', XmlEscape(tc["message"]))
                default:
                    tag := tc["status"] = "fail" ? "failure" : "error"
                    body .= Format('>`n      <{1} message="{2}">{3}</{1}>`n    </testcase>`n',
                        tag, XmlEscape(tc["message"]), XmlEscape(tc["text"]))
            }
        }
        body .= "  </testsuite>`n"
    }
    xml := '<?xml version="1.0" encoding="UTF-8"?>`n'
    xml .= Format('<testsuites name="qa" tests="{}" failures="{}" errors="{}" skipped="{}" time="{:.3f}">`n',
        tests, failures, errors, skipped, totalMs / 1000)
    xml .= body "</testsuites>`n"
    tmp := path "." ProcessExist() ".tmp"
    try {
        SplitPath(path, , &dir)
        if dir != ""
            DirCreate(dir)
        f := FileOpen(tmp, "w", "UTF-8-RAW")
        f.Write(xml)
        f.Close()
        FileMove(tmp, path, 1)
    } finally {
        f := ""
        if FileExist(tmp)
            try FileDelete(tmp)
    }
}

; Escapes attribute and text content; characters XML 1.0 forbids (control
; codes a crashed child may print) are dropped.
XmlEscape(text) {
    text := RegExReplace(String(text), "[^\x09\x0A\x0D\x20-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]")
    text := StrReplace(text, "&", "&amp;")
    text := StrReplace(text, "<", "&lt;")
    text := StrReplace(text, ">", "&gt;")
    return StrReplace(text, '"', "&quot;")
}
