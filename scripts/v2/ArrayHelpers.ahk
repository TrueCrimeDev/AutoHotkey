#Requires AutoHotkey v2.1-alpha.17
#Module ArrayHelpers

; ArrayHelpers centralizes reusable Array utilities that can be imported
; by AutoHotkey v2 scripts. Importing the module object (`Import ArrayHelpers`)
; exposes read-only members for each export, while selective imports can bring
; `Join`, `Split`, or `EnsureArrayHelpers` directly into the caller's scope.

SetupArrayHelpers()

Export EnsureArrayHelpers() {
    SetupArrayHelpers()
}

Export Join(array, sep := ",") {
    SetupArrayHelpers()
    return array.Join(sep)
}

Export Split(str, sep := ",", target := unset) {
    SetupArrayHelpers()
    if !IsSet(target)
        target := []
    target.Split(str, sep)
    return target
}

SetupArrayHelpers() {
    static applied := false
    if applied
        return

    applied := true

    if !ObjHasOwnProp(Array.Prototype, "Join") {
        Array.Prototype.DefineProp("Join", {
            call: (a, sep := ",") {
                result := ""
                for i, v in a
                    result .= v (i < a.Length ? sep : "")
                return result
            }
        })
    }

    if !ObjHasOwnProp(Array.Prototype, "Split") {
        Array.Prototype.DefineProp("Split", {
            call: (a, str, sep := ",") {
                for v in StrSplit(str, sep)
                    a.Push(v)
                return a
            }
        })
    }
}
