/*
ansi_colors.ahk — Test ANSI escape codes in VS Code output panel
*/
#Requires AutoHotkey v2.0

stdout := FileOpen("*", "w", "UTF-8")
Print(text) => stdout.Write(text)

; ANSI escape = Chr(27) aka 0x1B
ESC := Chr(27)

; ─── Basic colors ─────────────────────────────────────────────────────────────
Print ESC "[1;37m=== ANSI Color Test ===" ESC "[0m`n`n"

; Standard foreground colors
colors := Map(
    "Black",   30, "Red",     31, "Green",   32, "Yellow",  33,
    "Blue",    34, "Magenta", 35, "Cyan",    36, "White",   37
)
for name, code in colors
    Print ESC "[" code "m" name ESC "[0m "
Print "`n"

; Bright/bold variants
Print "`nBright: "
for name, code in colors
    Print ESC "[1;" code "m" name ESC "[0m "
Print "`n"

; ─── Background colors ────────────────────────────────────────────────────────
Print "`nBackgrounds: "
for name, code in colors
    Print ESC "[" (code + 10) "m " name " " ESC "[0m "
Print "`n"

; ─── 256-color mode ───────────────────────────────────────────────────────────
Print "`n256-color ramp: "
loop 16
    Print ESC "[48;5;" (A_Index - 1) "m  " ESC "[0m"
Print "`n"
Print "                "
loop 16
    Print ESC "[48;5;" (A_Index + 15) "m  " ESC "[0m"
Print "`n"

; ─── 24-bit true color ───────────────────────────────────────────────────────
Print "`nTruecolor gradient: "
loop 32 {
    r := (A_Index - 1) * 8
    g := 255 - r
    b := 128
    Print ESC "[48;2;" r ";" g ";" b "m " ESC "[0m"
}
Print "`n"

; ─── Practical: status logging ────────────────────────────────────────────────
Print "`n"
Print ESC "[32m[PASS]" ESC "[0m All tests passed`n"
Print ESC "[31m[FAIL]" ESC "[0m Connection refused on port 443`n"
Print ESC "[33m[WARN]" ESC "[0m Config file missing, using defaults`n"
Print ESC "[36m[INFO]" ESC "[0m Server started on :8080`n"
Print ESC "[1;35m[DEBUG]" ESC "[0m Request payload: {`"id`": 42}`n"

; ─── Practical: styled table ──────────────────────────────────────────────────
Print "`n"
Print ESC "[1;4;37m  Status   Name          Size  " ESC "[0m`n"
Print ESC "[32m  OK  " ESC "[0m     main.ahk       1.2KB`n"
Print ESC "[32m  OK  " ESC "[0m     utils.ahk      0.8KB`n"
Print ESC "[31m  ERR " ESC "[0m     broken.ahk     0.3KB`n"
Print ESC "[33m  SKIP" ESC "[0m     draft.ahk      2.1KB`n"

; ─── Text styles ──────────────────────────────────────────────────────────────
Print "`n"
Print ESC "[1mBold" ESC "[0m  "
Print ESC "[2mDim" ESC "[0m  "
Print ESC "[3mItalic" ESC "[0m  "
Print ESC "[4mUnderline" ESC "[0m  "
Print ESC "[7mInverse" ESC "[0m  "
Print ESC "[9mStrikethrough" ESC "[0m`n"
