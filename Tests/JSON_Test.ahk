; Test script for Native JSON Support

#Requires AutoHotkey v2.0-

if !HasProp(JSON, "Parse")
{
    MsgBox "JSON class not found! Please compile AutoHotkey with the JSON patch."
    ExitApp
}

RunTests()

RunTests() {
    passed := 0
    failed := 0
    
    Assert(actual, expected, name) {
        if (actual == expected) {
            ; FileAppend "PASS: " name "`n", "*"
            passed++
        } else {
            FileAppend "FAIL: " name " - Expected '" expected "', got '" actual "'`n", "*"
            failed++
        }
    }

    AssertJSON(jsonStr, expectedStr, name) {
        try {
            obj := JSON.Parse(jsonStr)
            str := JSON.Stringify(obj)
            ; Note: Stringify order for Maps is undefined/implementation dependent.
            ; For simple cases it might match.
            ; For robust testing, we should compare objects.
            Assert(str, expectedStr, name)
        } catch as e {
            FileAppend "FAIL: " name " - Exception: " e.Message "`n", "*"
            failed++
        }
    }

    FileAppend "Running JSON Tests...`n", "*"

    ; Basic Types
    Assert(JSON.Parse("true"), 1, "Parse true")
    Assert(JSON.Parse("false"), 0, "Parse false")
    Assert(JSON.Parse("null"), "", "Parse null")
    Assert(JSON.Parse("123"), 123, "Parse integer")
    Assert(JSON.Parse("12.34"), 12.34, "Parse float")
    Assert(JSON.Parse('"hello"'), "hello", "Parse string")
    Assert(JSON.Parse('"escaped \"quote\""'), 'escaped "quote"', "Parse escaped string")

    ; Arrays
    arr := JSON.Parse("[1, 2, 3]")
    Assert(arr.Length, 3, "Array Length")
    Assert(arr[1], 1, "Array[1]")
    Assert(arr[2], 2, "Array[2]")
    Assert(arr[3], 3, "Array[3]")
    
    str := JSON.Stringify(arr)
    Assert(str, "[1,2,3]", "Stringify Array")

    ; Objects (Map)
    obj := JSON.Parse('{"a": 1, "b": "two"}')
    Assert(obj.Count, 2, "Map Count")
    Assert(obj["a"], 1, "Map['a']")
    Assert(obj["b"], "two", "Map['b']")

    ; Nested
    nested := JSON.Parse('{"arr": [1, 2], "obj": {"x": 10}}')
    Assert(nested["arr"][2], 2, "Nested Array")
    Assert(nested["obj"]["x"], 10, "Nested Object")

    ; Stringify Complex
    complex := Map("key", "value", "list", [1, 2])
    jsonStr := JSON.Stringify(complex)
    ; Order isn't guaranteed for Map, but let's check if it contains parts
    if (InStr(jsonStr, '"key":"value"') && InStr(jsonStr, '"list":[1,2]'))
        passed++
    else {
        FileAppend "FAIL: Stringify Complex - Got " jsonStr "`n", "*"
        failed++
    }

    ; Error Handling
    try {
        JSON.Parse("{invalid}")
        FileAppend "FAIL: Invalid JSON should throw`n", "*"
        failed++
    } catch {
        passed++ ; Expected exception
    }

    MsgBox "Tests Completed. Passed: " passed ", Failed: " failed
}
