#Requires AutoHotkey v2.1-alpha.30
; qa/Assert.ahk -- minimal assertion collector for the fork's regression
; suite. A test file #Includes this, fires asserts, then calls
; Assert.Summary() as its last statement. Summary prints a machine-parseable
; result line (consumed by run.ahk) and exits with code = failure count, so a
; standalone `$? -eq 0` means the file is green even when run on its own.
;
; Depends on this fork's variadic Print() BIF for console output.

class Assert {
    static passed := 0
    static failed := 0

    ; Strict equality. Numbers and strings compare by value with ==.
    static eq(actual, expected, label) {
        if (actual == expected) {
            Assert.passed += 1
            return
        }
        Assert.failed += 1
        Print("  FAIL {} -- expected: {}  actual: {}", label, expected, actual)
    }

    ; The value must be truthy (non-zero, non-empty).
    static truthy(cond, label) {
        if cond {
            Assert.passed += 1
            return
        }
        Assert.failed += 1
        Print("  FAIL {} -- expected truthy, got falsy", label)
    }

    ; The value must be falsy.
    static falsy(cond, label) {
        if !cond {
            Assert.passed += 1
            return
        }
        Assert.failed += 1
        Print("  FAIL {} -- expected falsy, got truthy", label)
    }

    ; fn must raise. Optionally assert the thrown Message contains `msgPart`.
    static throws(fn, label, msgPart := "") {
        try {
            fn()
        } catch as e {
            if (msgPart != "" && !InStr(e.Message, msgPart)) {
                Assert.failed += 1
                Print("  FAIL {} -- threw but message '{}' lacks '{}'", label, e.Message, msgPart)
                return
            }
            Assert.passed += 1
            return
        }
        Assert.failed += 1
        Print("  FAIL {} -- no exception raised", label)
    }

    ; fn must NOT raise; its return value is otherwise ignored.
    static noThrow(fn, label) {
        try {
            fn()
        } catch as e {
            Assert.failed += 1
            Print("  FAIL {} -- unexpected exception: {}", label, e.Message)
            return
        }
        Assert.passed += 1
    }

    static Summary() {
        ; Parseable contract line for run.ahk, then exit code = failures.
        Print("qa: {} passed, {} failed", Assert.passed, Assert.failed)
        ExitApp Assert.failed
    }
}
