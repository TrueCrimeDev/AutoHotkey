# Overlay Controls Quick Reference

Quick code snippets for common overlay patterns in AutoHotkey v2.

## Method 1: Simple Button Overlay

```ahk
#Requires AutoHotkey v2.0

; Basic overlay - button over edit field
MyGui := Gui()
MyGui.Title := "Overlay Test"

; Main edit field
SearchEdit := MyGui.Add("Edit", "x10 y10 w200 h30", "Type here...")

; Overlay button (positioned inside edit field)
SearchBtn := MyGui.Add("Button", "x180 y13 w24 h24", "🔍")

SearchBtn.OnEvent("Click", (*) => MsgBox("Searching: " SearchEdit.Value))

MyGui.Show()
```

---

## Method 2: Search Box Component

```ahk
#Requires AutoHotkey v2.0

; Reusable search box with icon
CreateSearchBox(ParentGui, x, y, w, h) {
    ; Edit field
    Edit := ParentGui.Add("Edit", "x" x " y" y " w" w " h" h)

    ; Calculate icon position (right edge, inside field)
    IconX := x + w - 28  ; 28px from right
    IconY := y + 3       ; 3px from top (vertical center)

    Icon := ParentGui.Add("Button", "x" IconX " y" IconY " w24 h24", "🔍")

    ; Wire up events
    Icon.OnEvent("Click", (*) => Search(Edit.Value))

    return {Edit: Edit, Icon: Icon}
}

Search(Query) {
    MsgBox("Searching for: " Query)
}

; Usage
MyGui := Gui()
SearchBox := CreateSearchBox(MyGui, 10, 10, 300, 30)
MyGui.Show()
```

---

## Method 3: Search + Clear Buttons

```ahk
#Requires AutoHotkey v2.0

; Search box with clear button
CreateSearchBox(ParentGui, x, y, w, h) {
    Edit := ParentGui.Add("Edit", "x" x " y" y " w" w " h" h)

    ; Clear button (X)
    ClearX := x + w - 52
    ClearY := y + 3
    ClearBtn := ParentGui.Add("Button", "x" ClearX " y" ClearY " w24 h24 Hidden", "✕")

    ; Search button
    SearchX := x + w - 28
    SearchBtn := ParentGui.Add("Button", "x" SearchX " y" ClearY " w24 h24", "🔍")

    ; Events
    SearchBtn.OnEvent("Click", (*) => DoSearch(Edit.Value))
    ClearBtn.OnEvent("Click", (*) => ClearField(Edit, ClearBtn))
    Edit.OnEvent("Change", (*) => ToggleClear(Edit, ClearBtn))

    return {Edit: Edit, Search: SearchBtn, Clear: ClearBtn}
}

DoSearch(Query) {
    MsgBox("Searching: " Query)
}

ClearField(EditCtrl, ClearBtn) {
    EditCtrl.Value := ""
    ClearBtn.Visible := false
    EditCtrl.Focus()
}

ToggleClear(EditCtrl, ClearBtn) {
    ClearBtn.Visible := (EditCtrl.Value != "")
}

; Usage
MyGui := Gui()
SearchBox := CreateSearchBox(MyGui, 10, 10, 300, 30)
MyGui.Show()
```

---

## Method 4: Input with Run Button

```ahk
#Requires AutoHotkey v2.0

; Command input with run button
CreateCommandBox(ParentGui, x, y, w, h) {
    Edit := ParentGui.Add("Edit", "x" x " y" y " w" w " h" h)

    RunX := x + w - 28
    RunBtn := ParentGui.Add("Button", "x" RunX " y" (y + 3) " w24 h24", "▶")

    RunBtn.OnEvent("Click", (*) => Execute(Edit.Value))

    return {Edit: Edit, Run: RunBtn}
}

Execute(Command) {
    MsgBox("Executing: " Command)
    ; Add your execution logic here
}

; Usage
MyGui := Gui()
CmdBox := CreateCommandBox(MyGui, 10, 10, 300, 30)
MyGui.Show()
```

---

## Method 5: Picture Control Overlay

```ahk
#Requires AutoHotkey v2.0

; Using Picture control instead of Button
; (Better for custom icons/transparency)

MyGui := Gui()
Edit := MyGui.Add("Edit", "x10 y10 w200 h30")

; Picture control (can use PNG with transparency)
; You'll need a search-icon.png file
IconPic := MyGui.Add("Picture", "x180 y13 w24 h24", "search-icon.png")

; Make it clickable
IconPic.OnEvent("Click", (*) => MsgBox("Icon clicked!"))

MyGui.Show()
```

---

## Method 6: Text Control as Icon

```ahk
#Requires AutoHotkey v2.0

; Using Text control for icons (Unicode symbols)
MyGui := Gui()
Edit := MyGui.Add("Edit", "x10 y10 w200 h30")

; Text control with emoji/symbol
Icon := MyGui.Add("Text", "x180 y11 w24 h24 Center", "🔍")
Icon.SetFont("s14")  ; Larger font

; Make it clickable and add hover cursor
Icon.OnEvent("Click", (*) => MsgBox("Search clicked!"))

MyGui.Show()
```

---

## Method 7: Password Toggle

