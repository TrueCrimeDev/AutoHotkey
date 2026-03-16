; StringUtils module — imported by 03_import_from_file.ahk
; In alpha.21, #Module ends at end of file automatically.

#Module StringUtils

export ToUpper(str)
{
    return StrUpper(str)
}

export ToLower(str)
{
    return StrLower(str)
}

export Repeat(str, count)
{
    result := ""
    loop count
        result .= str
    return result
}

export Reverse(str)
{
    result := ""
    loop StrLen(str)
        result := SubStr(str, A_Index, 1) . result
    return result
}

export Trim(str)
{
    return RTrim(LTrim(str))
}
