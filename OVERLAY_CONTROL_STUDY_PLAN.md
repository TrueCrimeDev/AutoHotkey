# Control Overlay Study Plan - AutoHotkey v2

## Goal
Create buttons that hover over edit fields (e.g., search icon button inside search box, run button over input field) that are always visible.

## Research Phases

### Phase 1: Fundamentals (2-3 hours)

**1.1 Study AHK v2 GUI Basics**
- [ ] Read AutoHotkey v2 GUI documentation
- [ ] Understand `Gui()` object creation
- [ ] Learn `Add()` method for controls
- [ ] Study control options (x, y, w, h)

**Resources:**
- Official docs: https://www.autohotkey.com/docs/v2/lib/Gui.htm
- Control reference: https://www.autohotkey.com/docs/v2/lib/GuiControls.htm

**Key Questions:**
- How are controls positioned? (absolute vs relative)
- What coordinate system is used? (pixels from top-left)
- Can controls have negative coordinates?

**Experiment 1.1:**
```ahk
; Create a simple GUI with positioned controls
MyGui := Gui()
Edit1 := MyGui.Add("Edit", "x10 y10 w200 h30", "Test")
Button1 := MyGui.Add("Button", "x50 y15 w80 h20", "Click")
MyGui.Show()
```

**Expected Learning:**
- Whether Button1 appears above or below Edit1
- If controls can overlap
- Default z-order behavior

---

**1.2 Study Control Z-Order**
- [ ] Research how AHK determines which control is "on top"
- [ ] Test if creation order affects layering
- [ ] Look for z-index or similar properties

**Key Questions:**
- Is z-order determined by creation order?
- Can z-order be changed after creation?
- Do some control types always appear above others?

**Experiment 1.2:**
```ahk
; Test z-order with overlapping controls
MyGui := Gui()
Button1 := MyGui.Add("Button", "x10 y10 w100 h40", "Bottom")
Button2 := MyGui.Add("Button", "x30 y20 w100 h40", "Top")
MyGui.Show()

; Hypothesis: Button2 should appear on top (created last)
```

**Expected Learning:**
- Confirmation of z-order rules
- Whether controls can be reordered

---

**1.3 Study Transparent Backgrounds**
- [ ] Research `BackgroundTrans` option
- [ ] Test transparent backgrounds on buttons
- [ ] Understand how transparency affects click-through

**Key Questions:**
- Can buttons have transparent backgrounds?
- Do transparent areas still receive clicks?
- Can images with alpha channel be used?

**Experiment 1.3:**
```ahk
; Test transparent button over edit
MyGui := Gui()
MyGui.BackColor := "White"
Edit1 := MyGui.Add("Edit", "x10 y10 w200 h30", "Search...")
Button1 := MyGui.Add("Button", "x180 y13 w24 h24", "🔍")

; Try to make button background transparent
; Research: Does BackgroundTrans work on controls?
MyGui.Show()
```

---

### Phase 2: Advanced Techniques (3-4 hours)

**2.1 Picture Control Method**
- [ ] Study using Picture controls as clickable overlays
- [ ] Test PNG images with transparency
- [ ] Handle click events on Picture controls

**Key Questions:**
- Can Picture controls trigger events?
- Do they support transparency better than buttons?
- Can they display icons/symbols?

**Experiment 2.1:**
```ahk
; Use Picture as button overlay
MyGui := Gui()
Edit1 := MyGui.Add("Edit", "x10 y10 w200 h30")
; Create search icon PNG with transparency
Pic1 := MyGui.Add("Picture", "x180 y13 w24 h24", "search-icon.png")

; Can we make it clickable?
Pic1.OnEvent("Click", SearchClick)

SearchClick(GuiCtrlObj, Info) {
    MsgBox("Search clicked!")
}

MyGui.Show()
```

**Expected Learning:**
- Whether Picture controls can be clickable
- How to create/use transparent icon images
- Event handling on Picture controls

---

**2.2 Text Control with Symbols**
- [ ] Test using Text controls for icon overlays
- [ ] Research Unicode symbols (🔍, ▶️, ✕, etc.)
- [ ] Make Text controls clickable

**Key Questions:**
- Can Text controls display Unicode symbols reliably?
- Are they clickable?
- Can they have custom cursors (hand pointer)?

