; StringUtils module — imported by 03_import_from_file.ahk
; No #Module line: the whole file is one default module, so
; `#Import "lib/StringUtils.ahk" {*}` binds every name it defines.


ToUpper(str)
{
    return StrUpper(str)
}

ToLower(str)
{
    return StrLower(str)
}

Repeat(str, count)
{
    result := ""
    loop count
        result .= str
    return result
}

Reverse(str)
{
    result := ""
    loop StrLen(str)
        result := SubStr(str, A_Index, 1) . result
    return result
}

Trim(str)
{
    return RTrim(LTrim(str))
}
