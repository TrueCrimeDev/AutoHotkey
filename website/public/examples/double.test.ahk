#Requires AutoHotkey v2.1-alpha.31
Double(value) => value * 2
if Double(21) != 42
    throw Error("Double(21) must equal 42")
Print("PASS: Double(21) = 42")
