#Requires AutoHotkey v2.1-alpha.30
#Include ..\mcp.ahk
/*
test_json.ahk — round-trip and fixture tests for Json.ahk.
Run:  AutoHotkey64.exe test_json.ahk      (exit 0 = all pass, 1 = failure)
*/

global gFails := 0
global gRun := 0

Check(label, got, want) {
    global gFails, gRun
    gRun++
    if (got == want) {
        Print(Format("ok   {}", label))
    } else {
        gFails++
        Print(Format("FAIL {}", label))
        Print("  want: " want)
        Print("  got:  " got)
    }
}

; --- Stringify fixtures ---
Check("str.empty-obj",  Json.Stringify(Map()),       "{}")
Check("str.empty-arr",  Json.Stringify([]),          "[]")
Check("str.int",        Json.Stringify(42),          "42")
Check("str.neg",        Json.Stringify(-7),          "-7")
Check("str.string",     Json.Stringify("hi"),        '"hi"')
Check("str.bool-true",  Json.Stringify(Json.True),   "true")
Check("str.bool-false", Json.Stringify(Json.False),  "false")
Check("str.null",       Json.Stringify(Json.Null),   "null")
Check("str.array",      Json.Stringify([1, 2, 3]),   "[1,2,3]")
Check("str.escape",     Json.Stringify('a"b\c`nd'),  '"a\"b\\c\nd"')
Check("str.tab",        Json.Stringify("`t"),        '"\t"')
; control char U+0001 must escape to  (expected value built via Format to
; avoid putting a raw control byte in this source file)
Check("str.ctrl",       Json.Stringify(Chr(1)),      Format('"\u{:04x}"', 1))

; Object key order is NOT guaranteed (AHK Map is unordered) — verify by
; re-parsing rather than matching a literal string.
obj := Map()
obj["name"] := "Foo"
obj["line"] := 3
obj["ok"]   := Json.True
rt := Json.Parse(Json.Stringify(obj))
Check("str.object.name", rt["name"],                          "Foo")
Check("str.object.line", rt["line"],                          3)
Check("str.object.ok",   rt["ok"] == Json.True ? "T" : "F",   "T")

; --- Parse fixtures ---
Check("parse.int",      Json.Parse("42"),                             42)
Check("parse.neg",      Json.Parse("-7"),                             -7)
Check("parse.float",    Json.Parse("1.5"),                            1.5)
Check("parse.string",   Json.Parse('"hi"'),                           "hi")
Check("parse.esc",      Json.Parse('"a\"b\\c\nd"'),                    'a"b\c`nd')
Check("parse.unicode",  Json.Parse('"A"'),                       "A")
Check("parse.true",     Json.Parse("true") == Json.True ? "T" : "F",  "T")
Check("parse.false",    Json.Parse("false") == Json.False ? "T" : "F","T")
Check("parse.null",     Json.Parse("null") == Json.Null ? "T" : "F",  "T")

arr := Json.Parse("[1, 2, 3]")
Check("parse.arr.len",  arr.Length,  3)
Check("parse.arr.3",    arr[3],      3)

m := Json.Parse('{"a": 1, "b": [true, "x"], "c": {"d": null}}')
Check("parse.obj.a",    m["a"],                                 1)
Check("parse.obj.b1",   m["b"][1] == Json.True ? "T" : "F",     "T")
Check("parse.obj.b2",   m["b"][2],                              "x")
Check("parse.obj.cd",   m["c"]["d"] == Json.Null ? "T" : "F",   "T")

; --- Round trip (structure preserved; key order may differ) ---
src := '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"x","arguments":{"file":"a.ahk","line":10}}}'
r := Json.Parse(src)
Check("rt.jsonrpc", r["jsonrpc"],                       "2.0")
Check("rt.id",      r["id"],                            1)
Check("rt.method",  r["method"],                        "tools/call")
Check("rt.name",    r["params"]["name"],                "x")
Check("rt.file",    r["params"]["arguments"]["file"],   "a.ahk")
Check("rt.line",    r["params"]["arguments"]["line"],   10)
; re-parse of the re-serialized form must be equivalent
r2 := Json.Parse(Json.Stringify(r))
Check("rt.reparse", r2["params"]["arguments"]["line"],  10)

; --- Parse errors throw ---
threw := false
try Json.Parse("{bad")
catch
    threw := true
Check("parse.error",    threw ? "T" : "F",   "T")

Print("")
Print(Format("{}/{} passed, {} failed", gRun - gFails, gRun, gFails))
ExitApp(gFails > 0 ? 1 : 0)
