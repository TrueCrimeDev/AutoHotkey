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
; Mutations preserve source types on untouched items.
mutated := JSON.Parse('[true,false]')
mutated.Push(1)
Assert.eq(JSON.Stringify(mutated), "[true,false,1]", "json.array.mutated.preserves.tags")

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

; ---- embedded NUL is data, not a string terminator -------------------------
; The length came from _tcslen once, so a NUL truncated the input and silently
; hid everything after it (found by the JSONTestSuite case n_multidigit_number_then_00).
Assert.throws(() => JSON.Parse("123" Chr(0)), "json.nul.trailing", "TrailingContent")
Assert.throws(() => JSON.Parse("123" Chr(0) "xyz"), "json.nul.hides.garbage", "TrailingContent")
Assert.throws(() => JSON.Parse("[1," Chr(0) "2]"), "json.nul.inside", "UnexpectedChar")

; ---- options plumbing fails loudly instead of silently ---------------------
; A Map's items are not own properties, so it used to read as an empty option
; set -- every option the caller asked for silently ignored.
Assert.throws(() => JSON.Parse('{"a":1}', Map("Container", "Map")), "json.opt.map.rejected", "object literal")
Assert.throws(() => JSON.Parse('{"a":1}', {Container:"Map"}, {MaxDepth:5}), "json.opt.duplicate.rejected", "More than one")
; Options are accepted from either trailing slot, and a callable is left alone
; so claiming the Reviver/Replacer slot later cannot change a working call.
Assert.eq(Type(JSON.Parse('{"a":1}', {Container:"Map"})), "Map", "json.opt.slot2")
Assert.eq(Type(JSON.Parse('{"a":1}', , {Container:"Map"})), "Map", "json.opt.slot3")
Assert.eq(JSON.Stringify(JSON.Parse('{"a":1}', (v) => v)), '{"a":1}', "json.opt.callable.ignored")
; Stringify used to swallow an options object passed in the Space slot.
Assert.eq(JSON.Stringify(JSON.Parse('{"u":"' Chr(233) '"}'), , {EnsureAscii:true})
    , '{"u":"' Chr(92) 'u00e9"}' , "json.opt.space.slot.is.options")
Assert.eq(JSON.Parse(1700000000), 1700000000, "json.numeric.arg.still.parses")

; ---- plain object literals serialize ---------------------------------------
Assert.eq(JSON.Stringify({a: 1, b: "x"}), '{"a":1,"b":"x"}', "json.dump.object.literal")
Assert.eq(JSON.Stringify({outer: {inner: [1, 2]}}), '{"outer":{"inner":[1,2]}}', "json.dump.object.nested")
; A dynamic property is skipped: producing its value means invoking script,
; which serializing a value must never do.
dynObj := {}
dynObj.DefineProp("dyn", {Get: (s) => 42})
dynObj.plain := 7
Assert.eq(JSON.Stringify(dynObj), '{"plain":7}', "json.dump.object.skips.dynamic")
selfRef := {}
selfRef.self := selfRef
Assert.throws(() => JSON.Stringify(selfRef), "json.dump.object.cycle", "CircularReference")

; ---- errors are catchable and carry position -------------------------------
; JSONError derives from ValueError, so code already catching ValueError works.
try {
    JSON.Parse("{")
} catch as e {
    Assert.eq(Type(e), "JSONError", "json.err.type")
    Assert.truthy(e is ValueError, "json.err.is.valueerror")
}
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
Assert.throws(() => JSON.Stringify(Buffer(4)), "json.err.unsupported.buffer", "UnsupportedType")
Assert.eq(JSON.Stringify({}), "{}", "json.dump.empty.literal")

