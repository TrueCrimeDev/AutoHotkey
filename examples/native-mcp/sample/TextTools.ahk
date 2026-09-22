#Requires AutoHotkey v2.1-alpha.31
; Pure text helper shared by the worker and tests.
CleanText(text) {
    cleaned := Trim(RegExReplace(text, "\s+", " "))
    if cleaned = ""
        throw ValueError("Provide at least one non-whitespace character.")
    return cleaned
}
