#Requires AutoHotkey v2.1-alpha.30
; qa/Assert.ahk -- minimal assertion collector for the fork's regression
; suite. A test file #Includes this, fires asserts, then calls
; Assert.Summary() as its last statement. Summary prints a machine-parseable
; result line (consumed by run.ahk) and exits with code = failure count, so a
; standalone `$? -eq 0` means the file is green even when run on its own.
;
; Depends on this fork's variadic Print() BIF for console output.
;
; Every failure prints "  FAIL <label> -- <detail>  (<file>:<line>)", naming
; the test line that called the assertion. When AHK_QA_JUNIT is set (run.ahk
; hands its environment to every child), each passing assertion also prints
; "  PASS <label>", so the runner can name every testcase in its JUnit report.

class Assert {
    static passed := 0
    static failed := 0
    static report := EnvGet("AHK_QA_JUNIT") != ""

    ; Strict equality. Numbers and strings compare by value with ==.
    static eq(actual, expected, label) {
        if (actual == expected)
            Assert.pass(label)
        else
            Assert.fail(label, Format("expected: {}  actual: {}", expected, actual))
    }

    ; The value must be truthy (non-zero, non-empty).
    static truthy(cond, label) {
        if cond
            Assert.pass(label)
        else
            Assert.fail(label, "expected truthy, got falsy")
    }

    ; The value must be falsy.
    static falsy(cond, label) {
        if !cond
            Assert.pass(label)
        else
            Assert.fail(label, "expected falsy, got truthy")
    }

    ; fn must raise. Optionally assert the thrown Message contains `msgPart`.
    static throws(fn, label, msgPart := "") {
        try {
            fn()
        } catch as e {
            if (msgPart != "" && !InStr(e.Message, msgPart))
                Assert.fail(label, Format("threw but message '{}' lacks '{}'", e.Message, msgPart))
            else
                Assert.pass(label)
            return
        }
        Assert.fail(label, "no exception raised")
    }

    ; fn must NOT raise; its return value is otherwise ignored.
    static noThrow(fn, label) {
        try {
            fn()
        } catch as e {
            Assert.fail(label, "unexpected exception: " e.Message)
            return
        }
        Assert.pass(label)
    }

    static pass(label) {
        Assert.passed += 1
        if Assert.report
            Print("  PASS {}", label)
    }

    ; Counts one failure and prints its detail line. The location is two
    ; frames up: the test line that called the assertion method.
    static fail(label, detail) {
        Assert.failed += 1
        where := Error("", -2)
        Print("  FAIL {} -- {}  ({}:{})", label, detail, where.File, where.Line)
    }

    static Summary() {
        ; Parseable contract line for run.ahk, then exit code = failures.
        Print("qa: {} passed, {} failed", Assert.passed, Assert.failed)
        ExitApp Assert.failed
    }
}
