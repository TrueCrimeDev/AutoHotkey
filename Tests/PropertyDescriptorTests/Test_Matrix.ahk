#Requires AutoHotkey v2.0

; Test Script for Matrix Property Descriptor

; Import the necessary module or source file
#Include "..\\..\\notes\\property-descriptor\\EXAMPLE_PropertyDescriptorBracketNotation.ahk"

; Test suite for Matrix class
class MatrixTest {
    static Test() {
        ; Create a 3x3 matrix
        m := Matrix(3, 3)
        
        ; Test matrix dimensions
        dims := m.Value
        if (dims.rows != 3 || dims.cols != 3)
            throw Error("Test failed: Expected 3x3 matrix, got " dims.rows "x" dims.cols)
        
        ; Set values in the matrix
        m.Value[1, 1] := 1
        m.Value[1, 2] := 2
        m.Value[2, 1] := 3
        m.Value[2, 2] := 4
        
        ; Verify set values
        if (m.Value[1, 1] != 1)
            throw Error("Test failed: Expected 1 at [1,1], got " m.Value[1, 1])
        
        if (m.Value[1, 2] != 2)
            throw Error("Test failed: Expected 2 at [1,2], got " m.Value[1, 2])
        
        if (m.Value[2, 1] != 3)
            throw Error("Test failed: Expected 3 at [2,1], got " m.Value[2, 1])
        
        if (m.Value[2, 2] != 4)
            throw Error("Test failed: Expected 4 at [2,2], got " m.Value[2, 2])
        
        ; Test out-of-bounds access
        try {
            m.Value[4, 4] ; This should throw an IndexError
            throw Error("Test failed: Should have thrown IndexError for out-of-bounds access")
        } catch as err {
            if (err.What != "IndexError")
                throw Error("Test failed: Unexpected error type for out-of-bounds access")
        }
        
        ; Test trying to set value without index
        try {
            m.Value[] := 5
            throw Error("Test failed: Should have thrown ValueError for incomplete indexing")
        } catch as err {
            if (err.What != "ValueError")
                throw Error("Test failed: Unexpected error type for incomplete indexing")
        }
        
        MsgBox "Matrix Property Descriptor Test Passed!"
    }
}

; Run the test
MatrixTest.Test()