```ahk
#Requires AutoHotkey v2.0

; Password field with show/hide toggle
CreatePasswordBox(ParentGui, x, y, w, h) {
    Edit := ParentGui.Add("Edit", "x" x " y" y " w" w " h" h " Password")

    ToggleX := x + w - 28
    ToggleBtn := ParentGui.Add("Button", "x" ToggleX " y" (y + 3) " w24 h24", "👁")

    IsShowing := false

    ToggleBtn.OnEvent("Click", (*) => {
        global IsShowing
        IsShowing := !IsShowing

        ; Toggle password mode
        Edit.Opt(IsShowing ? "-Password" : "+Password")

        ; Update button icon
        ToggleBtn.Text := IsShowing ? "👁" : "👁‍🗨"
    })

    return {Edit: Edit, Toggle: ToggleBtn}
}

; Usage
MyGui := Gui()
PwdBox := CreatePasswordBox(MyGui, 10, 10, 300, 30)
MyGui.Show()
```

---

## Method 8: Responsive Overlay (Resizable)

```ahk
#Requires AutoHotkey v2.0

; Maintains overlay position when window resizes
MyGui := Gui("+Resize")

Edit := MyGui.Add("Edit", "x10 y10 w300 h30 vSearchEdit")
Icon := MyGui.Add("Button", "x282 y13 w24 h24 vSearchIcon", "🔍")

; Handle resize
MyGui.OnEvent("Size", AdjustOverlay)

AdjustOverlay(GuiObj, MinMax, Width, Height) {
    ; Get edit field
    EditCtrl := GuiObj["SearchEdit"]
    IconCtrl := GuiObj["SearchIcon"]

    ; Calculate new width (maintain margins)
    NewWidth := Width - 20

    ; Resize edit
    EditCtrl.Move(10, 10, NewWidth, 30)

    ; Reposition icon
    IconX := 10 + NewWidth - 28
    IconCtrl.Move(IconX, 13)
}

MyGui.Show("w400 h300")
```

---

## Position Calculation Helper

```ahk
; Helper function to calculate overlay positions
CalculateOverlayPos(ParentX, ParentY, ParentW, ParentH, OverlayW, OverlayH, Position := "right") {
    switch Position {
        case "right":
            return {
                x: ParentX + ParentW - OverlayW - 4,
                y: ParentY + ((ParentH - OverlayH) / 2)
            }
        case "left":
            return {
                x: ParentX + 4,
                y: ParentY + ((ParentH - OverlayH) / 2)
            }
        case "center":
            return {
                x: ParentX + ((ParentW - OverlayW) / 2),
                y: ParentY + ((ParentH - OverlayH) / 2)
            }
    }
}

; Usage
MyGui := Gui()
Edit := MyGui.Add("Edit", "x10 y10 w200 h30")

; Calculate icon position
Pos := CalculateOverlayPos(10, 10, 200, 30, 24, 24, "right")
Icon := MyGui.Add("Button", "x" Pos.x " y" Pos.y " w24 h24", "🔍")

MyGui.Show()
```

---

## Common Unicode Icons

```ahk
; Useful symbols for overlay buttons
Icons := Map(
    "search", "🔍",      ; Magnifying glass
    "run", "▶",          ; Play/Run
    "clear", "✕",        ; X/Close
    "check", "✓",        ; Checkmark
    "eye", "👁",         ; Show
    "eye-closed", "👁‍🗨",  ; Hide
    "settings", "⚙",     ; Gear
    "down", "▼",         ; Dropdown
    "up", "▲",           ; Collapse
    "plus", "➕",         ; Add
    "minus", "➖",        ; Remove
    "info", "ℹ",         ; Information
    "warning", "⚠",      ; Warning
)

; Usage
MyGui := Gui()
Edit := MyGui.Add("Edit", "x10 y10 w200 h30")
SearchBtn := MyGui.Add("Button", "x180 y13 w24 h24", Icons["search"])
MyGui.Show()
```

---

## Debugging Overlay Positions

```ahk
; Helper to visualize control positions
ShowControlBounds(GuiCtrl) {
    GuiCtrl.GetPos(&x, &y, &w, &h)
    ToolTip("Control: x=" x " y=" y " w=" w " h=" h)
    SetTimer(() => ToolTip(), -3000)  ; Hide after 3 seconds
}

; Usage
MyGui := Gui()
Edit := MyGui.Add("Edit", "x10 y10 w200 h30")
Icon := MyGui.Add("Button", "x180 y13 w24 h24", "🔍")

; Click to show bounds
Icon.OnEvent("Click", (*) => ShowControlBounds(Icon))

MyGui.Show()
```

---

## Tips & Best Practices

1. **Z-Order**: Controls created later appear on top
2. **Positioning**: Use precise pixel calculations for alignment
3. **Events**: Later controls capture clicks (overlay before underlying)
4. **Icons**: Unicode works, but PNG gives more design control
5. **Size**: 24x24 is a good standard for icon buttons
6. **Margins**: Leave 3-4px padding from edges

## Common Pitfalls

❌ **Don't**: Create overlay before the underlying control
✅ **Do**: Create base control first, then overlay

❌ **Don't**: Use same position for both controls
✅ **Do**: Calculate overlay position relative to base

❌ **Don't**: Forget to handle resize events
✅ **Do**: Update overlay positions when window resizes

❌ **Don't**: Make overlay too large (blocks input)
✅ **Do**: Keep overlays small and to the edge

## Next Steps

1. Start with Method 1 (Simple Button Overlay)
2. Test that it works
3. Try Method 3 (Search + Clear) for practical example
4. Experiment with positioning
5. Build your own custom components

See `OVERLAY_CONTROL_STUDY_PLAN.md` for detailed research plan.
