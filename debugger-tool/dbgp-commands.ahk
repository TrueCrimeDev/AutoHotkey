#Requires AutoHotkey v2.0
#SingleInstance Force

; DBGp Command Reference + Interactive Launcher
; Spawns the test harness in its own tracked terminal window.

app := DbgpCommandGui()
app.Show()

class DbgpCommandGui {
    __New() {
        this.terminalPid := 0
        this.ahkExe := A_ScriptDir "\..\bin\AutoHotkey64.exe"
        this.harnessScript := A_ScriptDir "\test-stdio-dbgp.js"

        this.gui := Gui("+AlwaysOnTop", "DBGp Stdio Commands")
        this.gui.SetFont("s10", "Segoe UI")
        this.gui.BackColor := "0x1a1a1a"
        this.gui.MarginX := 12
        this.gui.MarginY := 8

        ; --- Header ---
        this.gui.SetFont("s12 bold cWhite")
        this.gui.AddText("xm w700", "DBGp Stdio Debugger")
        this.gui.SetFont("s9 norm c0xa0a0a0")
        this.gui.AddText("xm w700", "Launch the harness, then click or double-click commands to send them.")

        ; --- Script picker + launch ---
        this.gui.SetFont("s9 norm cWhite")
        this.gui.AddText("xm w50 h26 +0x200", "Script:")
        this.gui.SetFont("s9", "Consolas")
        this.scriptEdit := this.gui.AddEdit("x+4 yp w380 h26 Background0x202020 c0xffffff")
        this.scriptEdit.Value := A_ScriptDir "\..\Alpha22_Example.ahk"
        this.gui.SetFont("s9 norm", "Segoe UI")
        this.browseBtn := this.gui.AddButton("x+4 yp w60 h26", "Browse")
        this.browseBtn.OnEvent("Click", (*) => this.BrowseScript())
        this.launchBtn := this.gui.AddButton("x+4 yp w150 h26 c0x7BC96F", "Launch Harness")
        this.launchBtn.OnEvent("Click", (*) => this.LaunchHarness())

        ; --- Connection status ---
        this.gui.SetFont("s9 bold c0xDC3545")
        this.connStatus := this.gui.AddText("xm w700 h20", "Not connected")

        ; --- Commands ListView ---
        this.gui.SetFont("s9 norm cWhite")
        ogLV := this.gui.AddListView("xm w700 r16 +Grid -Multi Background0x121212 c0xffffff", ["Category", "Command", "Description"])
        ogLV.OnEvent("Click", (ctrl, row) => this.OnRowClick(ctrl, row))
        ogLV.OnEvent("DoubleClick", (ctrl, row) => this.OnDoubleClick(ctrl, row))

        this.commands := []
        this.BuildCommands()
        for item in this.commands
            ogLV.Add("", item.cat, item.cmd, item.desc)

        ogLV.ModifyCol(1, 85)
        ogLV.ModifyCol(2, 340)
        ogLV.ModifyCol(3, 265)
        this.lv := ogLV

        ; --- Preview (editable) ---
        this.gui.SetFont("s9 c0x808080")
        this.gui.AddText("xm", "Edit command before sending:")
        this.gui.SetFont("s10 cWhite", "Consolas")
        this.preview := this.gui.AddEdit("xm w700 r1 Background0x0f0f0f c0x5B9FEF")

        ; --- Action buttons ---
        this.gui.SetFont("s10 norm", "Segoe UI")
        this.sendBtn := this.gui.AddButton("xm w140 h34", "Send (Enter)")
        this.sendBtn.OnEvent("Click", (*) => this.SendCommand())
        this.copyBtn := this.gui.AddButton("x+8 yp w100 h34", "Copy")
        this.copyBtn.OnEvent("Click", (*) => this.CopyPreview())
        this.killBtn := this.gui.AddButton("x+8 yp w120 h34", "Kill Harness")
        this.killBtn.OnEvent("Click", (*) => this.KillHarness())

        ; --- Status ---
        this.gui.SetFont("s8 c0x606060")
        this.status := this.gui.AddText("xm w700 h18", "Ready")

        this.gui.OnEvent("Close", (*) => this.Cleanup())

        ; Hotkey: Enter in preview sends command
        this.preview.OnEvent("Change", (*) => 0)  ; keep focus
        HotIfWinActive("ahk_id " this.gui.Hwnd)
        Hotkey("Enter", (*) => this.SendCommand())
    }

