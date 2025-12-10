# 50 Advanced AutoHotkey v2 Examples

Complex, uncommon techniques inspired by the AutoHotkey v2 codebase internals.

## Category 1: Advanced Hook System Patterns (10 examples)

### Example 1: Input Event Logger with Timestamp Queue
*Logs all keyboard/mouse events with precise timing for replay*

```ahk
#Requires AutoHotkey v2.0
#SingleInstance Force

; Event queue using circular buffer (inspired by hook thread architecture)
class InputEventLogger {
    __New(maxEvents := 10000) {
        this.events := []
        this.maxEvents := maxEvents
        this.startTime := A_TickCount
        this.position := 0

        ; Install low-level hooks
        this.kbdHook := InputHook("L0")
        this.kbdHook.OnKeyDown := ObjBindMethod(this, "LogKey")
        this.kbdHook.Start()
    }

    LogKey(ih, vk, sc) {
        event := {
            type: "key",
            vk: vk,
            sc: sc,
            timestamp: A_TickCount - this.startTime,
            modifiers: GetKeyState("Shift", "P") | (GetKeyState("Ctrl", "P") << 1) | (GetKeyState("Alt", "P") << 2)
        }

        ; Circular buffer implementation
        this.events.Push(event)
        if (this.events.Length > this.maxEvents)
            this.events.RemoveAt(1)
    }

    Replay(speed := 1.0) {
        if (this.events.Length == 0)
            return

        lastTime := 0
        for event in this.events {
            delay := (event.timestamp - lastTime) / speed
            if (delay > 0)
                Sleep(delay)

            ; Reconstruct and send key
            Send("{" Chr(event.vk) "}")
            lastTime := event.timestamp
        }
    }

    ExportToFile(filename) {
        f := FileOpen(filename, "w")
        for event in this.events {
            f.WriteLine(Format("{1},{2},{3},{4}",
                event.timestamp, event.type, event.vk, event.modifiers))
        }
        f.Close()
    }
}

; Usage
logger := InputEventLogger()
MsgBox("Recording input for 10 seconds...")
Sleep(10000)
logger.ExportToFile("input_log.csv")
MsgBox("Recorded " logger.events.Length " events. Replaying at 2x speed...")
logger.Replay(2.0)
```

---

### Example 2: Gesture Recognition System
*Detects mouse gestures using hook data analysis*

```ahk
#Requires AutoHotkey v2.0

class GestureRecognizer {
    __New() {
        this.points := []
        this.recording := false
        this.gestures := Map(
            "L", [[-1,0]],  ; Left
            "R", [[1,0]],   ; Right
            "U", [[0,-1]],  ; Up
            "D", [[0,1]],   ; Down
            "LU", [[-1,0],[0,-1]],  ; L-shape
            "RU", [[1,0],[0,-1]],   ; Reverse L
            "Z", [[1,0],[0,1],[1,0]]  ; Z-pattern
        )

        ; Hook right button for gesture recording
        this.StartMonitoring()
    }

    StartMonitoring() {
        CoordMode("Mouse", "Screen")

        ; Use SetTimer instead of hook for this example
        SetTimer(() => this.CheckRButton(), 10)
    }

    CheckRButton() {
        static wasDown := false
        isDown := GetKeyState("RButton", "P")

        if (isDown && !wasDown) {
            ; Start recording
            this.recording := true
            this.points := []
            MouseGetPos(&x, &y)
            this.points.Push([x, y])
        } else if (!isDown && wasDown) {
            ; Stop recording and recognize
            this.recording := false
            if (this.points.Length > 1)
                this.RecognizeGesture()
        } else if (isDown && this.recording) {
            ; Continue recording
            MouseGetPos(&x, &y)
            lastPoint := this.points[this.points.Length]
            if (Abs(x - lastPoint[1]) > 5 || Abs(y - lastPoint[2]) > 5)
                this.points.Push([x, y])
        }

        wasDown := isDown
    }

    RecognizeGesture() {
        ; Simplify points to directions
        directions := []
        for i, point in this.points {
            if (i == 1)
                continue

            prev := this.points[i-1]
            dx := point[1] - prev[1]
            dy := point[2] - prev[2]

            ; Quantize to 8 directions
            if (Abs(dx) > Abs(dy) * 2) {
                directions.Push([dx > 0 ? 1 : -1, 0])
            } else if (Abs(dy) > Abs(dx) * 2) {
                directions.Push([0, dy > 0 ? 1 : -1])
            }
        }

        ; Match against known gestures
        for name, pattern in this.gestures {
            if (this.MatchPattern(directions, pattern)) {
                this.OnGesture(name)
                return
            }
        }
    }

    MatchPattern(directions, pattern) {
        if (directions.Length < pattern.Length)
            return false

        ; Simple pattern matching
        for i, dir in pattern {
            if (i > directions.Length)
                return false
            if (directions[i][1] != dir[1] || directions[i][2] != dir[2])
                return false
        }
        return true
    }

    OnGesture(name) {
        ToolTip("Gesture detected: " name)
        SetTimer(() => ToolTip(), -2000)

        ; Execute gesture action
        switch name {
            case "L": Send("#{Left}")   ; Windows: Snap left
            case "R": Send("#{Right}")  ; Windows: Snap right
            case "U": Send("#{Up}")     ; Windows: Maximize
            case "D": Send("#{Down}")   ; Windows: Minimize
            case "Z": Send("^z")        ; Undo
        }
    }
}

; Usage
recognizer := GestureRecognizer()
MsgBox("Gesture recognizer active! Hold right button and draw:
L = Snap Left
R = Snap Right
U = Maximize
D = Minimize
Z = Undo")
```

