## Category 4: Overlay Controls & Advanced GUI (10 examples)

### Example 26: Autocomplete Dropdown Overlay
*Shows suggestions as you type*

```ahk
#Requires AutoHotkey v2.0

class AutocompleteOverlay {
    __New(editCtrl, suggestions) {
        this.edit := editCtrl
        this.suggestions := suggestions
        this.dropdownGui := ""
        this.visible := false

        this.edit.OnEvent("Change", (*) => this.UpdateSuggestions())
        this.edit.OnEvent("Focus", (*) => this.UpdateSuggestions())
        this.edit.OnEvent("LoseFocus", (*) => this.HideDropdown())
    }

    UpdateSuggestions() {
        text := this.edit.Value
        if (StrLen(text) < 2) {
            this.HideDropdown()
            return
        }

        ; Filter suggestions
        matches := []
        for item in this.suggestions {
            if (InStr(item, text))
                matches.Push(item)
        }

        if (matches.Length == 0) {
            this.HideDropdown()
            return
        }

        this.ShowDropdown(matches)
    }

    ShowDropdown(matches) {
        ; Create dropdown if needed
        if (!this.dropdownGui) {
            this.dropdownGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
            this.listbox := this.dropdownGui.Add("ListBox", "r5 w200", [])
            this.listbox.OnEvent("DoubleClick", (*) => this.SelectItem())
        }

        ; Update items
        this.listbox.Delete()
        for item in matches
            this.listbox.Add([item])

        ; Position below edit
        this.edit.GetPos(&x, &y, &w, &h)
        this.dropdownGui.Show("x" x " y" (y + h) " w" w " NoActivate")
        this.visible := true
    }

    HideDropdown() {
        if (this.dropdownGui)
            this.dropdownGui.Hide()
        this.visible := false
    }

    SelectItem() {
        selected := this.listbox.Text
        this.edit.Value := selected
        this.HideDropdown()
    }
}

; Usage
MyGui := Gui()
SearchEdit := MyGui.Add("Edit", "x10 y10 w200 h25")

suggestions := ["Apple", "Application", "Banana", "Cherry", "Date",
                "Fig", "Grape", "Kiwi", "Lemon", "Mango"]

autocomplete := AutocompleteOverlay(SearchEdit, suggestions)
MyGui.Show()
```

---

### Example 27: Tooltip Menu System
*Context menu that follows cursor*

```ahk
#Requires AutoHotkey v2.0

class TooltipMenu {
    __New() {
        this.items := []
        this.gui := ""
        this.visible := false
    }

    AddItem(text, callback) {
        this.items.Push({text: text, callback: callback})
    }

    Show() {
        if (this.items.Length == 0)
            return

        if (!this.gui) {
            this.gui := Gui("+AlwaysOnTop -Caption +ToolWindow")
            this.gui.BackColor := "White"
            this.gui.SetFont("s10")

            for i, item in this.items {
                btn := this.gui.Add("Button", "x0 y" ((i-1)*30) " w200 h30", item.text)
                btn.OnEvent("Click", item.callback)
            }
        }

        MouseGetPos(&mx, &my)
        this.gui.Show("x" mx " y" my " NoActivate")
        this.visible := true
    }

    Hide() {
        if (this.gui)
            this.gui.Hide()
        this.visible := false
    }
}

; Usage
menu := TooltipMenu()
menu.AddItem("Copy", () => Send("^c"))
menu.AddItem("Paste", () => Send("^v"))
menu.AddItem("Search", () => Run("https://google.com"))
menu.AddItem("Cancel", () => menu.Hide())

^Space:: {
    if (menu.visible)
        menu.Hide()
    else
        menu.Show()
}
```

---

### Example 28: Progress Bar Overlay on Window
*Shows progress directly on any window*