    Show() {
        this.gui.Show("w724")
    }

    Cleanup() {
        this.KillHarness()
        ExitApp()
    }

    BrowseScript() {
        result := FileSelect(1,, "Select AHK Script", "AHK Scripts (*.ahk)")
        if result
            this.scriptEdit.Value := result
    }

    LaunchHarness() {
        script := this.scriptEdit.Value
        if !FileExist(script) {
            this.status.Value := "Script not found: " script
            return
        }
        if !FileExist(this.harnessScript) {
            this.status.Value := "Test harness not found: " this.harnessScript
            return
        }

        ; Kill any existing harness
        if this.terminalPid
            this.KillHarness()

        ; Build command — launch node in a new cmd window with a known title
        windowTitle := "DBGp-Harness-" A_TickCount
        cmd := 'cmd.exe /c "title ' windowTitle ' && node "' this.harnessScript '" "' script '""'
        Run(cmd, A_ScriptDir,, &pid)
        this.terminalPid := pid

        this.gui.SetFont("s9 bold c0x7BC96F")
        this.connStatus.Value := "Harness launched (PID: " pid ") — waiting for init..."
        this.connStatus.SetFont("c0x7BC96F")

        ; Wait for the window to appear, then store its HWND
        this.windowTitle := windowTitle
        SetTimer(() => this.WaitForTerminal(), -1500)
    }

    WaitForTerminal() {
        if WinExist(this.windowTitle) {
            this.connStatus.SetFont("c0x7BC96F")
            this.connStatus.Value := "Connected — harness running (PID: " this.terminalPid ")"
            this.status.Value := "Click a command to select, double-click to send"
        } else {
            this.connStatus.SetFont("c0xF59E42")
            this.connStatus.Value := "Waiting for terminal... (PID: " this.terminalPid ")"
            ; Retry
            SetTimer(() => this.WaitForTerminal(), -1000)
        }
    }

    KillHarness() {
        if this.terminalPid {
            try ProcessClose(this.terminalPid)
            this.terminalPid := 0
            this.connStatus.SetFont("c0xDC3545")
            this.connStatus.Value := "Not connected"
            this.status.Value := "Harness killed"
        }
    }