**Experiment 2.2:**
```ahk
; Use Text control as icon button
MyGui := Gui()
Edit1 := MyGui.Add("Edit", "x10 y10 w200 h30")
IconBtn := MyGui.Add("Text", "x180 y13 w24 h24 Center", "🔍")

; Make it look clickable
IconBtn.OnEvent("Click", SearchClick)
IconBtn.SetFont("s14")  ; Larger icon

SearchClick(GuiCtrlObj, Info) {
    MsgBox("Search icon clicked!")
}

MyGui.Show()
```

---

**2.3 Custom Draw Method**
- [ ] Research GDI+ drawing on GUI
- [ ] Study OnPaint events or similar
- [ ] Draw custom shapes/icons directly

**Key Questions:**
- Can we draw directly on the GUI canvas?
- Is there an OnPaint event for custom drawing?
- Can drawn elements be interactive?

**Research Topics:**
- GDI+ in AutoHotkey v2
- Custom painting/drawing
- Hit testing for drawn elements

---

**2.4 Absolute Positioning Technique**
- [ ] Use absolute positioning to place button precisely
- [ ] Calculate positions relative to edit field
- [ ] Handle window resizing

**Experiment 2.4:**
```ahk
; Precise positioning
MyGui := Gui()
Edit1 := MyGui.Add("Edit", "x10 y10 w200 h30 vSearchBox")

; Get edit position and size
Edit1.GetPos(&ex, &ey, &ew, &eh)

; Position button at right edge, inside edit
ButtonX := ex + ew - 30  ; 30px from right edge
ButtonY := ey + 3        ; 3px from top
Button1 := MyGui.Add("Button", "x" ButtonX " y" ButtonY " w24 h24", "🔍")

MyGui.Show()
```

---

### Phase 3: Common Patterns (2-3 hours)

**3.1 Search Box with Icon**
Goal: Create a search box with magnifying glass icon on the right

**Implementation Checklist:**
- [ ] Edit control for search input
- [ ] Icon/button positioned at right edge
- [ ] Icon triggers search function
- [ ] Visual feedback (hover state if possible)
- [ ] Clear button (X) when text exists

**Code Template:**
```ahk
; Search box component
CreateSearchBox(ParentGui, x, y, w, h) {
    ; Main edit field
    SearchEdit := ParentGui.Add("Edit", "x" x " y" y " w" w " h" h)

    ; Search icon button (overlaid on right)
    IconX := x + w - 28
    IconY := y + 2
    SearchIcon := ParentGui.Add("Button", "x" IconX " y" IconY " w24 h24", "🔍")

    ; Clear button (X) - appears when text exists
    ClearX := x + w - 52
    ClearBtn := ParentGui.Add("Button", "x" ClearX " y" IconY " w24 h24 Hidden", "✕")

    ; Events
    SearchIcon.OnEvent("Click", (*) => DoSearch(SearchEdit.Value))
    ClearBtn.OnEvent("Click", (*) => ClearSearch(SearchEdit, ClearBtn))
    SearchEdit.OnEvent("Change", (*) => ToggleClearBtn(SearchEdit, ClearBtn))

    return {Edit: SearchEdit, Icon: SearchIcon, Clear: ClearBtn}
}

DoSearch(Query) {
    MsgBox("Searching for: " Query)
}

ClearSearch(EditCtrl, ClearBtn) {
    EditCtrl.Value := ""
    ClearBtn.Visible := false
}

ToggleClearBtn(EditCtrl, ClearBtn) {
    ClearBtn.Visible := (EditCtrl.Value != "")
}
```

---

**3.2 Input Field with Run Button**
Goal: Text input with "▶" run button overlay

**Implementation Checklist:**
- [ ] Edit control for command/input
- [ ] Run button (▶) on right side
- [ ] Enter key also triggers run
- [ ] Visual indication when processing

