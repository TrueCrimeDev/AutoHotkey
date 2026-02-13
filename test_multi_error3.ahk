#Requires AutoHotkey v2.0

try {
    obj := {}
    obj.Error1()
} catch {
}

try {
    arr := []
    arr[99]
} catch {
}

; Uncaught - should exit with code 1
obj2 := {}
obj2.Uncaught()
