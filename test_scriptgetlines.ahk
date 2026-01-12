; Test _ScriptGetLines function

; Get 3 lines around the current line
lines := _ScriptGetLines(A_LineFile, A_LineNumber, -2)

output := "=== _ScriptGetLines Test ===`n`n"
output .= "Current file: " A_LineFile "`n"
output .= "Current line: " A_LineNumber "`n`n"
output .= "Source context:`n"

for line in lines {
    prefix := (line.Number = 4) ? ">>> " : "    "
    output .= prefix . Format("{:03}", line.Number) . ": " . line.Text . "`n"
}

MsgBox(output, "AutoHotkey with _ScriptGetLines")
