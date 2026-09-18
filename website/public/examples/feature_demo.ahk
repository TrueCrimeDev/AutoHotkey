#Requires AutoHotkey v2.1-alpha.31
#EnableEval
; feature_demo.ahk -- disposable demonstration of the +Console fork's additions.
; Every section asserts; the script exits 14 on any failure so the engine's
; `test` subcommand reports the verdict.

failures := 0
checks := 0

Print("=== ClautoHotkey feature demo on {} ===", A_AhkVersion)
Print("engine: {}", A_AhkPath)
Print()

; Print / Format dispatch
Print("[1] Print formatting")
Print("    two-arg form -> {} and {}", "alpha", 31)
Print("    single-arg form keeps literal {braces}")
AssertEq(Format("x={}, y={}", 6, 7), "x=6, y=7", "Print's Format dispatch matches Format()")
; Print's own stdout bytes are asserted end-to-end in section 6, where a child
; engine's output is captured over a pipe.

; JSON round trip with boolean / null tags
Print("[2] JSON")
src := '{"name":"demo","ok":true,"off":false,"none":null,"count":3}'
doc := JSON.Parse(src)
AssertEq(Type(doc), "JSON.Object", "objects parse into the ordered JSON.Object")
AssertEq(doc["ok"], 1, "true reaches script as 1")
AssertEq(doc["off"], 0, "false reaches script as 0")
AssertEq(doc["none"], "", "null reaches script as empty string")
AssertEq(doc["count"], 3, "numbers survive")
AssertEq(JSON.Stringify(doc), src, "round trip is byte-exact: keywords and key order kept")

native := JSON.Parse('[true,false,null]', {Booleans: "native", Null: "native"})
AssertEq(Type(native[1]), "Object", "Booleans:native yields the JSON.True singleton")
AssertEq(JSON.Stringify(native), '[true,false,null]', "native singletons re-emit as keywords")
Print("    {} -> {}", src, JSON.Stringify(doc))

; Inspect of an array
Print("[3] Inspect")
sample := ["alpha", 31, 2.5]
report := Inspect(sample)
info := JSON.Parse(report)
AssertEq(info["type"], "Array", "Inspect reports the type")
AssertEq(info["length"], 3, "Inspect reports the length")
AssertEq(info["items"][1], "alpha", "Inspect inlines primitive items")
AssertEq(info["items"][2], 31, "numeric items stay numeric")
Print("    {}", report)

; Check: valid and invalid source
Print("[4] Check")
good := Check("x := 1`nPrint(x)")
AssertEq(good.Ok, 1, "valid source checks clean")
AssertEq(good.Diagnostics.Length, 0, "clean source has no diagnostics")

bad := Check("x := `nif (")
AssertEq(bad.Ok, 0, "invalid source is rejected")
Assert(bad.Diagnostics.Length >= 1, "rejected source carries at least one diagnostic")
if bad.Diagnostics.Length {
    d := bad.Diagnostics[1]
    Assert(d.Message != "", "diagnostic carries a message")
    Print("    diagnostic: line {} - {}", d.Line, d.Message)
}

; Eval, opt-in via #EnableEval
Print("[5] Eval")
AssertEq(Eval("1 + 2"), 3, "Eval evaluates an expression")
n := 21
AssertEq(Eval("n * 2"), 42, "Eval reads the caller's scope")
caught := ""
try
    Eval("1 +")
catch SyntaxError as e
    caught := e.Message
Assert(caught != "", "a malformed expression throws SyntaxError")
Print("    SyntaxError: {}", caught)

; ProcessPipe: this engine running a tiny child
Print("[6] ProcessPipe")
childScript := A_ScriptDir "\child_echo.ahk"
payload := "hello-from-harness"
pipe := ProcessPipe(A_AhkPath, ["/Headless", childScript, payload])
Assert(pipe.PID > 0, "child process started")
line1 := pipe.ReadLine(10)
line2 := pipe.ReadLine(10)
code := pipe.Wait(10)
AssertEq(line1, "echo: " payload, "child's Print(Fmt, Values*) formatted through the pipe")
AssertEq(line2, "literal {braces} kept", "child's single-arg Print kept literal braces")
AssertEq(code, 0, "child exited 0")
AssertEq(pipe.ReadStdErr(), "", "child wrote nothing to stderr")
Print("    pid {} said: {} | {} (exit {})", pipe.PID, line1, line2, code)
pipe.Close()

; Verdict
Print()
Print("{} assertions, {} failed", checks, failures)
ExitApp(failures ? 14 : 0)

Assert(condition, label) {
    global checks, failures
    checks += 1
    if condition {
        Print("    PASS  {}", label)
        return
    }
    failures += 1
    Print("    FAIL  {}", label)
}

AssertEq(actual, expected, label) {
    global checks, failures
    checks += 1
    if (actual = expected) && (Type(actual) = Type(expected) || IsNumber(expected)) {
        Print("    PASS  {}", label)
        return
    }
    failures += 1
    Print("    FAIL  {} (expected {}, got {})", label, Repr(expected), Repr(actual))
}

Repr(value) {
    if IsObject(value)
        return "<" Type(value) ">"
    return IsNumber(value) ? String(value) : "'" value "'"
}
