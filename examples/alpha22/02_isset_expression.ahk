; alpha.22 Feature: IsSet permits unset expression without assignment
; Previously IsSet required a variable name only.
; Now you can pass an expression that might be unset.
; Requires: AutoHotkey v2.1-alpha.22+

; --- IsSet with optional parameters ---

CheckValue(val?) {
    ; In alpha.22, IsSet can take the optional param directly
    if IsSet(val)
        FileAppend("val is set: " String(val) "`n", "*")
    else
        FileAppend("val is unset`n", "*")
}

CheckValue("hello")  ; => val is set: hello
CheckValue()         ; => val is unset

; --- IsSet with virtual references ---

; Fixed in alpha.22: IsSet(p) correctly returns 0 for unset virtual references
class Config {
    static Get(key, default?) {
        ; IsSet works with the optional `default` parameter
        if IsSet(default)
            FileAppend('Config.Get("' key '") with default: ' String(default) "`n", "*")
        else
            FileAppend('Config.Get("' key '") without default`n', "*")
    }
}

Config.Get("theme", "dark")
Config.Get("theme")

; --- Combining Type() and IsSet() for robust parameter handling ---

SmartFunc(a, b?, c?) {
    FileAppend("a=" String(a), "*")
    FileAppend(", b " (IsSet(b) ? "=" String(b) : "is unset"), "*")
    FileAppend(", c " (IsSet(c) ? "=" String(c) : "is unset"), "*")
    FileAppend("`n", "*")
}

SmartFunc("x", "y", "z")
SmartFunc("x", "y")
SmartFunc("x")
