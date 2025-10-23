#Requires AutoHotkey v2.0

; Test Script for Array-Like Property Access Property Descriptor

; Import the necessary module or source file
#Include "C:\Users\uphol\Documents\Design\Coding\AHK\!Running\AutoHotkey\notes\EXAMPLE_PropertyDescriptorBracketNotation.ahk"

; Test suite for ArrayProperty class
class ArrayPropertyTest {
    static Test() {
        testObj := ArrayProperty()
        
        ; Test single parameter (Map item access)
        result1 := testObj.SingleParam[1]
        if (result1 != "A")
            throw Error("Test failed: Expected 'A', got " result1)
        
        ; Test multi-parameter without index (full array)
        result2 := testObj.MultiParam
        if (result2.Length != 5 || !IsArray(result2))
            throw Error("Test failed: Expected full array with 5 items")
        
        ; Test multi-parameter with specific index
        result3 := testObj.MultiParam[2]
        if (result3 != 20)
            throw Error("Test failed: Expected 20, got " result3)
        
        ; Test multi-parameter with last index
        result4 := testObj.MultiParam[5]
        if (result4 != 50)
            throw Error("Test failed: Expected 50, got " result4)
        
        MsgBox "ArrayProperty Property Descriptor Test Passed!"
    }
}

; Run the test
ArrayPropertyTest.Test()

/plugin marketplace add https://github.com/rohitt/claude-plugin-suite

/plugin marketplace add rohittcodes/claude-plugin-suite