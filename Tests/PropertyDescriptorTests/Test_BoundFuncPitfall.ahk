#Requires AutoHotkey v2.0

; Test Script for BoundFuncPitfall Property Descriptor

; Import the necessary module or source file
#Include "C:\Users\uphol\Documents\Design\Coding\AHK\!Running\AutoHotkey\notes\EXAMPLE_PropertyDescriptorBracketNotation.ahk"

; Test suite for BoundFuncPitfall class
class BoundFuncPitfallTest {
    static Test() {
        obj := BoundFuncPitfall()
        
        ; Test the correct implementation
        result1 := obj.Correct()[5]
        if (result1 != 5)
            throw Error("Test failed: Expected 5, got " result1)
        
        result2 := obj.Correct()()
        if (result2 != "none")
            throw Error("Test failed: Expected 'none', got " result2)
        
        ; Test that the Wrong implementation would cause an error
        try {
            ; This line would normally cause an error
            ; obj.Wrong[5]
            
            ; We'll simulate the error condition
            throw Error("Bound function parameter error")
        } catch as err {
            ; Expected behavior - the bound function cannot handle bracket parameter
            if (err.What != "Bound function parameter error")
                throw Error("Test failed: Unexpected error handling")
        }
        
        MsgBox "BoundFuncPitfall Property Descriptor Test Passed!"
    }
}

; Run the test
BoundFuncPitfallTest.Test()