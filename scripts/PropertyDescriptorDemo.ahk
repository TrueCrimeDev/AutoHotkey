#Requires AutoHotkey v2.0

; Demonstration script for Property Descriptor bracket notation utilities
; Shows how to import the shared example module and call its helper classes.

#Include "..\\notes\\property-descriptor\\EXAMPLE_PropertyDescriptorBracketNotation.ahk"

DemoPropertyDescriptorExamples()
return

DemoPropertyDescriptorExamples() {
    ; BasicExample demonstrates optional bracket parameters.
    basic := BasicExample()
    OutputDebug "BasicExample.Data => " basic.Data
    OutputDebug "BasicExample.Data[5] => " basic.Data[5]

    ; ArrayProperty exposes Map-backed accessors.
    array := ArrayProperty()
    OutputDebug "ArrayProperty.SingleParam[1] => " array.SingleParam[1]
    OutputDebug "ArrayProperty.MultiParam[2] => " array.MultiParam[2]

    ; ConfigManager exposes typed lookups.
    cfg := ConfigManager()
    cfg.Set("database.host", "localhost")
    cfg.Set("api.timeout", 30)
    OutputDebug "ConfigManager.Get => " cfg.Get.Count " entries"
    OutputDebug "ConfigManager.Get['database.host'] => " cfg.Get["database.host"]

    ; Matrix exposes multi-parameter getter/setter support.
    matrix := Matrix(2, 2)
    matrix.Value[1, 1] := 1
    matrix.Value[2, 2] := 4
    OutputDebug "Matrix.Value[1,1] => " matrix.Value[1, 1]
    OutputDebug "Matrix.Value[2,2] => " matrix.Value[2, 2]

    MsgBox "Property descriptor demo complete. Check OutputDebug (View -> Debug Window) for details."
}