    BuildCommands() {
        c := this.commands

        c.Push({cat: "Execution", cmd: "run", desc: "Continue until breakpoint/error"})
        c.Push({cat: "Execution", cmd: "step_into", desc: "Step into (enter functions)"})
        c.Push({cat: "Execution", cmd: "step_over", desc: "Step over (skip functions)"})
        c.Push({cat: "Execution", cmd: "step_out", desc: "Step out of current function"})
        c.Push({cat: "Execution", cmd: "stop", desc: "Terminate script"})
        c.Push({cat: "Execution", cmd: "detach", desc: "Disconnect, keep running"})
        c.Push({cat: "Execution", cmd: "break", desc: "Interrupt running script"})

        c.Push({cat: "Status", cmd: "status", desc: "Get current debugger state"})
        c.Push({cat: "Status", cmd: "stack_depth", desc: "Get call stack depth"})
        c.Push({cat: "Status", cmd: "stack_get", desc: "Get full call stack"})
        c.Push({cat: "Status", cmd: "stack_get -d 0", desc: "Get topmost stack frame"})

        c.Push({cat: "Variables", cmd: "context_names", desc: "List available contexts"})
        c.Push({cat: "Variables", cmd: "context_get -c 0", desc: "Get local variables"})
        c.Push({cat: "Variables", cmd: "context_get -c 1", desc: "Get global variables"})
        c.Push({cat: "Variables", cmd: "property_get -n varName", desc: "Get specific variable"})
        c.Push({cat: "Variables", cmd: "property_set -n varName -- base64", desc: "Set variable value"})
        c.Push({cat: "Variables", cmd: "property_value -n expression", desc: "Evaluate expression"})

        c.Push({cat: "Breakpoints", cmd: "breakpoint_set -t line -n 10", desc: "Break at line 10"})
        c.Push({cat: "Breakpoints", cmd: "breakpoint_set -t line -f file:///C%3A/path/script.ahk -n 10", desc: "Break at file:line"})
        c.Push({cat: "Breakpoints", cmd: "breakpoint_set -t exception", desc: "Break on any exception"})
        c.Push({cat: "Breakpoints", cmd: "breakpoint_list", desc: "List all breakpoints"})
        c.Push({cat: "Breakpoints", cmd: "breakpoint_get -d 1", desc: "Get breakpoint by ID"})
        c.Push({cat: "Breakpoints", cmd: "breakpoint_remove -d 1", desc: "Remove breakpoint by ID"})

        c.Push({cat: "Features", cmd: "feature_get -n language_name", desc: "Query: language name"})
        c.Push({cat: "Features", cmd: "feature_get -n max_children", desc: "Query: max child props"})
        c.Push({cat: "Features", cmd: "feature_set -n max_depth -v 3", desc: "Set property depth to 3"})
        c.Push({cat: "Features", cmd: "feature_set -n max_children -v 100", desc: "Set max children to 100"})

        c.Push({cat: "Source", cmd: "source -f file:///C%3A/path/script.ahk", desc: "Get full source code"})
        c.Push({cat: "Source", cmd: "source -f file:///C%3A/path/script.ahk -b 1 -e 20", desc: "Get lines 1-20"})

        c.Push({cat: "Streams", cmd: "stdout -c 1", desc: "Copy stdout to debugger"})
        c.Push({cat: "Streams", cmd: "stdout -c 2", desc: "Redirect stdout to debugger"})
        c.Push({cat: "Streams", cmd: "stderr -c 1", desc: "Copy stderr to debugger"})

        c.Push({cat: "Types", cmd: "typemap_get", desc: "Get type mapping"})
    }

    OnRowClick(ctrl, row) {
        if row < 1
            return
        cmd := ctrl.GetText(row, 2)
        this.preview.Value := cmd
        this.status.Value := "Selected — press Enter or double-click to send"
    }

    OnDoubleClick(ctrl, row) {
        if row < 1
            return
        cmd := ctrl.GetText(row, 2)
        this.preview.Value := cmd
        this.SendCommand()
    }

    CopyPreview() {
        cmd := this.preview.Value
        if cmd = "" {
            this.status.Value := "Nothing to copy"
            return
        }
        A_Clipboard := cmd
        this.status.Value := "Copied: " cmd
    }

    SendCommand() {
        cmd := this.preview.Value
        if cmd = "" {
            this.status.Value := "Nothing to send — select a command first"
            return
        }

        ; Find the harness terminal by its title
        if !this.terminalPid || !this.windowTitle {
            ; No harness — just copy to clipboard
            A_Clipboard := cmd
            this.status.Value := "No harness running — copied to clipboard instead"
            return
        }

        targetWin := this.windowTitle
        if !WinExist(targetWin) {
            A_Clipboard := cmd
            this.status.Value := "Terminal window not found — copied to clipboard"
            return
        }

        ; Save clipboard, put command on it, paste into terminal, restore
        prevClip := ClipboardAll()
        A_Clipboard := cmd
        ClipWait(1)

        WinActivate(targetWin)
        if !WinWaitActive(targetWin,, 2) {
            A_Clipboard := prevClip
            this.status.Value := "Could not activate terminal"
            return
        }

        SendInput("^v")
        Sleep(80)
        SendInput("{Enter}")
        Sleep(150)

        ; Restore clipboard and refocus GUI
        A_Clipboard := prevClip
        WinActivate("ahk_id " this.gui.Hwnd)
        this.status.Value := "Sent: " cmd
    }
}