```ahk
#Requires AutoHotkey v2.0

class WindowProgressOverlay {
    __New(targetWinTitle) {
        this.target := targetWinTitle
        this.gui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")  ; Clickthrough
        this.gui.BackColor := "Black"
        WinSetTransColor("Black", this.gui)

        this.progress := this.gui.Add("Progress", "x0 y0 w400 h30 BackgroundGray cGreen", 0)
        this.text := this.gui.Add("Text", "x0 y35 w400 Center", "0%")
        this.text.SetFont("s12 Bold", "Arial")

        this.PositionOverlay()
    }

    PositionOverlay() {
        if (WinExist(this.target)) {
            WinGetPos(&x, &y, &w, &h, this.target)
            ; Center at bottom of window
            overlayX := x + (w - 400) / 2
            overlayY := y + h - 100
            this.gui.Show("x" overlayX " y" overlayY " w400 h70 NoActivate")
        }
    }

    SetProgress(value, text := "") {
        this.progress.Value := value
        displayText := text ? text : (value "%")
        this.text.Value := displayText
        this.PositionOverlay()
    }

    Close() {
        this.gui.Destroy()
    }
}

; Usage
overlay := WindowProgressOverlay("Notepad")

; Simulate progress
Loop 100 {
    overlay.SetProgress(A_Index, "Processing " A_Index "/100")
    Sleep(50)
}

overlay.Close()
```

---

### Example 29: Floating Toolbar
*Toolbar that stays near cursor*

```ahk
#Requires AutoHotkey v2.0

class FloatingToolbar {
    __New() {
        this.gui := Gui("+AlwaysOnTop -Caption +ToolWindow")
        this.gui.BackColor := "333333"
        this.gui.SetFont("s10", "Segoe UI")

        ; Add tool buttons
        this.AddButton("✂", () => Send("^x"), "Cut")
        this.AddButton("📋", () => Send("^c"), "Copy")
        this.AddButton("📄", () => Send("^v"), "Paste")
        this.AddButton("↶", () => Send("^z"), "Undo")
        this.AddButton("↷", () => Send("^y"), "Redo")

        this.xOffset := 0
        this.lastX := 0
        this.lastY := 0

        ; Follow cursor
        SetTimer(() => this.FollowCursor(), 100)
    }

    AddButton(icon, callback, tooltip) {
        btn := this.gui.Add("Button", "x" this.xOffset " y0 w40 h40", icon)
        btn.OnEvent("Click", callback)
        btn.ToolTip := tooltip
        this.xOffset += 40
    }

    FollowCursor() {
        MouseGetPos(&mx, &my)

        ; Only update if mouse moved significantly
        if (Abs(mx - this.lastX) < 50 && Abs(my - this.lastY) < 50)
            return

        this.lastX := mx
        this.lastY := my

        ; Position toolbar below and right of cursor
        this.gui.Show("x" (mx + 20) " y" (my + 20) " NoActivate")
    }

    Hide() {
        this.gui.Hide()
    }

    Show() {
        this.FollowCursor()
    }
}

; Usage
toolbar := FloatingToolbar()

^!t::toolbar.Show()
^!h::toolbar.Hide()

MsgBox("Ctrl+Alt+T to show toolbar`nCtrl+Alt+H to hide")
```

---

### Example 30: Magnifier Overlay
*Magnifies area under cursor*

```ahk
#Requires AutoHotkey v2.0

class MagnifierOverlay {
    __New(zoom := 2) {
        this.zoom := zoom
        this.size := 200
        this.gui := Gui("+AlwaysOnTop -Caption +ToolWindow")
        this.pic := this.gui.Add("Picture", "w" this.size " h" this.size)
        this.active := false
    }

    Toggle() {
        this.active := !this.active

        if (this.active) {
            this.gui.Show("NoActivate")
            SetTimer(() => this.Update(), 50)
        } else {
            this.gui.Hide()
            SetTimer(() => this.Update(), 0)
        }
    }

    Update() {
        if (!this.active)
            return

        MouseGetPos(&mx, &my)

        ; Calculate capture area
        captureSize := this.size / this.zoom
        captureX := mx - captureSize / 2
        captureY := my - captureSize / 2

        ; Capture screen area
        pBitmap := this.CaptureScreen(captureX, captureY, captureSize, captureSize)

        ; Scale up
        pScaled := this.ScaleBitmap(pBitmap, this.size, this.size)

        ; Display
        this.DisplayBitmap(pScaled)

        ; Position magnifier near cursor
        this.gui.Show("x" (mx + 30) " y" (my + 30) " NoActivate")
    }

    CaptureScreen(x, y, w, h) {
        ; Simplified - would use GDI+ in real implementation
        ; This is a placeholder showing the concept
        return 0
    }

    ScaleBitmap(pBitmap, newW, newH) {
        ; Would use GDI+ to scale bitmap
        return pBitmap
    }

    DisplayBitmap(pBitmap) {
        ; Would display the scaled bitmap
        ; this.pic.Value := pBitmap
    }
}