---

### Example 3: Key Chord Manager
*Multi-key combinations without modifiers (like vim)*

```ahk
#Requires AutoHotkey v2.0

class ChordManager {
    __New(timeout := 1000) {
        this.timeout := timeout
        this.sequence := []
        this.lastTime := 0
        this.chords := Map()

        ; Register input hook
        this.ih := InputHook("L1 T" (timeout/1000))
        this.ih.OnChar := ObjBindMethod(this, "OnChar")
        this.ih.Start()
    }

    RegisterChord(keys, callback) {
        this.chords[keys] := callback
    }

    OnChar(ih, char) {
        currentTime := A_TickCount

        ; Reset sequence if timeout exceeded
        if (currentTime - this.lastTime > this.timeout)
            this.sequence := []

        this.sequence.Push(char)
        this.lastTime := currentTime

        ; Check for chord match
        seqStr := ""
        for ch in this.sequence
            seqStr .= ch

        if (this.chords.Has(seqStr)) {
            callback := this.chords[seqStr]
            callback()
            this.sequence := []

            ; Restart input hook
            this.ih.Stop()
            this.ih.Start()
        }

        ; Limit sequence length
        if (this.sequence.Length > 4)
            this.sequence.RemoveAt(1)
    }
}

; Usage
cm := ChordManager()

; Register vim-like chords
cm.RegisterChord("dd", () => Send("^x"))  ; dd = cut line
cm.RegisterChord("yy", () => Send("^c"))  ; yy = copy line
cm.RegisterChord("pp", () => Send("^v"))  ; pp = paste
cm.RegisterChord("gg", () => Send("^{Home}"))  ; gg = top of file
cm.RegisterChord("GG", () => Send("^{End}"))   ; GG = end of file

MsgBox("Chord manager active! Try:
dd = Cut
yy = Copy
pp = Paste
gg = Top
GG = Bottom")
```

---

### Example 4: Context-Aware Hotkey System
*Hotkeys change behavior based on application context*

