#Requires AutoHotkey v2.1-alpha.30
; test_json.ahk -- the native JSON class (source/json.cpp).
;
; Pins the behaviour that distinguishes this from the script-level libraries it
; replaces, verified against 2.1-alpha.30+Console:
;   * document order survives parse -> modify -> stringify (Map/Object sort);
;   * true/false/null reach script as 1/0/"" yet re-emit as the keywords, via
;     the provenance tag the container keeps beside each value;
;   * keys are case-SENSITIVE ("a" and "A" are two keys; an Object merges them);
;   * Int64 extremes and exponent forms survive exactly;
;   * malformed input throws a catchable error carrying line/col/pos/code, and
;     depth and cycles throw rather than crashing the host script.
#Include ..\Assert.ahk

; ---- type identity ---------------------------------------------------------
Assert.eq(Type(JSON), "Class", "json.class")
Assert.eq(Type(JSON.Parse("{}")), "JSON.Object", "json.parse.type")
Assert.eq(Type(JSON.Parse("[]")), "JSON.Array", "json.parse.array.type")
Assert.truthy(JSON.Parse("[]") is Array, "json.parse.array.is.array")

; ---- scalars and containers ------------------------------------------------
o := JSON.Parse('{"s":"x","i":2,"f":3.5,"t":true,"f2":false,"n":null,"a":[1,2],"o":{"k":1}}')
Assert.eq(o["s"], "x", "json.string")
Assert.eq(o["i"], 2, "json.int")
Assert.eq(Type(o["i"]), "Integer", "json.int.type")
Assert.eq(o["f"], 3.5, "json.float")
Assert.eq(Type(o["f"]), "Float", "json.float.type")
Assert.eq(o["a"][2], 2, "json.array.item")
Assert.eq(o["o"]["k"], 1, "json.nested")
Assert.eq(o.Count, 8, "json.count")

; true/false/null are handed over as plain values, so the natural test works.
Assert.eq(o["t"], 1, "json.true.value")
Assert.eq(o["f2"], 0, "json.false.value")
Assert.eq(o["n"], "", "json.null.value")
Assert.truthy(o["t"], "json.true.truthy")
Assert.falsy(o["f2"], "json.false.falsy")
Assert.falsy(o["n"], "json.null.falsy")

; ---- the differentiators ---------------------------------------------------
; Round-trip is byte-exact even though script saw 1/0/"".
src := '{"z":1,"a":true,"m":null,"b":false}'
Assert.eq(JSON.Stringify(JSON.Parse(src)), src, "json.roundtrip.exact")

; Document order survives an edit -- a Map would come back alphabetised.
cfg := JSON.Parse('{"name":"x","version":2,"debug":false}')
cfg["version"] := 3
Assert.eq(JSON.Stringify(cfg), '{"name":"x","version":3,"debug":false}', "json.order.preserved")
Assert.eq(cfg.Keys[1] "," cfg.Keys[3], "name,debug", "json.keys.order")

; Case-sensitive keys: an AHK Object would merge these into one.
Assert.eq(JSON.Stringify(JSON.Parse('{"a":1,"A":2}')), '{"a":1,"A":2}', "json.keys.casesensitive")

; Int64 extremes exact (thqby wraps the positive bound to a negative number).
Assert.eq(JSON.Stringify(JSON.Parse('[9223372036854775807,-9223372036854775808]'))
    , "[9223372036854775807,-9223372036854775808]", "json.int64.exact")