; Usage
magnifier := MagnifierOverlay(3)
^m::magnifier.Toggle()

MsgBox("Press Ctrl+M to toggle magnifier (concept demo)")
```

---

### Example 31: Markdown Preview Overlay
*Live markdown preview next to editor*

```ahk
#Requires AutoHotkey v2.0

class MarkdownPreview {
    __New(editCtrl) {
        this.edit := editCtrl
        this.preview := Gui("+Resize", "Preview")
        this.html := this.preview.Add("ActiveX", "w600 h400", "Shell.Explorer")

        this.edit.OnEvent("Change", (*) => this.Update())
        this.PositionPreview()
    }

    PositionPreview() {
        this.edit.Gui.GetPos(&x, &y, &w, &h)
        this.preview.Show("x" (x + w + 10) " y" y " w600 h" h)
    }

    Update() {
        markdown := this.edit.Value
        html := this.ConvertMarkdown(markdown)
        this.html.Navigate("about:blank")
        this.html.document.write(html)
    }

    ConvertMarkdown(md) {
        ; Simple markdown to HTML (basic implementation)
        html := "<html><head><style>body{font-family:Arial;padding:20px;}</style></head><body>"

        ; Headers
        md := RegExReplace(md, "m)^# (.+)$", "<h1>$1</h1>")
        md := RegExReplace(md, "m)^## (.+)$", "<h2>$1</h2>")
        md := RegExReplace(md, "m)^### (.+)$", "<h3>$1</h3>")

        ; Bold
        md := RegExReplace(md, "\*\*(.+?)\*\*", "<strong>$1</strong>")

        ; Italic
        md := RegExReplace(md, "\*(.+?)\*", "<em>$1</em>")

        ; Line breaks
        md := RegExReplace(md, "`n", "<br>")

        html .= md "</body></html>"
        return html
    }
}

; Usage
MyGui := Gui(, "Markdown Editor")
Edit := MyGui.Add("Edit", "x10 y10 w600 h400 Multi")
MyGui.Show()

preview := MarkdownPreview(Edit)
```

---

### Example 32: Color Picker Overlay
*Click anywhere to pick color*

```ahk
#Requires AutoHotkey v2.0

class ColorPicker {
    __New() {
        this.active := false
        this.gui := Gui("+AlwaysOnTop -Caption +ToolWindow")
        this.gui.BackColor := "White"
        this.colorBox := this.gui.Add("Progress", "x10 y10 w80 h80 BackgroundWhite")
        this.text := this.gui.Add("Edit", "x10 y100 w80 ReadOnly Center", "#000000")
    }

    Toggle() {
        this.active := !this.active

        if (this.active) {
            this.gui.Show()
            SetTimer(() => this.Update(), 50)
        } else {
            this.gui.Hide()
            SetTimer(() => this.Update(), 0)
        }
    }

    Update() {
        if (!this.active)
            return

        MouseGetPos(&mx, &my)

        ; Get pixel color at cursor
        color := PixelGetColor(mx, my)

        ; Update display
        this.colorBox.Opt("Background" color)
        this.text.Value := color

        ; Position near cursor
        this.gui.Show("x" (mx + 20) " y" (my + 20) " NoActivate")

        ; Click to copy
        if (GetKeyState("LButton", "P")) {
            A_Clipboard := color
            ToolTip("Copied: " color)
            SetTimer(() => ToolTip(), -1000)
            this.Toggle()
        }
    }
}

; Usage
picker := ColorPicker()
^+c::picker.Toggle()

MsgBox("Press Ctrl+Shift+C to activate color picker`nClick to copy color")
```

---

### Example 33: Window Thumbnail Preview
*Shows mini preview of windows*

```ahk
#Requires AutoHotkey v2.0

class WindowThumbnails {
    __New() {
        this.gui := Gui("+AlwaysOnTop +Resize", "Window Thumbnails")
        this.gui.SetFont("s8")
        this.thumbnails := []

        this.Refresh()
        this.gui.Show("w800 h600")

        SetTimer(() => this.Refresh(), 2000)
    }

