#Requires AutoHotkey v2.0
#SingleInstance Force

; Hook Test Suite GUI
; Runs test-hooks.sh via WSL and displays results in a ListView.

global SCRIPT_PATH := "/mnt/c/Users/uphol/Documents/AHK/.claude/hooks/test-hooks.sh"
global LV, SB, RunBtn

g := Gui("+Resize +MinSize430x280", "Hook Test Suite")
g.BackColor := "FFFFFF"

g.SetFont("s11", "Segoe UI")
RunBtn := g.AddButton("xm ym w140 h36", "▶  Run Tests")
RunBtn.OnEvent("Click", RunTests)

g.SetFont("s9", "Segoe UI")
LV := g.AddListView("xm y+10 w580 r20", ["", "Hook", "Test"])
LV.ModifyCol(1, 32)
LV.ModifyCol(2, 190)
LV.ModifyCol(3, 340)

SB := g.AddStatusBar()
SB.SetText("  Click Run Tests to start")

g.OnEvent("Size", GuiResize)
g.OnEvent("Close", (*) => ExitApp())
g.Show("w620 h500")
return

RunTests(*) {
    global LV, SB, RunBtn, SCRIPT_PATH
    try {
        LV.Delete()
        RunBtn.Enabled := false
        SB.SetText("  ⏳ Running tests...")

        ; Build a tiny launcher script in Windows temp
        tmpSh := A_Temp "\run-hook-tests.sh"
        tmpOut := A_Temp "\hook-test-output.txt"
        try FileDelete(tmpSh)
        try FileDelete(tmpOut)

        launcher := "#!/bin/bash" "`n"
            . 'export PATH="$HOME/.local/bin:$PATH"' "`n"
            . "bash " SCRIPT_PATH " 2>&1" "`n"
        FileAppend(launcher, tmpSh)

        ; Convert Windows temp path → WSL path
        wslSh := WinToWsl(tmpSh)

        ; Run via WSL, redirect stdout to a Windows temp file
        RunWait(A_ComSpec ' /c wsl bash "' wslSh '" > "' tmpOut '"', , "Hide")

        raw := ""
        try raw := FileRead(tmpOut)
        try FileDelete(tmpSh)
        try FileDelete(tmpOut)

        if (raw = "") {
            SB.SetText("  ⚠️ No output — check that WSL and jq are installed")
            RunBtn.Enabled := true
            return
        }

        ParseAndShow(raw)
    } catch as e {
        SB.SetText("  ❌ Error: " e.Message)
    }
    RunBtn.Enabled := true
}

ParseAndShow(raw) {
    global LV, SB

    ; Strip ANSI escape codes
    text := RegExReplace(raw, "\x{1B}\[[0-9;]*m")

    hook := ""
    pass := 0
    fail := 0
    skip := 0

    loop parse text, "`n", "`r" {
        line := Trim(A_LoopField)

        if RegExMatch(line, "=== (.+?) \(", &m)
            hook := m[1]
        else if RegExMatch(line, "^PASS (.+)", &m) {
            LV.Add("", "✅", hook, m[1])
            pass++
        }
        else if RegExMatch(line, "^FAIL (.+)", &m) {
            LV.Add("", "❌", hook, m[1])
            fail++
        }
        else if RegExMatch(line, "^SKIP (.+)", &m) {
            LV.Add("", "⏭", hook, m[1])
            skip++
        }
    }

    total := pass + fail
    if (!pass && !fail && !skip)
        SB.SetText("  ⚠️ No test results found in output")
    else if (!fail && !skip)
        SB.SetText("  ✅ ALL TESTS PASSED: " pass "/" total)
    else if (!fail)
        SB.SetText("  ✅ " pass "/" total " passed (" skip " skipped)")
    else {
        s := "  ❌ " pass "/" total " passed, " fail " failed"
        if skip
            s .= " (" skip " skipped)"
        SB.SetText(s)
    }
}

WinToWsl(winPath) {
    drive := StrLower(SubStr(winPath, 1, 1))
    rest := StrReplace(SubStr(winPath, 3), "\", "/")
    return "/mnt/" drive rest
}

GuiResize(g, minMax, w, h) {
    global LV
    if minMax = -1
        return
    LV.Move(,, w - 20, h - 95)
}