```ahk
#Requires AutoHotkey v2.0

class ContextHotkeys {
    __New() {
        this.contexts := Map()
        this.currentContext := "default"

        ; Monitor active window changes
        SetTimer(() => this.UpdateContext(), 250)
    }

    RegisterContext(name, matcher, hotkeys) {
        this.contexts[name] := {
            matcher: matcher,
            hotkeys: hotkeys,
            active: false
        }
    }

    UpdateContext() {
        activeWin := WinGetTitle("A")
        activeClass := WinGetClass("A")
        activeExe := WinGetProcessName("A")

        ; Check which context matches
        for name, ctx in this.contexts {
            matches := ctx.matcher(activeWin, activeClass, activeExe)

            if (matches && !ctx.active) {
                ; Activate this context
                this.ActivateContext(name)
            } else if (!matches && ctx.active) {
                ; Deactivate this context
                this.DeactivateContext(name)
            }
        }
    }

    ActivateContext(name) {
        ctx := this.contexts[name]
        ctx.active := true

        ; Enable hotkeys for this context
        for key, callback in ctx.hotkeys {
            Hotkey(key, callback, "On")
        }

        ToolTip("Context: " name)
        SetTimer(() => ToolTip(), -1000)
    }

    DeactivateContext(name) {
        ctx := this.contexts[name]
        ctx.active := false

        ; Disable hotkeys
        for key, callback in ctx.hotkeys {
            try Hotkey(key, "Off")
        }
    }
}

; Usage
ch := ContextHotkeys()

; Browser context
ch.RegisterContext("browser",
    (title, class, exe) => (exe = "chrome.exe" || exe = "firefox.exe"),
    Map(
        "^t", () => Send("^t"),  ; New tab
        "^w", () => Send("^w"),  ; Close tab
        "^+t", () => Send("^+t")  ; Reopen closed tab
    )
)

; Code editor context
ch.RegisterContext("editor",
    (title, class, exe) => (exe = "Code.exe" || exe = "notepad++.exe"),
    Map(
        "^;", () => Send("^/"),  ; Toggle comment
        "^+f", () => Send("^+f"), ; Format document
        "F5", () => Send("{F5}")  ; Run
    )
)

MsgBox("Context-aware hotkeys active!
Switch between browser and editor to see different behaviors")
```

---

### Example 5: Macro Recorder with Playback Speed Control
*Records and plays back input with variable speed*

```ahk
#Requires AutoHotkey v2.0

class MacroRecorder {
    __New() {
        this.recording := false
        this.events := []
        this.startTime := 0
        this.playbackSpeed := 1.0

        this.RegisterHotkeys()
    }

    RegisterHotkeys() {
        Hotkey("F9", (*) => this.ToggleRecording())
        Hotkey("F10", (*) => this.Playback())
        Hotkey("F11", (*) => this.AdjustSpeed(-0.25))
        Hotkey("F12", (*) => this.AdjustSpeed(0.25))
    }

    ToggleRecording() {
        this.recording := !this.recording

        if (this.recording) {
            this.events := []
            this.startTime := A_TickCount
            this.StartCapture()
            ToolTip("Recording...")
        } else {
            this.StopCapture()
            ToolTip("Stopped. " this.events.Length " events recorded")
            SetTimer(() => ToolTip(), -2000)
        }
    }

    StartCapture() {
        ; Capture keyboard
        this.ih := InputHook("V")
        this.ih.OnKeyDown := (ih, vk, sc) => this.RecordEvent("key", vk, sc)
        this.ih.Start()

        ; Capture mouse clicks
        this.timer := SetTimer(() => this.CheckMouse(), 10)
    }

    StopCapture() {
        if (IsSet(this.ih))
            this.ih.Stop()
        if (IsSet(this.timer))
            SetTimer(this.timer, 0)
    }

    CheckMouse() {
        static lastL := false, lastR := false

        isL := GetKeyState("LButton", "P")
        isR := GetKeyState("RButton", "P")

        if (isL && !lastL)
            this.RecordEvent("lclick", 0, 0)
        if (isR && !lastR)
            this.RecordEvent("rclick", 0, 0)

        lastL := isL
        lastR := isR
    }

    RecordEvent(type, vk, sc) {
        if (!this.recording)
            return

        MouseGetPos(&mx, &my)
        this.events.Push({
            type: type,
            vk: vk,
            sc: sc,
            x: mx,
            y: my,
            time: A_TickCount - this.startTime
        })
    }

    Playback() {
        if (this.events.Length == 0) {
            MsgBox("No macro recorded!")
            return
        }

        ToolTip("Playing back at " this.playbackSpeed "x speed...")

        lastTime := 0
        for event in this.events {
            delay := (event.time - lastTime) / this.playbackSpeed
            if (delay > 0)
                Sleep(delay)

            switch event.type {
                case "key":
                    Send("{" Chr(event.vk) "}")
                case "lclick":
                    Click(event.x " " event.y)
                case "rclick":
                    Click(event.x " " event.y " Right")
            }

            lastTime := event.time
        }

        ToolTip()
    }

    AdjustSpeed(delta) {
        this.playbackSpeed := Max(0.25, Min(4.0, this.playbackSpeed + delta))
        ToolTip("Playback speed: " this.playbackSpeed "x")
        SetTimer(() => ToolTip(), -1000)
    }
}

; Usage
recorder := MacroRecorder()
MsgBox("Macro Recorder Ready!
F9  = Start/Stop Recording
F10 = Playback
F11 = Slower
F12 = Faster")
```

