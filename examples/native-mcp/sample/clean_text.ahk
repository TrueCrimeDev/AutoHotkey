#Requires AutoHotkey v2.1-alpha.31
#Include TextTools.ahk
if A_Args.Length != 1
    throw ValueError("Usage: clean_text.ahk <text>")
result := Map()
result["original"] := A_Args[1]
result["cleaned"] := CleanText(A_Args[1])
result["beforeLength"] := StrLen(result["original"])
result["afterLength"] := StrLen(result["cleaned"])
Print(JSON.Stringify(result))
