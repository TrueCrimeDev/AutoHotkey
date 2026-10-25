#Requires AutoHotkey v2.0
#SingleInstance Force

; Hook test runner: runs test-hooks.sh (next to this file) through Git for
; Windows bash and lists every PASS / FAIL / SKIP line. No WSL is involved.
; This is a GUI, so start it yourself; agents run `bash .claude/hooks/test-hooks.sh`
; directly and only `check` this file.

global LV, SB, RunBtn

g := Gui("+Resize +MinSize560x300", "Hook Test Suite")
g.SetFont("s10", "Segoe UI")
RunBtn := g.AddButton("xm ym w140 h32", "Run tests")
RunBtn.OnEvent("Click", RunTests)

g.SetFont("s9", "Segoe UI")
LV := g.AddListView("xm y+8 w860 r24", ["Result", "Section", "Case", "Detail"])
LV.ModifyCol(1, 55)
LV.ModifyCol(2, 200)
LV.ModifyCol(3, 330)
LV.ModifyCol(4, 250)

SB := g.AddStatusBar()
SB.SetText("  Click Run tests to start")

g.OnEvent("Size", GuiResize)
g.OnEvent("Close", (*) => ExitApp())
g.Show("w880 h560")

; Returns the full path of Git for Windows bash.exe, or "" when none is found.
; System32\bash.exe (the WSL launcher) and the WindowsApps alias are never used.
FindGitBash() {
    candidates := []
    for name in ["ProgramW6432", "ProgramFiles", "ProgramFiles(x86)"] {
        dir := EnvGet(name)
        if (dir != "")
            candidates.Push(dir "\Git\bin\bash.exe")
    }
    for root in ["HKLM", "HKCU"] {
        try candidates.Push(RegRead(root "\SOFTWARE\GitForWindows", "InstallPath") "\bin\bash.exe")
    }
    candidates.Push(EnvGet("LOCALAPPDATA") "\Programs\Git\bin\bash.exe")
    for path in candidates {
        if FileExist(path)
            return path
    }

    tmp := A_Temp "\hook-tests-where-" A_TickCount ".txt"
    try {
        RunWait(A_ComSpec ' /c "where bash.exe > "' tmp '" 2>nul"', , "Hide")
        list := FileRead(tmp)
        FileDelete(tmp)
    } catch {
        return ""
    }
    loop parse list, "`n", "`r" {
        path := Trim(A_LoopField)
        if (path = "" || InStr(path, "\System32\") || InStr(path, "\WindowsApps\"))
            continue
        if FileExist(path)
            return path
    }
    return ""
}

RunTests(*) {
    LV.Delete()
    RunBtn.Enabled := false
    try {
        bashExe := FindGitBash()
        if (bashExe = "") {
            SB.SetText("  Git for Windows bash.exe not found. Install Git for Windows; Claude Code needs it for the hooks too.")
            return
        }
        SB.SetText("  Running test-hooks.sh with " bashExe " ...")
        script := StrReplace(A_ScriptDir "\test-hooks.sh", "\", "/")
        outFile := A_Temp "\hook-tests-" A_TickCount ".txt"
        ; cmd /c ""bash.exe" "script" > "out" 2>&1 < NUL": the outer quotes are
        ; stripped by cmd, the inner ones survive. RunWait returns bash's exit code.
        exitCode := RunWait(A_ComSpec ' /c ""' bashExe '" "' script '" > "' outFile '" 2>&1 < NUL"', A_ScriptDir, "Hide")
        raw := ""
        try raw := FileRead(outFile, "UTF-8")
        try FileDelete(outFile)
        ShowResults(raw, exitCode)
    } catch as e {
        SB.SetText("  Error: " e.Message)
    } finally {
        RunBtn.Enabled := true
    }
}

ShowResults(raw, exitCode) {
    text := RegExReplace(raw, "\x{1B}\[[0-9;]*m")
    section := "", firstLine := "", fatal := "", result := ""
    pass := 0, fail := 0, skip := 0, failRow := 0

    loop parse text, "`n", "`r" {
        line := Trim(A_LoopField)
        if (line = "")
            continue
        if (firstLine = "")
            firstLine := line
        if RegExMatch(line, "^=== (.+) ===$", &m) {
            section := m[1]
            failRow := 0
        } else if RegExMatch(line, "^PASS (.+)$", &m) {
            LV.Add(, "PASS", section, m[1], "")
            pass++
            failRow := 0
        } else if RegExMatch(line, "^FAIL (.+)$", &m) {
            failRow := LV.Add(, "FAIL", section, m[1], "")
            fail++
        } else if RegExMatch(line, "^SKIP (.+?) -- (.+)$", &m) {
            LV.Add(, "SKIP", section, m[1], m[2])
            skip++
            failRow := 0
        } else if (failRow && RegExMatch(line, "^- (.+)$", &m)) {
            detail := LV.GetText(failRow, 4)
            LV.Modify(failRow, "Col4", detail = "" ? m[1] : detail "; " m[1])
        } else if RegExMatch(line, "^FATAL: (.+)$", &m) {
            fatal := m[1]
        } else if RegExMatch(line, "^RESULT: (.+)$", &m) {
            result := m[1]
        }
    }

    if (fatal != "")
        SB.SetText("  FATAL (exit " exitCode "): " fatal)
    else if (!pass && !fail && !skip)
        SB.SetText("  No test results (exit " exitCode "): " (firstLine = "" ? "no output" : firstLine))
    else {
        s := "  exit " exitCode ": " pass " passed, " fail " failed, " skip " skipped"
        if (skip)
            s .= "  WARNING: skipped cases did not run"
        if (result = "")
            s .= "  (no RESULT line: the run was cut short)"
        SB.SetText(s)
    }
}

GuiResize(thisGui, minMax, w, h) {
    if (minMax = -1)
        return
    LV.Move(, , w - 20, h - 80)
}