---

### Example 6: Application-Specific Input Blocker
*Blocks certain keys/mouse in specific applications*

```ahk
#Requires AutoHotkey v2.0

class InputBlocker {
    __New() {
        this.rules := Map()
        this.active := Map()

        SetTimer(() => this.UpdateRules(), 500)
    }

    BlockInApp(exeName, keys) {
        if (!this.rules.Has(exeName))
            this.rules[exeName] := []

        for key in keys
            this.rules[exeName].Push(key)
    }

    UpdateRules() {
        exe := WinGetProcessName("A")

        ; Deactivate old rules
        for oldExe, _ in this.active {
            if (oldExe != exe) {
                this.DeactivateRules(oldExe)
            }
        }

        ; Activate new rules
        if (this.rules.Has(exe) && !this.active.Has(exe)) {
            this.ActivateRules(exe)
        }
    }

    ActivateRules(exe) {
        this.active[exe] := true

        for key in this.rules[exe] {
            try {
                Hotkey(key, (*) => this.BlockKey(key), "On")
            }
        }
    }

    DeactivateRules(exe) {
        this.active.Delete(exe)

        for key in this.rules[exe] {
            try Hotkey(key, "Off")
        }
    }

    BlockKey(key) {
        ; Key is blocked - do nothing or show warning
        ToolTip("Key " key " blocked in this application")
        SetTimer(() => ToolTip(), -500)
    }
}

; Usage
blocker := InputBlocker()

; Block Alt+F4 in critical applications
blocker.BlockInApp("notepad.exe", ["!F4", "^w"])

; Block gaming keys in work apps
blocker.BlockInApp("EXCEL.EXE", ["w", "a", "s", "d", "Space"])

; Block dangerous keys in remote desktop
blocker.BlockInApp("mstsc.exe", ["#d", "#l", "^!Delete"])

MsgBox("Input blocker active!
Alt+F4 blocked in Notepad
WASD blocked in Excel
Win keys blocked in RDP")
```

---

### Example 7: Keystroke Heatmap Generator
*Visualizes keyboard usage patterns*