    Refresh() {
        ; Clear old thumbnails
        for thumb in this.thumbnails
            thumb.Destroy()

        this.thumbnails := []

        ; Get all windows
        windows := WinGetList(,, "Program Manager")

        x := 10
        y := 10
        for winId in windows {
            if (!WinExist("ahk_id " winId))
                continue

            title := WinGetTitle("ahk_id " winId)
            if (StrLen(title) == 0)
                continue

            ; Create thumbnail representation
            btn := this.gui.Add("Button", "x" x " y" y " w150 h100", SubStr(title, 1, 20))
            btn.OnEvent("Click", (*) => WinActivate("ahk_id " winId))
            this.thumbnails.Push(btn)

            x += 160
            if (x > 700) {
                x := 10
                y += 110
            }
        }
    }
}

; Usage
^!w::WindowThumbnails()
```

---

### Example 34: Overlay Drawing Canvas
*Draw annotations on screen*

```ahk
#Requires AutoHotkey v2.0

class DrawingOverlay {
    __New() {
        this.gui := Gui("+AlwaysOnTop -Caption +E0x80000")  ; WS_EX_LAYERED
        WinSetTransColor("White", this.gui)

        A_ScreenWidth := SysGet(16)
        A_ScreenHeight := SysGet(17)

        this.gui.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight " NoActivate")

        this.drawing := false
        this.lastX := 0
        this.lastY := 0
        this.lines := []

        SetTimer(() => this.CheckDraw(), 10)
    }

    CheckDraw() {
        ; Hold Ctrl+Shift to draw
        if (GetKeyState("Ctrl", "P") && GetKeyState("Shift", "P") && GetKeyState("LButton", "P")) {
            MouseGetPos(&mx, &my)

            if (this.drawing) {
                ; Draw line from last position
                this.DrawLine(this.lastX, this.lastY, mx, my)
            }

            this.drawing := true
            this.lastX := mx
            this.lastY := my
        } else {
            this.drawing := false
        }
    }

    DrawLine(x1, y1, x2, y2) {
        ; Store line for redraw
        this.lines.Push({x1: x1, y1: y1, x2: x2, y2: y2})

        ; In real implementation, would use GDI+ to draw on transparent overlay
        OutputDebug("Draw line: " x1 "," y1 " to " x2 "," y2)
    }

    Clear() {
        this.lines := []
        ; Would clear the canvas
    }

    Close() {
        this.gui.Destroy()
    }
}

; Usage
^!d::DrawingOverlay()

MsgBox("Hold Ctrl+Shift and drag mouse to draw on screen (concept)")
```

---

### Example 35: Notification Center
*Stacks notifications like Windows Action Center*

```ahk
#Requires AutoHotkey v2.0

class NotificationCenter {
    __New() {
        this.notifications := []
        this.yOffset := 10
        this.xPos := A_ScreenWidth - 310
    }

    Notify(title, message, duration := 5000) {
        ; Create notification GUI
        notif := Gui("+AlwaysOnTop -Caption +ToolWindow")
        notif.BackColor := "222222"
        notif.SetFont("s10 cWhite", "Segoe UI")

        notif.Add("Text", "x10 y10 w280", title).SetFont("Bold")
        notif.Add("Text", "x10 y35 w280", message)
        closeBtn := notif.Add("Button", "x260 y10 w30 h20", "×")

        ; Position notification
        yPos := this.yOffset
        for n in this.notifications
            yPos += 80

        notif.Show("x" this.xPos " y" yPos " w300 h70 NoActivate")

        ; Store notification
        notifObj := {gui: notif, y: yPos}
        this.notifications.Push(notifObj)

        ; Auto-dismiss
        SetTimer(() => this.Remove(notif), -duration)

        ; Close button
        closeBtn.OnEvent("Click", (*) => this.Remove(notif))
    }

    Remove(notif) {
        ; Find and remove notification
        for i, n in this.notifications {
            if (n.gui = notif) {
                n.gui.Destroy()
                this.notifications.RemoveAt(i)

                ; Reposition remaining notifications
                this.Reposition()
                return
            }
        }
    }

    Reposition() {
        yPos := this.yOffset
        for n in this.notifications {
            n.y := yPos
            n.gui.Show("x" this.xPos " y" yPos " NoActivate")
            yPos += 80
        }
    }
}

; Usage
nc := NotificationCenter()

^1::nc.Notify("Info", "This is an information message")
^2::nc.Notify("Warning", "This is a warning message")
^3::nc.Notify("Error", "This is an error message")

MsgBox("Press Ctrl+1/2/3 to test notifications")
```

Continue to final 15 examples in next message...