**Code Template:**
```ahk
; Command input with run button
CreateCommandBox(ParentGui, x, y, w, h) {
    CmdEdit := ParentGui.Add("Edit", "x" x " y" y " w" w " h" h)

    RunX := x + w - 28
    RunY := y + 2
    RunBtn := ParentGui.Add("Button", "x" RunX " y" RunY " w24 h24", "▶")

    RunBtn.OnEvent("Click", (*) => ExecuteCommand(CmdEdit.Value))
    CmdEdit.OnEvent("Change", (*) => EnableRunBtn(CmdEdit, RunBtn))

    ; Enter key executes
    CmdEdit.OnEvent("KeyPress", (Ctrl, Key) => {
        if (Key = 13) {  ; Enter
            ExecuteCommand(Ctrl.Value)
        }
    })

    return {Edit: CmdEdit, Run: RunBtn}
}

ExecuteCommand(Cmd) {
    MsgBox("Executing: " Cmd)
    ; Your command execution logic here
}

EnableRunBtn(EditCtrl, RunBtn) {
    RunBtn.Enabled := (EditCtrl.Value != "")
}
```

---

**3.3 Password Field with Show/Hide Toggle**
Goal: Password field with eye icon to toggle visibility

**Implementation Checklist:**
- [ ] Edit control with password option
- [ ] Eye icon button overlay
- [ ] Toggle between password and normal mode
- [ ] Icon changes state (open/closed eye)

**Code Template:**
```ahk
; Password field with visibility toggle
CreatePasswordBox(ParentGui, x, y, w, h) {
    ; Start as password field
    PwdEdit := ParentGui.Add("Edit", "x" x " y" y " w" w " h" h " Password")

    ToggleX := x + w - 28
    ToggleY := y + 2
    EyeBtn := ParentGui.Add("Button", "x" ToggleX " y" ToggleY " w24 h24", "👁")

    IsVisible := false

    EyeBtn.OnEvent("Click", (*) => {
        global IsVisible
        IsVisible := !IsVisible

        ; Save current value
        CurrentValue := PwdEdit.Value

        ; Recreate edit with/without password option
        PwdEdit.Opt(IsVisible ? "-Password" : "+Password")
        PwdEdit.Value := CurrentValue

        ; Update icon
        EyeBtn.Text := IsVisible ? "👁" : "👁‍🗨"
    })

    return {Edit: PwdEdit, Toggle: EyeBtn}
}
```

---

### Phase 4: Refinement (2-3 hours)

**4.1 Visual Polish**
- [ ] Remove button borders (Flat style)
- [ ] Custom background colors
- [ ] Hover effects
- [ ] Focus indicators

**Research Topics:**
- Control styles in AHK v2
- Custom control appearance
- Mouse hover detection
- Focus events

**Experiment 4.1:**
```ahk
; Flat, borderless button
MyGui := Gui()
Edit1 := MyGui.Add("Edit", "x10 y10 w200 h30")
IconBtn := MyGui.Add("Button", "x180 y13 w24 h24", "🔍")

; Try different styles
; Research: What options make buttons flat?
; Possible: -Border, Flat, etc.

MyGui.Show()
```

---

**4.2 Responsive Sizing**
- [ ] Handle window resizing
- [ ] Adjust overlay positions dynamically
- [ ] Maintain proper alignment

**Key Questions:**
- How to detect window resize in AHK v2?
- Can controls auto-resize?
- How to recalculate overlay positions?

**Experiment 4.2:**
```ahk
; Resizable GUI with maintained overlays
MyGui := Gui("+Resize")
SearchBox := CreateSearchBox(MyGui, 10, 10, 300, 30)

MyGui.OnEvent("Size", AdjustLayout)

AdjustLayout(GuiObj, MinMax, Width, Height) {
    ; Recalculate positions based on new size
    NewWidth := Width - 20
    SearchBox.Edit.Move(10, 10, NewWidth, 30)

    ; Reposition icon
    IconX := 10 + NewWidth - 28
    SearchBox.Icon.Move(IconX, 12)
}

MyGui.Show()
```

---

**4.3 Click-Through Transparent Areas**
- [ ] Make only icon clickable, not full button
- [ ] Click-through transparent backgrounds
- [ ] Proper hit testing

**Research Topics:**
- WS_EX_TRANSPARENT window style
- Custom hit testing
- Region-based controls

---

**4.4 Accessibility**
- [ ] Tab order (skip overlay buttons?)
- [ ] Keyboard shortcuts
- [ ] Screen reader compatibility

**Considerations:**
- Should overlay buttons be in tab order?
- Keyboard alternatives (e.g., Ctrl+Enter for run)
- ARIA labels or equivalents

