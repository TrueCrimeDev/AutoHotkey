#Requires AutoHotkey v2.0

; Test Script for RegExResult Property Descriptor

; Import the necessary module or source file
#Include "..\\..\\notes\\property-descriptor\\EXAMPLE_PropertyDescriptorBracketNotation.ahk"

; Test suite for RegExResult class
class RegExResultTest {
    static Test() {
        result := RegExResult(
            "FullMatch",
            ["Group1", "Group2", "Group3"],
            [1, 10, 15]
        )
        
        ; Test total length count
        totalLen := result.Len
        if (totalLen != 4)
            throw Error("Test failed: Expected 4 total length, got " totalLen)
        
        ; Test full match length
        fullMatchLen := result.Len[0]
        if (fullMatchLen != 9)
            throw Error("Test failed: Expected 9 for full match length, got " fullMatchLen)
        
        ; Test specific group length
        group1Len := result.Len[1]
        if (group1Len != 6)
            throw Error("Test failed: Expected 6 for Group1 length, got " group1Len)
        
        ; Test default position
        defaultPos := result.Pos
        if (defaultPos != 1)
            throw Error("Test failed: Expected 1 for default position, got " defaultPos)
        
        ; Test first group position
        firstGroupPos := result.Pos[1]
        if (firstGroupPos != 1)
            throw Error("Test failed: Expected 1 for first group position, got " firstGroupPos)
        
        MsgBox "RegExResult Property Descriptor Test Passed!"
    }
}

; Run the test
RegExResultTest.Test()