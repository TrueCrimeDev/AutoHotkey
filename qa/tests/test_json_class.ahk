#Requires AutoHotkey v2.1-alpha.31
; test_json_class.ahk -- the JSON class object itself: nothing can construct an
; instance of it, and JSON.True / JSON.False / JSON.Null are read-only.
;
; OLD (2.1-alpha.33+Console, f7712ec1): JSON inherited Object.Call, so JSON(),
; (Object.Call)(JSON) and a subclass's constructor each returned a plain Object
; on the JSON.Object prototype (`is JSON`, Type "JSON.Object") whose Set, Count
; and Keys read and wrote past its end: exit 11, an access violation or heap
; corruption. JSON.True := 5 replaced the singleton, so a native-mode parse no
; longer matched JSON.True. Constructing and releasing such an object is safe
; (only its JSON.Object methods are not), so the in-process asserts below stop
; there; every method call on one runs in a child via RunSnippet, where a crash
; is an assertable exit code instead of the end of this test.
#Include ..\Assert.ahk
#Include ..\Harness.ahk

class QaJsonSub extends JSON {
}

; Type of the error fn() throws, or "" when it returns normally.
CaughtType(fn) {
    try {
        fn()
    } catch as e {
        return Type(e)
    }
    return ""
}

SetPlainBase() {
    o := {}
    o.Base := JSON.Prototype
}

; --- JSON() and the generic constructor paths are refused --------------------
Assert.throws(() => JSON(), "json.class.call.throws", "JSON.Parse")
Assert.throws(() => JSON("x", 1), "json.class.call.args.throws", "JSON.Parse")
Assert.eq(CaughtType(() => JSON()), "TypeError", "json.class.call.type")
; With JSON.Call bypassed, Object.Call must still refuse the JSON.Object prototype.
Assert.eq(CaughtType(() => (Object.Call)(JSON)), "ValueError", "json.class.object.call")
Assert.eq(CaughtType(() => (Object.Call)({Prototype: JSON.Prototype})), "ValueError", "json.class.prototype.object.call")
Assert.eq(CaughtType(() => QaJsonSub()), "TypeError", "json.class.subclass.call")
Assert.eq(CaughtType(() => (Object.Call)(QaJsonSub)), "ValueError", "json.class.subclass.object.call")
; protects: a plain Object could already not be rebased onto JSON.Object.
Assert.eq(CaughtType(SetPlainBase), "ValueError", "json.class.rebase.refused")

; JSON.Object and JSON.Array are type names, not members (fork.d.ahk): calling
; them is an ordinary MethodError.
Assert.eq(CaughtType(() => JSON.Object()), "MethodError", "json.class.object.member")
Assert.eq(CaughtType(() => JSON.Array()), "MethodError", "json.class.array.member")

; A child exercises each path's result. On the old engine both return a fake
; JSON.Object and Set/Count/Keys on it crash or corrupt the heap.
r := RunSnippet('
(
paths := [() => JSON(), () => (Object.Call)(JSON)]
for p in paths {
    try {
        x := p()
    } catch as e {
        Print("refused " Type(e))
        continue
    }
    x.Set("k", 1)
    Print("count " x.Count)
    for k in x.Keys
        Print("key " k)
    x := ""
}
Print("done")
)')
Assert.eq(r.code, 0, "json.class.child.exit")
Assert.truthy(InStr(r.out, "refused TypeError") && InStr(r.out, "refused ValueError"), "json.class.child.refused")
Assert.truthy(InStr(r.out, "done") && !InStr(r.out, "count"), "json.class.child.no.instance")

; --- JSON.Prototype is still the JSON.Object prototype ----------------------
parsed := JSON.Parse('{"b":1,"a":[true,null]}')
Assert.truthy(parsed is JSON, "json.class.parsed.is.json")
Assert.truthy(parsed.Base == JSON.Prototype, "json.class.parsed.base")
Assert.eq(Type(parsed), "JSON.Object", "json.class.parsed.type")
Assert.eq(JSON.Prototype.__Class, "JSON.Object", "json.class.prototype.name")
Assert.falsy(parsed["a"] is JSON, "json.class.array.not.json")
Assert.truthy(parsed["a"] is Array, "json.class.array.is.array")
Assert.falsy({} is JSON, "json.class.plain.not.json")
Assert.falsy(JSON.Parse('{"a":1}', {Container: "Map"}) is JSON, "json.class.map.not.json")
Assert.truthy(parsed.Clone() is JSON, "json.class.clone.is.json")
; Real instances keep working, as do the static methods through a subclass.
parsed.Set("c", 2)
parsed["b"] := 3
Assert.eq(parsed.Count, 3, "json.class.parsed.count")
Assert.eq(JSON.Stringify(parsed), '{"b":3,"a":[true,null],"c":2}', "json.class.parsed.stringify")
Assert.eq(JSON.Stringify(QaJsonSub.Parse('[1,{"x":2}]')), '[1,{"x":2}]', "json.class.subclass.static")

; --- JSON.True / JSON.False / JSON.Null ---------------------------------------
native := {Booleans: "native", Null: "native"}
before := JSON.Parse('[true,false,null]', native)
Assert.truthy(before[1] == JSON.True && before[2] == JSON.False && before[3] == JSON.Null, "json.native.identity.before")
Assert.eq(JSON.Stringify(before), "[true,false,null]", "json.native.roundtrip.before")

for name in ["True", "False", "Null"] {
    Assert.truthy(JSON.HasOwnProp(name), "json.singleton.own." name)
    Assert.eq(Type(JSON.%name%), "Object", "json.singleton.type." name)
    single := JSON.%name%
    Assert.throws(() => JSON.%name% := 5, "json.singleton.readonly." name, "read-only")
    Assert.truthy(JSON.%name% == single, "json.singleton.unchanged." name)
    Assert.throws(() => QaJsonSub.%name% := 5, "json.singleton.subclass.readonly." name, "read-only")
}
Assert.truthy(JSON.True != JSON.False && JSON.False != JSON.Null && JSON.True != JSON.Null, "json.singleton.distinct")

; The attempted assignments above must not have broken native-mode identity.
after := JSON.Parse('{"t":true,"f":false,"n":null,"a":[true,false,null]}', native)
Assert.truthy(after["t"] == JSON.True && after["f"] == JSON.False && after["n"] == JSON.Null, "json.native.identity.after")
Assert.truthy(after["a"][1] == JSON.True && after["a"][3] == JSON.Null, "json.native.array.identity.after")
Assert.eq(JSON.Stringify(after), '{"t":true,"f":false,"n":null,"a":[true,false,null]}', "json.native.roundtrip.after")
Assert.eq(JSON.Stringify([JSON.True, JSON.False, JSON.Null]), "[true,false,null]", "json.singleton.stringify.after")
Assert.eq(JSON.Stringify(Map("t", JSON.True)), '{"t":true}', "json.singleton.map.stringify.after")

Assert.Summary()