---

### Phase 5: Documentation (1-2 hours)

**5.1 Create Pattern Library**
- [ ] Document each overlay pattern
- [ ] Include code examples
- [ ] Add screenshots/mockups
- [ ] List pros/cons of each approach

**5.2 Best Practices Guide**
- [ ] When to use overlays vs. separate buttons
- [ ] Performance considerations
- [ ] UX guidelines
- [ ] Common pitfalls

**5.3 Reusable Components**
- [ ] Create function library
- [ ] Parameterized component creators
- [ ] Example integration code

---

## Key Research Questions

### Critical Questions to Answer:
1. **Z-Order Control**
   - Can we control which control appears on top?
   - Is it purely creation order or can we modify it?
   - Do different control types have priority?

2. **Transparency**
   - Can buttons have transparent backgrounds in AHK v2?
   - Do Picture controls handle transparency better?
   - Can we use alpha-channel PNGs?

3. **Click Handling**
   - When controls overlap, which receives the click?
   - Can we make overlays clickable but not block underlying control?
   - Is there click-through for transparent areas?

4. **Positioning Precision**
   - What's the smallest unit (pixels)?
   - Can we position controls outside parent bounds?
   - How to handle DPI scaling?

5. **Performance**
   - Does having many overlaid controls impact performance?
   - Are there limits to control count?
   - Redraw efficiency with overlapping controls?

---

## Experiments to Run

### Experiment Suite A: Basic Overlays
```ahk
; A1: Two buttons, one overlapping
; A2: Button over edit field
; A3: Picture over edit field
; A4: Text over edit field
; A5: Multiple overlays (search + clear buttons)
```

### Experiment Suite B: Transparency
```ahk
; B1: BackgroundTrans on buttons
; B2: PNG images with alpha channel
; B3: WS_EX_TRANSPARENT style
; B4: Region-based transparency
```

### Experiment Suite C: Interactivity
```ahk
; C1: Click events on overlays
; C2: Hover effects
; C3: Focus management
; C4: Tab order testing
```

### Experiment Suite D: Real-World Patterns
```ahk
; D1: Modern search box (icon + clear)
; D2: Command palette (run button)
; D3: Password visibility toggle
; D4: Dropdown with custom arrow
; D5: Numeric spinner with +/- buttons
```

---

## Success Criteria

By end of study, should be able to:
- ✅ Create search box with embedded icon button
- ✅ Create run button overlay on input field
- ✅ Handle clicks on overlay buttons correctly
- ✅ Make overlays visually polished (no borders, proper alignment)
- ✅ Create reusable component functions
- ✅ Document best practices and patterns

---

## Timeline

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| Phase 1: Fundamentals | 2-3 hours | Understanding of basics, initial experiments |
| Phase 2: Advanced Techniques | 3-4 hours | Working overlay prototypes |
| Phase 3: Common Patterns | 2-3 hours | 3+ reusable patterns implemented |
| Phase 4: Refinement | 2-3 hours | Polished, production-ready components |
| Phase 5: Documentation | 1-2 hours | Complete pattern library + guide |
| **Total** | **10-15 hours** | **Complete overlay control system** |

---

## Resources to Consult

### Official Documentation
- AutoHotkey v2 Docs: https://www.autohotkey.com/docs/v2/
- Gui Class: https://www.autohotkey.com/docs/v2/lib/Gui.htm
- Control Types: https://www.autohotkey.com/docs/v2/lib/GuiControls.htm

### Community Resources
- AutoHotkey Forums: https://www.autohotkey.com/boards/
- Search for: "overlay controls", "button over edit", "custom GUI"

### Similar Solutions (for inspiration)
- Web search boxes with icons
- Windows 10/11 search bars
- Material Design input fields
- Bootstrap form components

---

## Next Steps

1. **Start with Phase 1, Experiment 1.1** - Create basic overlapping controls
2. **Document findings** after each experiment
3. **Take screenshots** of successful overlay patterns
4. **Iterate on designs** based on learnings
5. **Build component library** with best patterns

---

## Notes Section

Use this space to document discoveries:

### Discoveries:
-

### Challenges:
-

### Solutions Found:
-

### Questions for Forums:
-