```ahk
#Requires AutoHotkey v2.0

class KeystrokeHeatmap {
    __New() {
        this.counts := Map()
        this.totalKeys := 0
        this.gui := ""

        ; Start logging
        this.ih := InputHook("L0")
        this.ih.OnKeyDown := (ih, vk, sc) => this.LogKey(vk)
        this.ih.Start()

        ; Update display periodically
        SetTimer(() => this.UpdateDisplay(), 5000)
    }

    LogKey(vk) {
        key := Chr(vk)
        this.counts[key] := (this.counts.Has(key) ? this.counts[key] : 0) + 1
        this.totalKeys++
    }

    UpdateDisplay() {
        if (this.totalKeys == 0)
            return

        ; Create or update GUI
        if (!this.gui) {
            this.gui := Gui("+AlwaysOnTop +ToolWindow", "Keystroke Heatmap")
            this.gui.SetFont("s8", "Consolas")
            this.edit := this.gui.Add("Edit", "r30 w400 ReadOnly")
            this.gui.Show("NoActivate")
        }

        ; Sort keys by frequency
        sorted := []
        for key, count in this.counts
            sorted.Push({key: key, count: count, pct: count / this.totalKeys * 100})

        sorted := this.SortByCount(sorted)

        ; Build heatmap
        output := "Key Frequency Heatmap`n"
        output .= "Total: " this.totalKeys " keystrokes`n`n"

        for i, item in sorted {
            if (i > 20)  ; Top 20 only
                break

            bar := this.MakeBar(item.pct)
            output .= Format("{1,-3} {2,-20} {3,6.2f}% ({4})`n",
                item.key, bar, item.pct, item.count)
        }

        this.edit.Value := output
    }

    MakeBar(pct) {
        length := Round(pct)
        bar := ""
        Loop Min(20, length)
            bar .= "█"
        return bar
    }

    SortByCount(arr) {
        ; Bubble sort (simple for demo)
        n := arr.Length
        Loop n - 1 {
            i := A_Index
            Loop n - i {
                j := A_Index
                if (arr[j].count < arr[j+1].count) {
                    temp := arr[j]
                    arr[j] := arr[j+1]
                    arr[j+1] := temp
                }
            }
        }
        return arr
    }
}

