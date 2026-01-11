#Requires AutoHotkey v2.0

; Test Script for MultiCounter Property Descriptor

; Import the necessary module or source file
#Include "..\\..\\notes\\property-descriptor\\EXAMPLE_PropertyDescriptorBracketNotation.ahk"

; Test suite for MultiCounter class
class MultiCounterTest {
    static Test() {
        counter := MultiCounter()
        
        ; Increment multiple counters
        counter.Increment("clicks")
        counter.Increment("clicks")
        counter.Increment("views")
        
        ; Test specific counter values
        clicksCount := counter.Count["clicks"]
        if (clicksCount != 2)
            throw Error("Test failed: Expected 2 clicks, got " clicksCount)
        
        viewsCount := counter.Count["views"]
        if (viewsCount != 1)
            throw Error("Test failed: Expected 1 view, got " viewsCount)
        
        ; Test getting all counters
        allCounts := counter.Count
        if (allCounts.Count != 2)
            throw Error("Test failed: Expected 2 total counters, got " allCounts.Count)
        
        ; Verify the values in the full count map
        if (allCounts["clicks"] != 2 || allCounts["views"] != 1)
            throw Error("Test failed: Unexpected values in full count map")
        
        ; Test non-existent counter
        nonExistentCount := counter.Count["nonexistent"]
        if (nonExistentCount != 0)
            throw Error("Test failed: Expected 0 for non-existent counter, got " nonExistentCount)
        
        MsgBox "MultiCounter Property Descriptor Test Passed!"
    }
}

; Run the test
MultiCounterTest.Test()