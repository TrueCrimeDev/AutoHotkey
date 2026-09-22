#Requires AutoHotkey v2.1-alpha.31
; tests/Test.ahk -- single-process test framework for the engine's `test` subcommand.
;
; Usage (see tests/run.ahk):
;   #Include Test.ahk
;   #Include my_feature.test.ahk    ; each file registers cases with Test.Case()
;   Test.Run()                      ; prints results, exits 14 on any failure
;
; A test file:
;   Test.Case("adds numbers", () => Assert.Eq(1 + 1, 2))
;   Test.Case("rejects bad input", RejectsBadInput)
;   RejectsBadInput() {
;       Assert.Throws(() => Integer("x"), TypeError)
;   }
;
; Output is plain text via Print(). Under GitHub Actions each failure is also
; emitted as a `::error file=...,line=...::` workflow command so it shows up as
; an annotation on the PR diff. Set AHK_TEST_JUNIT=<path> to write JUnit XML.

class AssertionError extends Error {
}

class Assert {
    static Eq(actual, expected, label := "") {
        if !Assert.Same(actual, expected)
            throw AssertionError(Assert.Msg(label, "expected {} but got {}", Assert.Repr(expected), Assert.Repr(actual)), -1)
    }

    static NotEq(actual, unexpected, label := "") {
        if Assert.Same(actual, unexpected)
            throw AssertionError(Assert.Msg(label, "did not expect {}", Assert.Repr(unexpected)), -1)
    }

    static True(value, label := "") {
        if !value
            throw AssertionError(Assert.Msg(label, "expected truthy but got {}", Assert.Repr(value)), -1)
    }

    static False(value, label := "") {
        if value
            throw AssertionError(Assert.Msg(label, "expected falsy but got {}", Assert.Repr(value)), -1)
    }

    static Contains(haystack, needle, label := "") {
        if !InStr(haystack, needle)
            throw AssertionError(Assert.Msg(label, "expected {} to contain {}", Assert.Repr(haystack), Assert.Repr(needle)), -1)
    }

    static Matches(text, pattern, label := "") {
        if !RegExMatch(text, pattern)
            throw AssertionError(Assert.Msg(label, "expected {} to match /{}/", Assert.Repr(text), pattern), -1)
    }

    static Is(value, expectedType, label := "") {
        if !(value is expectedType)
            throw AssertionError(Assert.Msg(label, "expected {} but got {}", expectedType.Prototype.__Class, Type(value)), -1)
    }

    ; Runs fn and expects it to throw. Optional exception class and message
    ; substring narrow the expectation. Returns the caught error.
    static Throws(fn, expectedType := "", messagePart := "", label := "") {
        try
            fn()
        catch Any as err {
            if expectedType && !(err is expectedType)
                throw AssertionError(Assert.Msg(label, "expected {} but {} was thrown: {}", expectedType.Prototype.__Class, Type(err), Assert.ErrorText(err)), -1)
            if messagePart && !InStr(Assert.ErrorText(err), messagePart)
                throw AssertionError(Assert.Msg(label, "expected error text to contain {} but got {}", Assert.Repr(messagePart), Assert.Repr(Assert.ErrorText(err))), -1)
            return err
        }
        throw AssertionError(Assert.Msg(label, "expected an exception but none was thrown"), -1)
    }

    static Fail(message := "assertion failed") {
        throw AssertionError(message, -1)
    }

    ; --- helpers -------------------------------------------------------------

    static Same(a, b) {
        if IsObject(a) || IsObject(b)
            return a == b
        if IsNumber(a) && IsNumber(b)
            return a = b
        return a == b   ; case-sensitive string comparison
    }

    static Repr(value) {
        if value is String
            return '"' StrReplace(StrReplace(value, "`n", "``n"), "`r", "``r") '"'
        if IsObject(value)
            return "<" Type(value) ">"
        return String(value)
    }

