#Requires AutoHotkey v2.0

; Test Script for Basic Bracket Parameter Passing Property Descriptor

; Import the necessary module or source file
#Include "..\\..\\notes\\property-descriptor\\EXAMPLE_PropertyDescriptorBracketNotation.ahk"

; Test suite for BasicExample class
class BasicExampleTest {
    static Test() {
        testObj := BasicExample()
        
        ; Test accessing without index
        result1 := testObj.Data
        if (result1 != "All data requested")
            throw Error("Test failed: Expected 'All data requested', got " result1)
        
        ; Test accessing with specific index
        result2 := testObj.Data[5]
        if (result2 != "Index: 5")
            throw Error("Test failed: Expected 'Index: 5', got " result2)
        
        ; Test accessing with empty brackets
        result3 := testObj.Data[]
        if (result3 != "All data requested")
            throw Error("Test failed: Expected 'All data requested', got " result3)
        
        MsgBox "BasicExample Property Descriptor Test Passed!"
    }
}

; Run the test
BasicExampleTest.Test()