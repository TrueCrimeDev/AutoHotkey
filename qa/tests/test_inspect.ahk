#Requires AutoHotkey v2.1-alpha.31
#Include ..\Assert.ahk
; Inspect(Value, Depth, MaxItems): structured, script-free description of live values.

I(v, d?, m?) => JSON.Parse(Inspect(v, d?, m?))
Has(arr, name) {
    for item in arr
        if item = name
            return true
    return false
}

; --- primitives ------------------------------------------------------------
r := I(42)
Assert.eq(r["type"], "Integer", "int type")
Assert.eq(r["value"], 42, "int value")
r := I(1.5)
Assert.eq(r["type"], "Float", "float type")
Assert.eq(r["value"], 1.5, "float value")
r := I("héllo`n")
Assert.eq(r["type"], "String", "string type")
Assert.eq(r["length"], 6, "string length")
Assert.eq(r["value"], "héllo`n", "string value round-trips")

; --- plain objects, depth ----------------------------------------------------
o := {a: 1, b: "x", c: {d: 2}}
r := I(o)
Assert.eq(r["type"], "Object", "plain type")
Assert.eq(r["properties"]["a"], 1, "own value")
Assert.eq(r["properties"]["c"]["type"], "Object", "nested descriptor")
Assert.eq(r["properties"]["c"]["properties"]["d"], 2, "nested value at depth 2")
r := I(o, 1)
Assert.eq(r["properties"]["c"]["truncated"], 1, "depth 1 truncates nested")
Assert.falsy(r["properties"]["c"].Has("properties"), "truncated node has no properties")
r := I(o, 0)
Assert.eq(r["truncated"], 1, "depth 0 truncates the root")

; --- arrays, maps, MaxItems ----------------------------------------------------
r := I([1, "two", [3]])
Assert.eq(r["type"], "Array", "array type")
Assert.eq(r["length"], 3, "array length")
Assert.eq(r["items"][2], "two", "array item")
Assert.eq(r["items"][3]["type"], "Array", "nested array descriptor")
Assert.truthy(Has(r["methods"], "Push"), "Array.Prototype methods listed")
Assert.truthy(Has(r["getters"], "Length"), "Length getter listed")
r := I([1, 2, 3, 4, 5], 2, 3)
Assert.eq(r["items"].Length, 3, "MaxItems caps items")
Assert.eq(r["truncated"], 1, "capped array is flagged")
sparse := [1, , 3]
r := I(sparse)
Assert.eq(r["items"][2], "", "sparse hole reads as null/empty")
m := Map("k", 1, 2, "v")
r := I(m)
Assert.eq(r["type"], "Map", "map type")
Assert.eq(r["count"], 2, "map count")
; Map keeps integer keys before string keys; check by key rather than position.
byKey := Map()
for pair in r["entries"]
    byKey[pair[1]] := pair[2]
Assert.eq(byKey["k"], 1, "string map key")
Assert.eq(byKey[2], "v", "integer map key survives as an integer")
Assert.eq(byKey.Count, 2, "both entries present")

; --- classes: own values, getters, methods, statics -----------------------------
class Widget {
    count := 0
    static tag := "w"
    Text {
        get => "Save"
        set => this.count := value
    }
    Poke() {
        return 1
    }
}
w := Widget()
w.count := 3
r := I(w)
Assert.eq(r["type"], "Widget", "instance type")
Assert.eq(r["properties"]["count"], 3, "instance own value")
Assert.truthy(Has(r["getters"], "Text"), "getter listed by name, not invoked")
Assert.truthy(Has(r["setters"], "Text"), "setter listed")
Assert.truthy(Has(r["methods"], "Poke"), "method listed")
Assert.falsy(Has(r["methods"], "HasOwnProp"), "Object.Prototype members are not listed")
Assert.falsy(r["properties"].Has("Text"), "getter not evaluated into properties")
r := I(Widget)
Assert.eq(r["class"], "Widget", "class object is marked")
Assert.eq(r["properties"]["tag"], "w", "static value listed on the class")

; --- native objects: Gui control, Buffer, Func, JSON.Object ------------------------
g := Gui()
btn := g.AddButton("w200", "Save")
r := I(btn)
Assert.eq(r["type"], "Gui.Button", "native control type")
Assert.truthy(Has(r["getters"], "Text"), "native getter listed")
Assert.truthy(Has(r["methods"], "OnEvent"), "native method listed")
Assert.truthy(Has(r["methods"], "Focus"), "inherited native method listed")
g.Destroy()
r := I(Buffer(16))
Assert.eq(r["type"], "Buffer", "buffer type")
Assert.truthy(Has(r["getters"], "Size"), "buffer getter listed")
F(a, b := 1, c*) => a
r := I(F)
Assert.eq(r["type"], "Func", "func type")
Assert.eq(r["name"], "F", "func name")
Assert.eq(r["minParams"], 1, "minParams")
Assert.eq(r["variadic"], 1, "variadic")
r := I(StrLen)
Assert.eq(r["name"], "StrLen", "builtin func name")
r := I(JSON.Parse('{"z":1,"a":[true]}'))
Assert.eq(r["type"], "JSON.Object", "JSON.Object type")
Assert.eq(r["entries"][1][1], "z", "JSON.Object keeps document order")
Assert.eq(r["entries"][2][2]["type"], "JSON.Array", "nested JSON array")

; --- cycles, deep nesting, wide objects, bad args ----------------------------------
a := {}
a.self := a
r := I(a)
Assert.eq(r["properties"]["self"]["circular"], 1, "cycle reported, not followed")
deep := {}
node := deep
Loop 60 {
    node.next := {}
    node := node.next
}
Assert.noThrow(() => Inspect(deep, 1000), "depth is clamped, no crash on deep chains")
wide := {}
Loop 500
    wide.%"p" A_Index% := A_Index
r := I(wide)
Assert.eq(r["truncated"], 1, "wide object capped by default MaxItems")
r := I(wide, 2, 1000)
Assert.eq(r["properties"].Count, 500, "MaxItems raised shows all")
Assert.noThrow(() => Inspect({a: 1}, -5, -5), "negative args are clamped")
Assert.eq(JSON.Parse(Inspect([1, 2, 3], 2, 0))["items"].Length, 1, "MaxItems 0 clamps to 1")
Assert.truthy(InStr(Inspect(w, 1), '"properties"'), "text form is JSON")

Assert.Summary()