; Usage
heatmap := KeystrokeHeatmap()
MsgBox("Keystroke heatmap started!
Type away and watch the statistics update every 5 seconds.")
```

---

### Example 8: Smart Caps Lock (Context-Based Toggle)
*Caps Lock behavior changes based on what you're typing*

```ahk
#Requires AutoHotkey v2.0

class SmartCapsLock {
    __New() {
        this.buffer := ""
        this.autoCapitalize := true

        ; Replace Caps Lock with smart behavior
        Hotkey("CapsLock", (*) => this.ToggleMode())

        ; Monitor typing for auto-caps
        this.ih := InputHook("L0")
        this.ih.OnChar := (ih, char) => this.OnChar(char)
        this.ih.Start()
    }

    ToggleMode() {
        this.autoCapitalize := !this.autoCapitalize
        ToolTip("Smart Caps: " (this.autoCapitalize ? "ON" : "OFF"))
        SetTimer(() => ToolTip(), -1000)
    }

    OnChar(char) {
        this.buffer .= char

        ; Keep buffer size manageable
        if (StrLen(this.buffer) > 50)
            this.buffer := SubStr(this.buffer, -49)

        if (!this.autoCapitalize)
            return

        ; Check if we should capitalize
        if (this.ShouldCapitalize()) {
            ; Backspace and replace with uppercase
            Send("{Backspace}" StrUpper(char))
        }
    }

    ShouldCapitalize() {
        ; Capitalize after period
        if (RegExMatch(this.buffer, "\.\s+\w$"))
            return true

        ; Capitalize start of sentence
        if (RegExMatch(this.buffer, "^[A-Z][^.!?]*[.!?]\s+\w$"))
            return true

        ; Capitalize "I"
        if (RegExMatch(this.buffer, "\si$"))
            return true

        return false
    }
}

; Usage
smart := SmartCapsLock()
MsgBox("Smart Caps Lock active!
- Auto-capitalizes after periods
- Auto-capitalizes 'I'
- Press Caps Lock to toggle

Try typing: 'hello. this is a test. i am typing.'")
```

---

### Example 9: Mouse Jiggler with Natural Movement
*Prevents screensaver with realistic mouse patterns*

```ahk
#Requires AutoHotkey v2.0

class MouseJiggler {
    __New(interval := 60000) {
        this.interval := interval
        this.active := false
        this.patterns := []

        ; Create natural movement patterns
        this.InitPatterns()

        Hotkey("F8", (*) => this.Toggle())
    }

    InitPatterns() {
        ; Small circular motion
        this.patterns.Push([
            [5, 0], [4, 3], [0, 5], [-4, 3],
            [-5, 0], [-4, -3], [0, -5], [4, -3]
        ])

        ; Figure-8 pattern
        this.patterns.Push([
            [10, 0], [7, 7], [0, 10], [-7, 7],
            [-10, 0], [-7, -7], [0, -10], [7, -7]
        ])

        ; Random walk
        this.patterns.Push("random")
    }

    Toggle() {
        this.active := !this.active

        if (this.active) {
            this.Jiggle()
            ToolTip("Mouse Jiggler: ON")
        } else {
            ToolTip("Mouse Jiggler: OFF")
        }

        SetTimer(() => ToolTip(), -1000)
    }

    Jiggle() {
        if (!this.active)
            return

        ; Choose random pattern
        pattern := this.patterns[Random(1, this.patterns.Length)]

        MouseGetPos(&startX, &startY)

        if (pattern = "random") {
            ; Random small movements
            Loop 10 {
                dx := Random(-20, 20)
                dy := Random(-20, 20)
                MouseMove(startX + dx, startY + dy, 10)
                Sleep(50)
            }
        } else {
            ; Predefined pattern
            for move in pattern {
                MouseMove(startX + move[1], startY + move[2], 5)
                Sleep(30)
            }
        }

        ; Return to start
        MouseMove(startX, startY, 5)

        ; Schedule next jiggle
        SetTimer(() => this.Jiggle(), -this.interval)
    }
}

; Usage
jiggler := MouseJiggler(30000)  ; Every 30 seconds
MsgBox("Mouse Jiggler ready!
Press F8 to toggle on/off
Will move mouse naturally every 30 seconds")
```

---

### Example 10: Keyboard Mapper with Layers
*Implement keyboard layers like QMK firmware*

```ahk
#Requires AutoHotkey v2.0

class LayeredKeyboard {
    __New() {
        this.currentLayer := 0
        this.layers := []
        this.holdingLayer := false

        ; Define base layer (layer 0)
        this.AddLayer(Map(
            "a", "a", "s", "s", "d", "d", "f", "f",
            "j", "j", "k", "k", "l", "l", ";", ";"
        ))

        ; Define function layer (layer 1) - activated by holding Space
        this.AddLayer(Map(
            "a", "{Home}",
            "s", "{End}",
            "d", "{PgUp}",
            "f", "{PgDn}",
            "j", "{Left}",
            "k", "{Down}",
            "l", "{Up}",
            ";", "{Right}"
        ))

        ; Register Space as layer key
        Hotkey("Space", (*) => this.LayerDown(1))
        Hotkey("Space Up", (*) => this.LayerUp())

        ; Register all mapped keys
        this.RegisterKeys()
    }

    AddLayer(mappings) {
        this.layers.Push(mappings)
    }

    RegisterKeys() {
        ; Get all unique keys from all layers
        allKeys := Map()
        for layer in this.layers {
            for key, _ in layer
                allKeys[key] := true
        }

        ; Register hotkeys for each key
        for key, _ in allKeys {
            Hotkey(key, ObjBindMethod(this, "HandleKey", key))
        }
    }

    LayerDown(layer) {
        this.currentLayer := layer
        this.holdingLayer := true
    }

    LayerUp() {
        this.currentLayer := 0
        this.holdingLayer := false
    }

    HandleKey(key, *) {
        layer := this.layers[this.currentLayer + 1]

        if (layer.Has(key)) {
            mapping := layer[key]
            if (SubStr(mapping, 1, 1) = "{") {
                ; Special key
                Send(mapping)
            } else {
                ; Regular character
                SendText(mapping)
            }
        }
    }
}

; Usage
keyboard := LayeredKeyboard()
MsgBox("Layered keyboard active!

Base layer: Normal keys
Hold Space +
  j/k/l/; = Arrow keys
  a/s = Home/End
  d/f = PgUp/PgDn

Try it in a text editor!")
```

I'll continue with the remaining 40 examples in the next file...

---

This is part 1 of 5. Would you like me to continue generating the remaining 40 examples? They'll cover:
- Quasi-Threading & Timing (10 examples)
- Debugger Integration (5 examples)
- Overlay Controls & Advanced GUI (10 examples)
- Memory & Process Manipulation (5 examples)
- WinAPI Integration (5 examples)
- Event System & Callbacks (5 examples)