    static Msg(label, fmt, args*) {
        text := Format(fmt, args*)
        return label != "" ? label ": " text : text
    }

    static ErrorText(err) {
        return err is Error ? err.Message (err.Extra != "" ? " (" err.Extra ")" : "") : String(err)
    }
}

class Test {
    static cases := []
    static results := []

    ; Registers one test case. fn is called with no arguments.
    static Case(name, fn) {
        Test.cases.Push({name: name, fn: fn})
    }

    ; Runs every registered case, prints a report, writes JUnit XML when
    ; AHK_TEST_JUNIT is set, and exits with 14 if anything failed.
    static Run() {
        if !Test.cases.Length {
            Print("tests: no cases registered")
            ExitApp(14)
        }
        onActions := EnvGet("GITHUB_ACTIONS") = "true"
        passed := 0, failed := 0, errored := 0
        started := A_TickCount
        Print("tests: running {} case(s)", Test.cases.Length)
        for tc in Test.cases {
            t0 := A_TickCount
            result := {name: tc.name, status: "pass", message: "", file: "", line: 0, ms: 0}
            try
                tc.fn.Call()
            catch AssertionError as err {
                result.status := "fail", result.message := err.Message
                result.file := err.File, result.line := err.Line
            } catch Any as err {
                result.status := "error"
                result.message := Type(err) ": " Assert.ErrorText(err)
                if err is Error
                    result.file := err.File, result.line := err.Line
            }
            result.ms := A_TickCount - t0
            Test.results.Push(result)
            switch result.status {
                case "pass":
                    passed += 1
                    Print("  [PASS] {}", result.name)
                case "fail":
                    failed += 1
                    Print("  [FAIL] {} -- {}  ({}:{})", result.name, result.message, result.file, result.line)
                default:
                    errored += 1
                    Print("  [ERROR] {} -- {}  ({}:{})", result.name, result.message, result.file, result.line)
            }
            if onActions && result.status != "pass"
                Print("::error file={},line={},title={}::{}", Test.RelPath(result.file), result.line, result.name, result.message)
        }
        Print("")
        Print("tests: {} passed, {} failed, {} errors ({} ms)", passed, failed, errored, A_TickCount - started)
        junit := EnvGet("AHK_TEST_JUNIT")
        if junit != ""
            Test.WriteJUnit(junit, passed, failed, errored, A_TickCount - started)
        if failed || errored
            ExitApp(14)
    }

    static RelPath(path) {
        root := EnvGet("GITHUB_WORKSPACE")
        if root != "" && InStr(path, root) = 1
            return StrReplace(SubStr(path, StrLen(root) + 2), "\", "/")
        return path
    }

    static WriteJUnit(path, passed, failed, errored, totalMs) {
        xml := '<?xml version="1.0" encoding="UTF-8"?>`n'
        xml .= Format('<testsuite name="{}" tests="{}" failures="{}" errors="{}" time="{:.3f}">`n',
            Test.Xml(A_ScriptName), Test.results.Length, failed, errored, totalMs / 1000)
        for r in Test.results {
            xml .= Format('  <testcase name="{}" classname="{}" time="{:.3f}"', Test.Xml(r.name), Test.Xml(A_ScriptName), r.ms / 1000)
            if r.status = "pass" {
                xml .= " />`n"
                continue
            }
            tag := r.status = "fail" ? "failure" : "error"
            xml .= Format('>`n    <{} message="{}">{}:{}</{}>`n  </testcase>`n',
                tag, Test.Xml(r.message), Test.Xml(r.file), r.line, tag)
        }
        xml .= "</testsuite>`n"
        f := FileOpen(path, "w", "UTF-8-RAW")
        f.Write(xml)
        f.Close()
    }

    static Xml(text) {
        text := StrReplace(String(text), "&", "&amp;")
        text := StrReplace(text, "<", "&lt;")
        text := StrReplace(text, ">", "&gt;")
        return StrReplace(text, '"', "&quot;")
    }
}