; Exponent forms parse at all (thqby's regex rejects unsigned/uppercase ones).
Assert.eq(JSON.Parse('[1e2,1E2,1e+2,1e-2]')[1], 100.0, "json.exp.unsigned")
Assert.eq(JSON.Parse('[1e2,1E2,1e+2,1e-2]')[2], 100.0, "json.exp.uppercase")
Assert.eq(JSON.Parse('[1e-2]')[1], 0.01, "json.exp.negative")

; Floats keep their exact value rather than being regex-rounded.
Assert.eq(JSON.Stringify(JSON.Parse('[0.1,3.141592653589793]')), "[0.1,3.141592653589793]", "json.float.exact")

; ---- arrays carry the same provenance tags ---------------------------------
Assert.eq(JSON.Stringify(JSON.Parse('[1,true,false,null,"s"]')), '[1,true,false,null,"s"]', "json.array.roundtrip")
Assert.eq(JSON.Stringify(JSON.Parse('{"f":[true,null],"g":1}')), '{"f":[true,null],"g":1}', "json.array.nested.roundtrip")
arr := JSON.Parse('[true,false]')
Assert.eq(Type(arr), "JSON.Array", "json.array.type")
Assert.truthy(arr is Array, "json.array.is.array")          ; must stay Array-compatible
Assert.eq(arr[1], 1, "json.array.elem.value")
Assert.truthy(arr[1], "json.array.elem.truthy")
Assert.falsy(arr[2], "json.array.elem.falsy")
Assert.eq(arr.Length, 2, "json.array.length")
; Array's own mutators know nothing about tags, so a length change drops them
; rather than risking a value being mislabelled.
mutated := JSON.Parse('[true,false]')
mutated.Push(1)
Assert.eq(JSON.Stringify(mutated), "[1,0,1]", "json.array.mutated.drops.tags")

; ---- large objects use the hash index rather than a linear scan ------------
big := "{"
loop 3000
    big .= (A_Index > 1 ? "," : "") '"k' A_Index '":' A_Index
bigObj := JSON.Parse(big "}")
Assert.eq(bigObj.Count, 3000, "json.big.count")
Assert.eq(bigObj["k1"], 1, "json.big.lookup.first")
Assert.eq(bigObj["k3000"], 3000, "json.big.lookup.last")
Assert.truthy(bigObj.Delete("k1500"), "json.big.delete")
Assert.falsy(bigObj.Has("k1500"), "json.big.deleted.gone")
Assert.eq(bigObj["k3000"], 3000, "json.big.lookup.after.delete")  ; index rebuilt
Assert.eq(bigObj.Count, 2999, "json.big.count.after.delete")

; ---- strings and escapes ---------------------------------------------------
Assert.eq(JSON.Parse('"Aé"'), "Aé", "json.escape.u")
Assert.eq(JSON.Parse('"a\/b"'), "a/b", "json.escape.slash")       ; thqby leaves this as a\/b
Assert.eq(JSON.Parse('"\b\f\n\r\t"'), Chr(8) Chr(12) "`n`r`t", "json.escape.controls")
Assert.eq(JSON.Parse('"😀"'), "😀", "json.escape.surrogate.pair")
Assert.eq(StrLen(JSON.Parse('"😀"')), 2, "json.escape.surrogate.len")
; Every C0 control is escaped on output, so the result always re-parses.
Assert.eq(JSON.Stringify(Chr(1)), '"' Chr(92) 'u0001"', "json.escape.c0.always")
Assert.eq(JSON.Stringify("q`"b\s"), '"q\"b\\s"', "json.escape.quote.backslash")

; ---- top-level scalars (thqby throws on parse, cJson on dump) --------------
Assert.eq(JSON.Parse("42"), 42, "json.toplevel.number")
Assert.eq(JSON.Parse('"s"'), "s", "json.toplevel.string")
Assert.eq(JSON.Stringify("s"), '"s"', "json.toplevel.dump")

; ---- aliases and call-site compatibility -----------------------------------
Assert.eq(JSON.Dump(JSON.Load('{"a":1}')), '{"a":1}', "json.alias.loaddump")
Assert.eq(JSON.stringify(JSON.parse('{"a":1}')), '{"a":1}', "json.alias.lowercase")

; ---- pretty printing -------------------------------------------------------
Assert.eq(JSON.Stringify(JSON.Parse('{"a":1}'), , 2), "{`n  `"a`": 1`n}", "json.pretty.width")
Assert.eq(JSON.Stringify(JSON.Parse('{"a":1}'), , "`t"), "{`n`t`"a`": 1`n}", "json.pretty.string")
Assert.eq(JSON.Stringify(JSON.Parse('{"a":1}')), '{"a":1}', "json.compact.default")

; ---- options ---------------------------------------------------------------
Assert.eq(Type(JSON.Parse('{"a":1}', {Container:"Map"})), "Map", "json.opt.container.map")
Assert.eq(Type(JSON.Parse('{"a":true}', {Booleans:"native"})["a"]), "Object", "json.opt.booleans.native")
Assert.eq(JSON.Stringify(JSON.Parse('[true,false,null]', {Booleans:"native", Null:"native"}))
    , "[true,false,null]", "json.opt.native.array.roundtrip")
Assert.eq(JSON.Stringify(JSON.Parse('{/*c*/"a":1}', {AllowComments:true})), '{"a":1}', "json.opt.comments")
Assert.eq(JSON.Stringify(JSON.Parse('[1,2,]', {AllowTrailingCommas:true})), "[1,2]", "json.opt.trailingcommas")

; ---- container API ---------------------------------------------------------
j := JSON.Parse('{"x":1,"y":2}')
Assert.truthy(j.Has("x"), "json.obj.has")
Assert.falsy(j.Has("zz"), "json.obj.has.missing")
Assert.eq(j.Get("zz", "dflt"), "dflt", "json.obj.get.default")
j.Set("z", 3)
j.Delete("x")
Assert.eq(JSON.Stringify(j), '{"y":2,"z":3}', "json.obj.set.delete")
Assert.eq(JSON.Stringify(j.Clone()), '{"y":2,"z":3}', "json.obj.clone")
Assert.eq(j.Keys.Length, 2, "json.obj.keys")
Assert.eq(j.Values[1], 2, "json.obj.values")
seen := ""
for k, v in j
    seen .= k "=" v ";"
Assert.eq(seen, "y=2;z=3;", "json.obj.enum.order")

; Serialising a plain Map still works (thqby-shaped code passes Maps in).
Assert.eq(JSON.Stringify(Map("a", 1)), '{"a":1}', "json.dump.map")
Assert.eq(JSON.Stringify([1, "a"]), '[1,"a"]', "json.dump.array")

; ---- errors are catchable and carry position -------------------------------
Assert.throws(() => JSON.Parse("{"), "json.err.truncated", "UnexpectedEnd")
Assert.throws(() => JSON.Parse("[1,2}"), "json.err.mismatch", "UnexpectedChar")   ; thqby accepts this
Assert.throws(() => JSON.Parse('{"a":1} trailing'), "json.err.trailing", "TrailingContent")
Assert.throws(() => JSON.Parse('{"a":01}'), "json.err.leadingzero", "UnexpectedChar")
Assert.throws(() => JSON.Parse('{a:1}'), "json.err.unquotedkey", "quoted property name")
Assert.throws(() => JSON.Parse('["\q"]'), "json.err.badescape", "BadEscape")
Assert.throws(() => JSON.Parse('["' Chr(9) '"]'), "json.err.rawcontrol", "control character")
Assert.throws(() => JSON.Parse('{/*c*/"a":1}'), "json.err.comments.default", "UnexpectedChar")

; Position information is present and correct.
try {
    JSON.Parse('{"a":1,`n "b" 2}')
} catch as e {
    Assert.truthy(InStr(e.Message, "line 2"), "json.err.line")
    Assert.truthy(InStr(e.Message, "col "), "json.err.col")
}

; Depth and cycles throw instead of taking the host script down with an
; uncatchable native stack overflow (how the script-level libraries fail).
deep := ""
loop 400
    deep .= "["
Assert.throws(() => JSON.Parse(deep), "json.err.depth", "DepthExceeded")
Assert.truthy(JSON.Parse(SubStr(deep, 1, 200) StrReplace(SubStr(deep, 1, 200), "[", "]")) is Array
    , "json.depth.under.cap.ok")

cyc := JSON.Parse('{"a":1}')
cyc["self"] := cyc
Assert.throws(() => JSON.Stringify(cyc), "json.err.cycle", "CircularReference")

; An unsupported value names its type rather than emitting invalid JSON.
Assert.throws(() => JSON.Stringify({fn: (*) => 1}.fn), "json.err.unsupported", "UnsupportedType")

Assert.Summary()
