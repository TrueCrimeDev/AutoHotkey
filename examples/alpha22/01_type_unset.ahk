; alpha.22 Feature: Type() returns "unset" for omitted parameters
; Previously Type() required exactly 1 argument.
; Now Type() with 0 args returns "unset", and unset optional params
; passed to Type() are handled via SYM_MISSING.

; --- Basic usage: Type() with no arguments ---

FileAppend("Type() = " Type() "`n", "*")           ; => "unset"
FileAppend("Type(42) = " Type(42) "`n", "*")       ; => "Integer"
FileAppend("Type('hi') = " Type("hello") "`n", "*")  ; => "String"
FileAppend("Type([]) = " Type([1, 2]) "`n", "*")   ; => "Array"

; --- Practical use: type-based dispatch ---
; When an optional param is omitted, check with IsSet first,
; then call Type() with no args or with the value.

FormatValue(val?) {
    if !IsSet(val)
        return "(no value provided) — Type() = " Type()
    switch Type(val) {
        case "Integer", "Float":
            return "Number: " val
        case "String":
            return 'String: "' val '"'
        case "Array":
            return "Array with " val.Length " elements"
        default:
            return "Object of type: " Type(val)
    }
}

FileAppend(FormatValue(100) "`n", "*")       ; Number: 100
FileAppend(FormatValue("test") "`n", "*")    ; String: "test"
FileAppend(FormatValue() "`n", "*")          ; (no value provided)

; --- Combined IsSet + Type pattern ---

ProcessParam(p?) {
    if !IsSet(p)
        FileAppend("Parameter was unset (Type() = " Type() ")`n", "*")
    else
        FileAppend("Parameter type: " Type(p) ", value: " String(p) "`n", "*")
}

ProcessParam()
ProcessParam(3.14)