; ---- ParseAt: one value at a time for NDJSON / streaming ------------------
JsonStream(text) {
    out := [], pos := 1
    while (pos <= StrLen(text))
        out.Push(JSON.ParseAt(text, &pos))
    return out
}
; NDJSON: newline-delimited, the shape of streamed JSON-RPC and log feeds.
ndj := JsonStream('{"id":1}' Chr(10) '{"id":2}' Chr(10) '{"id":3}' Chr(10))
Assert.eq(ndj.Length, 3, "json.parseat.ndjson.count")
Assert.eq(ndj[2]["id"], 2, "json.parseat.ndjson.value")
; Concatenated with no delimiter at all -- whole-doc Parse cannot do this.
concat := JsonStream('{"a":1}[2,3]"s"42')
Assert.eq(concat.Length, 4, "json.parseat.concat.count")
Assert.eq(JSON.Stringify(concat[2]), "[2,3]", "json.parseat.concat.mixed")
Assert.eq(concat[4], 42, "json.parseat.concat.scalar")
; Falsy records must each count -- the reason the loop guards on Pos, not truth.
falsy := JsonStream('0' Chr(10) 'false' Chr(10) 'null' Chr(10) '""' Chr(10) '5')
Assert.eq(falsy.Length, 5, "json.parseat.falsy.count")
Assert.eq(falsy[1], 0, "json.parseat.falsy.zero")
Assert.eq(falsy[3], "", "json.parseat.falsy.null")
; Leading/blank whitespace between and around records is skipped.
Assert.eq(JsonStream(Chr(10) Chr(10) "  " '{"a":1}' Chr(10) "  " '{"b":2}  ' Chr(10)).Length, 2, "json.parseat.blanklines")
; Pos advances past each value and parks one past the end.
p := 1
JSON.ParseAt('{"a":1}  rest', &p)
; Pos parks on the next VALUE (the 'r' at index 10), trailing whitespace skipped,
; so the following call needs no cleanup of its own.
Assert.eq(p, 10, "json.parseat.pos.advance")
; A mid-stream syntax error throws JSONError and does not run away.
threw := false
try {
    p2 := 1
    loop 10
        if (p2 <= StrLen('{"ok":1}' Chr(10) '{oops}'))
            JSON.ParseAt('{"ok":1}' Chr(10) '{oops}', &p2)
} catch as e
    threw := e is ValueError
Assert.truthy(threw, "json.parseat.error.catchable")
; Per-call options are honored (native booleans round-trip here too).
pn := 1
Assert.eq(JSON.Stringify(JSON.ParseAt('[true,null]', &pn, {Booleans:"native", Null:"native"}))
    , "[true,null]", "json.parseat.options")

; ---- Container:"Map" is the plain-types mode: plain Map AND plain Array -------
m := JSON.Parse('{"o":{"t":true},"arr":[true,null]}', {Container:"Map"})
Assert.eq(Type(m), "Map", "json.map.object.type")
Assert.eq(Type(m["arr"]), "Array", "json.map.array.type")          ; plain Array, not JSON.Array
; No tags in Map mode, so keywords collapse to 1/0/"" on the way out.
Assert.eq(JSON.Stringify(m), '{"arr":[1,""],"o":{"t":1}}', "json.map.no.tags")
; Default (JSON.Object) mode still round-trips array keywords exactly.
Assert.eq(JSON.Stringify(JSON.Parse('{"arr":[true,null]}')), '{"arr":[true,null]}', "json.default.array.roundtrip")

; ---- JSON.Validate: verdict without materializing, never throws -------------
vg := JSON.Validate('{"a":[1,2],"b":true}')
Assert.truthy(vg.Valid, "json.validate.good")
Assert.eq(vg.Code, "", "json.validate.good.nocode")
vb := JSON.Validate('{"a":1} trailing')
Assert.falsy(vb.Valid, "json.validate.bad")
Assert.eq(vb.Code, "TrailingContent", "json.validate.bad.code")
Assert.truthy(vb.Pos > 0 && vb.Line >= 1 && vb.Col >= 1, "json.validate.position")
Assert.falsy(JSON.Validate('{"a":').Valid, "json.validate.truncated")
Assert.falsy(JSON.Validate('[1,2,]').Valid, "json.validate.trailingcomma.strict")
Assert.truthy(JSON.Validate('[1,2,]', {AllowTrailingCommas:true}).Valid, "json.validate.trailingcomma.opt")
; Validate must agree with Parse on the whole JSONTestSuite corpus, or one has
; drifted from the other. This is the guard that lets them share one grammar.
vChecked := 0, vDisagree := 0
Loop Files, A_ScriptDir "\..\fixtures\jsonsuite\*.json" {
    k := SubStr(A_LoopFileName, 1, 1)
    if (k = "i")
        continue
    txt := ""
    try txt := FileRead(A_LoopFileFullPath, "UTF-8")
    pOk := true
    try JSON.Parse(txt)
    catch
        pOk := false
    if (pOk != (JSON.Validate(txt).Valid ? true : false))
        vDisagree++
    vChecked++
}
Assert.eq(vDisagree, 0, "json.validate.agrees.with.parse")
Assert.truthy(vChecked >= 283, "json.validate.corpus.covered")

