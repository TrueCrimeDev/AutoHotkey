; Native JSON class: parse, stringify, ordering and error reporting.

Test.Case("JSON.Parse keeps object key order and types", ParseKeepsOrder)
ParseKeepsOrder() {
    obj := JSON.Parse('{"b": 1, "a": [true, null, "x"], "c": {"d": 2.5}}')
    Assert.Eq(Type(obj), "JSON.Object")
    keys := ""
    for k in obj.Keys
        keys .= k
    Assert.Eq(keys, "bac", "document order")
    Assert.Eq(obj["a"][1], 1, "true -> 1")
    Assert.Eq(obj["a"][2], "", "null -> empty")
    Assert.Eq(obj["c"]["d"], 2.5)
}

Test.Case("JSON round-trips a config byte-exact", () => (
    Assert.Eq(JSON.Stringify(JSON.Parse('{"on":true,"off":false,"n":null,"list":[1,2]}')),
              '{"on":true,"off":false,"n":null,"list":[1,2]}')
))

Test.Case("JSON.Stringify indents with Space", () => (
    Assert.Eq(JSON.Stringify(JSON.Parse('{"a":[1]}'), , 2), '{`n  "a": [`n    1`n  ]`n}')
))

Test.Case("JSON.Parse reports position on malformed input", ParseError)
ParseError() {
    err := Assert.Throws(() => JSON.Parse('{"a": 1,}'), JSONError)
    Assert.True(err.Line >= 1, "Line")
}

Test.Case("JSON.ParseAt walks NDJSON", ParseAtStream)
ParseAtStream() {
    text := '{"id":1}`n{"id":2}`n'
    pos := 1, ids := []
    while (pos <= StrLen(text)) {
        value := JSON.ParseAt(text, &pos)
        ids.Push(value["id"])
    }
    Assert.Eq(ids.Length, 2)
    Assert.Eq(ids[2], 2)
}

Test.Case("JSON scalar policy is independent of native value representation", ScalarPolicy)
ScalarPolicy() {
    for native in [false, true] {
        opts := {AllowTopLevelScalar: false, Booleans: native ? "native" : "integer", Null: native ? "native" : "empty"}
        for text in ["true", "false", "null", "123", '"text"'] {
            Assert.False(JSON.Validate(text, opts).Valid, text " validation")
            Assert.Throws(ParseDocumentWithOptions.Bind(text, opts), JSONError, , text " parse")
            Assert.Throws(ParseOneWithOptions.Bind(text, opts), JSONError, , text " stream")
        }
        for text in ['{"on":true}', '[false,null]'] {
            Assert.True(JSON.Validate(text, opts).Valid, text " validation")
            Assert.Eq(JSON.Stringify(JSON.Parse(text, opts)), text)
            Assert.Eq(JSON.Stringify(ParseOneWithOptions(text, opts)), text)
        }
    }
}

ParseOneWithOptions(text, opts) {
    pos := 1
    return JSON.ParseAt(text, &pos, opts)
}

ParseDocumentWithOptions(text, opts) => JSON.Parse(text, opts)

Test.Case("JSON.Object deletes return values and remains reusable after Clear", ContainerMutations)
ContainerMutations() {
    obj := JSON.Parse("{}")
    Loop 16
        obj["key" A_Index] := "value" A_Index
    Assert.Eq(obj.Delete("key8"), "value8")
    Assert.Eq(obj.Count, 15)
    Assert.Eq(obj["key9"], "value9")
    obj.Clear()
    Assert.Eq(obj.Count, 0)
    Assert.False(obj.Has("key9"))
    obj["next"] := 7
    Assert.Eq(JSON.Stringify(obj), '{"next":7}')
}
