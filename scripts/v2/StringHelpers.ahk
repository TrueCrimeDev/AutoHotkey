#Requires AutoHotkey v2.1-alpha.11+
#Module StringHelpers

; StringHelpers exposes reusable text utilities that can be imported by
; AutoHotkey v2 modules. Importing the module object (`Import StringHelpers`)
; provides read-only access to each exported helper as a member, while
; selective imports (`Import { Name } from StringHelpers`) bring individual
; functions into the caller's global scope.

Export CollapseWhitespace(str) {
    if str = ""
        return ""

    ; Normalize any run of whitespace characters (spaces, tabs, newlines)
    ; down to a single literal space so downstream consumers can rely on a
    ; predictable separator.
    return Trim(RegExReplace(str, "\\s+", " "))
}

Export ToTitleCase(str) {
    str := CollapseWhitespace(str)
    if str = ""
        return ""

    words := StrSplit(str, " ")
    for index, word in words {
        if word = ""
            continue
        words[index] := StrUpper(SubStr(word, 1, 1)) . StrLower(SubStr(word, 2))
    }
    return words.Join(" ")
}
