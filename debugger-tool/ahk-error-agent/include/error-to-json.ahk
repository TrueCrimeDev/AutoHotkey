; AHK Error-to-JSON Handler
; Outputs runtime errors as JSON to stderr for AI agent consumption
;
; Usage:
;   AutoHotkey.exe /ErrorStdOut /include error-to-json.ahk your_script.ahk 2>error.json
;
; Output format:
;   {"type":"UnsetError","message":"...","file":"...","line":42,"what":"","stack":"..."}

#Requires AutoHotkey v2.0

#Warn All, Off  ; Suppress warnings for cleaner JSON output

OnError(_ErrorToJSON, -1)

_ErrorToJSON(err, mode) {
    ; Escape special characters for JSON
    msg := _JsonEscape(err.Message)
    file := _JsonEscape(err.File)
    what := _JsonEscape(err.What)
    stack := _JsonEscape(err.Stack)
    extra := _JsonEscape(err.Extra)

    ; Build JSON object
    json := Format('{{'
        . '"type":"{1}",'
        . '"message":"{2}",'
        . '"file":"{3}",'
        . '"line":{4},'
        . '"what":"{5}",'
        . '"extra":"{6}",'
        . '"stack":"{7}",'
        . '"mode":"{8}"'
        . '}}',
        Type(err),
        msg,
        file,
        err.Line,
        what,
        extra,
        stack,
        mode
    )

    ; Output to stderr
    FileAppend(json "`n", "**")

    return -1
}

_JsonEscape(str) {
    str := StrReplace(str, "\", "\\")
    str := StrReplace(str, '"', '\"')
    str := StrReplace(str, "`n", "\n")
    str := StrReplace(str, "`r", "\r")
    str := StrReplace(str, "`t", "\t")
    return str
}

; MsgBox outputs to stdout as JSON too
MsgBox(Text?, Title?, Options?) {
    text := IsSet(Text) ? _JsonEscape(Text) : ""
    title := IsSet(Title) ? _JsonEscape(Title) : ""
    FileAppend(Format('{{"msgbox":true,"text":"{1}","title":"{2}"}}`n', text, title), "*")
    return "OK"
}