; ---- Buffer parse: raw bytes, BOM-sniffed, invalid encoding is an error -----
MkUtf8Buf(str) {
    b := Buffer(StrPut(str, "UTF-8") - 1)
    StrPut(str, b, "UTF-8")
    return b
}
bo := JSON.Parse(MkUtf8Buf('{"from":"buffer","n":42}'))
Assert.eq(bo["from"], "buffer", "json.buffer.parse")
Assert.eq(bo["n"], 42, "json.buffer.parse.num")
; Invalid UTF-8 in a Buffer is a real error, not a silent U+FFFD substitution --
; the whole reason a byte path exists. (FileRead would have repaired it first.)
badBuf := Buffer(3)
NumPut("UChar", 0x22, "UChar", 0xFF, "UChar", 0x22, badBuf)   ; "  <FF>  " inside quotes
threwEnc := false
try JSON.Parse(badBuf)
catch as e
    threwEnc := InStr(e.Message, "not valid")
Assert.truthy(threwEnc, "json.buffer.invalid.utf8.errors")

; ---- ParseFile: read+parse a file's bytes directly -------------------------
jfTmp := A_Temp "\qa_json_" A_TickCount ".json"
jf := FileOpen(jfTmp, "w", "UTF-8")
jf.Write('{"file":true,"list":[1,2,3]}')
jf.Close()
fo := JSON.ParseFile(jfTmp)
Assert.eq(fo["file"], 1, "json.parsefile.value")
Assert.eq(fo["list"].Length, 3, "json.parsefile.array")
FileDelete(jfTmp)
threwMissing := false
try JSON.ParseFile(A_Temp "\qa_json_absent_" A_TickCount ".json")
catch
    threwMissing := true
Assert.truthy(threwMissing, "json.parsefile.missing.throws")

; ---- review fixes: Validate/Parse must agree under non-default options too ---
; The corpus agreement check runs default options; these pin the option branches.
JsonAgree(txt, opt) {
    p := true
    try JSON.Parse(txt, opt)
    catch
        p := false
    return p = (JSON.Validate(txt, opt).Valid ? true : false)
}
; AllowTopLevelScalar:false -- Validate used to accept scalars Parse rejects.
for badScalar in ["42", '"s"', "true", "null", "3.14"]
    Assert.truthy(JsonAgree(badScalar, {AllowTopLevelScalar:false}), "json.validate.notoplevel.agree." badScalar)
Assert.falsy(JSON.Validate("42", {AllowTopLevelScalar:false}).Valid, "json.validate.notoplevel.rejects")
Assert.truthy(JSON.Validate("[1]", {AllowTopLevelScalar:false}).Valid, "json.validate.notoplevel.array.ok")

; UTF-16 with an odd byte count is malformed, not silently truncated.
oddBuf := Buffer(5)
NumPut("UChar", 0xFF, "UChar", 0xFE, "UChar", 0x41, "UChar", 0x00, "UChar", 0xAA, oddBuf)  ; BOM "A" + stray
threwOdd := false
try JSON.Parse(oddBuf)
catch as e
    threwOdd := InStr(e.Message, "odd number")
Assert.truthy(threwOdd, "json.buffer.utf16.odd.errors")
evenBuf := Buffer(8)
NumPut("UChar", 0xFF, "UChar", 0xFE, "UChar", 0x5B, "UChar", 0x00, "UChar", 0x31, "UChar", 0x00, "UChar", 0x5D, "UChar", 0x00, evenBuf)
Assert.eq(JSON.Stringify(JSON.Parse(evenBuf)), "[1]", "json.buffer.utf16le.decodes")

; Validate accepts a Buffer (Parse does), and reports bad encoding as Valid=0.
Assert.truthy(JSON.Validate(MkUtf8Buf('[1,2,3]')).Valid, "json.validate.buffer")
badEncBuf := Buffer(3)
NumPut("UChar", 0x22, "UChar", 0xFF, "UChar", 0x22, badEncBuf)
vbe := JSON.Validate(badEncBuf)
Assert.falsy(vbe.Valid, "json.validate.buffer.badenc")
Assert.eq(vbe.Code, "BadEncoding", "json.validate.buffer.badenc.code")

; Unknown Encoding names error rather than silently decoding as UTF-8; CPnnn works.
cpBuf := Buffer(4)
NumPut("UChar", 0x22, "UChar", 0x93, "UChar", 0x94, "UChar", 0x22, cpBuf)  ; CP1252 curly quotes
Assert.eq(JSON.Parse(cpBuf, {Encoding:"CP1252"}), Chr(0x201C) Chr(0x201D), "json.encoding.cp1252")
threwEnc := false
try JSON.Parse(MkUtf8Buf('{}'), {Encoding:"NotAnEncoding"})
catch as e
    threwEnc := InStr(e.Message, "encoding")
Assert.truthy(threwEnc, "json.encoding.unknown.errors")

Assert.Summary()
