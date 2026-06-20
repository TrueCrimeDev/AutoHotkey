/*
ansi_color.ahk — colored console output in AutoHotkey v2 via ANSI escapes

Two things make ANSI color work in a plain cmd.exe / PowerShell console:

  1. A REAL escape byte. AHK's escape character is the backtick, and there is
     no `e sequence, so "\e[31m" is literal backslash-e text and "`e[31m" is
     invalid. Use Chr(0x1B) to get the actual ESC (0x1B) byte.

  2. Virtual-terminal processing. Legacy conhost ignores ANSI until you opt in
     with SetConsoleMode | ENABLE_VIRTUAL_TERMINAL_PROCESSING (0x4). Windows
     Terminal / Cmder / ConEmu enable it for you; raw cmd/pwsh do not.

And a trap: write through the SAME handle VT was enabled on. FileAppend("CONOUT$")
opens a fresh handle (VT defaults OFF) and shows raw escapes anyway — so this
example writes via WriteConsoleW on the configured handle instead.

With all three in place you build one fully-colored string and emit it in a
single write — no per-segment SetConsoleTextAttribute calls.

Usage:
  bin\AutoHotkey64.exe examples\ansi_color.ahk          ; color demo
  bin\AutoHotkey64.exe examples\ansi_color.ahk test     ; runtime self-test
*/
#Requires AutoHotkey v2.0

main()

main() {
    if (A_Args.Length >= 1 && A_Args[1] = "test") {
        SelfTest()
        return
    }
    Demo()
}

; Enable ANSI/VT processing on the active console screen buffer (once).
; Returns the console handle, or 0 if output isn't a real console (redirected).
InitVT() {
    static h := 0
    if h
        return h
    ; CONOUT$ → the active screen buffer, even when stdout is redirected.
    ; GENERIC_READ|WRITE = 0xC0000000, FILE_SHARE_READ|WRITE = 3, OPEN_EXISTING = 3
    handle := DllCall("CreateFile", "str", "CONOUT$", "uint", 0xC0000000, "uint", 3,
                      "ptr", 0, "uint", 3, "uint", 0, "ptr", 0, "ptr")
    if (handle = -1 || handle = 0)
        return 0
    mode := 0
    if DllCall("GetConsoleMode", "ptr", handle, "uint*", &mode)
        DllCall("SetConsoleMode", "ptr", handle, "uint", mode | 0x4)  ; +VT processing
    h := handle
    return h
}

; Convert <color>text</color> tags into ANSI escape sequences (single level).
AnsiTags(text) {
    static fg := Map(
        "black", 30, "red", 31, "green", 32, "yellow", 33,
        "blue", 34, "magenta", 35, "cyan", 36, "white", 37, "gray", 90)
    esc := Chr(0x1B)
    reset := esc . "[0m"
    out := ""
    pos := 1
    while (pos <= StrLen(text)) {
        if RegExMatch(text, "s)<(\w+)>(.*?)</\1>", &m, pos) {
            out .= SubStr(text, pos, m.Pos - pos)            ; text before the tag
            code := fg.Get(m[1], 37)
            out .= esc . "[" . code . "m" . m[2] . reset
            pos := m.Pos + m.Len
        } else {
            out .= SubStr(text, pos)
            break
        }
    }
    return out
}

; Write through the SAME handle VT was enabled on. A fresh CONOUT$ handle (what
; FileAppend opens) defaults to VT OFF, so writing via it shows raw escapes even
; after InitVT — that's the trap. WriteConsoleW reuses our configured handle.
; Falls back to stdout when there's no console (redirected/piped): raw text, no
; color, which is the correct behavior for a pipe.
ConWrite(text) {
    h := InitVT()
    if (h) {
        written := 0
        DllCall("WriteConsoleW", "ptr", h, "wstr", text, "uint", StrLen(text),
                "uint*", &written, "ptr", 0)
    } else {
        FileAppend(text, "*")
    }
}

; Render tags and write the whole line in one call.
Out(text) {
    ConWrite(AnsiTags(text) . "`n")
}

Demo() {
    esc := Chr(0x1B)
    if !InitVT()
        FileAppend("(no console attached; ANSI shows as raw text when redirected)`n", "*")

    buf := AnsiTags("<green>AHK v2 ANSI color demo</green>`n`n")

    ; Basic 16-color foreground swatch, built from tags.
    for name in ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white", "gray"]
        buf .= AnsiTags(Format("<{1}>{1}</{1}>  ", name))
    buf .= "`n"

    ; 256-color ramp (ESC[38;5;Nm).
    buf .= esc . "[1m256-color:" . esc . "[0m "
    Loop 18 {
        n := 16 + (A_Index - 1) * 12
        buf .= esc . "[38;5;" . n . "m" . Chr(0x2588)
    }
    buf .= esc . "[0m`n"

    ; Truecolor gradient (ESC[38;2;R;G;Bm).
    buf .= esc . "[1mtruecolor:" . esc . "[0m "
    Loop 24 {
        r := 255 - A_Index * 9
        g := A_Index * 9
        buf .= esc . "[38;2;" . r . ";" . g . ";128m" . Chr(0x2588)
    }
    buf .= esc . "[0m`n"

    ConWrite(buf)
}

; Runtime verification — proves AnsiTags emits real ESC sequences. No console
; needed; writes results to stdout and sets the exit code (0 = pass, 1 = fail).
SelfTest() {
    esc := Chr(0x1B)
    pass := true

    got := AnsiTags("<red>x</red>")
    want := esc . "[31mx" . esc . "[0m"
    pass := Assert("single tag", got, want) && pass

    got := AnsiTags("a<cyan>b</cyan>c")
    want := "a" . esc . "[36mb" . esc . "[0mc"
    pass := Assert("text around tag", got, want) && pass

    got := AnsiTags("<gray>dim</gray>")
    want := esc . "[90mdim" . esc . "[0m"
    pass := Assert("gray = bright black (90)", got, want) && pass

    ; The leading byte of a rendered tag must be ESC (0x1B), not '\'.
    firstByte := Ord(SubStr(AnsiTags("<red>x</red>"), 1, 1))
    pass := Assert("first byte is ESC 0x1B", firstByte, 0x1B) && pass

    Print("")
    Print(pass ? "ALL PASS" : "FAILURES")
    ExitApp(pass ? 0 : 1)
}

Assert(label, got, want) {
    ok := (got = want)
    Print("{} - {}", ok ? "ok  " : "FAIL", label)
    if !ok
        Print("       got  {}`n       want {}", ShowEsc(got), ShowEsc(want))
    return ok
}

ShowEsc(s) {
    return StrReplace(s, Chr(0x1B), "\e")
}
