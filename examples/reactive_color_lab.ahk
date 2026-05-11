/*
    Reactive Color Lab — Dark Mode GUI with Pattern-Driven Architecture
    ────────────────────────────────────────────────────────────────────
    Demonstrates how esoteric patterns (Signals, Computed, Effect,
    Result monad, OOP) drive a real GUI with zero manual UI syncing.

    Architecture:
      Signal(R,G,B) ──► Computed(hex,hsl,luma,comp) ──► Effect(update GUI)
      Slider.Change ──► Signal.Set ──► auto-propagation ──► GUI redraws itself

    Run: bin\AutoHotkey64.exe examples\reactive_color_lab.ahk
*/
#Requires AutoHotkey v2.1-alpha.26

; ═══════════════════════════════════════════════════════════════
; REACTIVE PRIMITIVES — the engine behind zero-glue UI updates
; ═══════════════════════════════════════════════════════════════

class Rx {
    static _observer := ""

    ; Signal: a mutable cell that notifies observers on change
    ; Note: get/set accept (_) because AHK passes the owning object
    ; as an implicit first arg when calling obj.Get() / obj.Set(v)
    static Signal(initial) {
        val := initial
        subs := Map()
        get := (_) {
            if Rx._observer != ""
                subs[Rx._observer] := true
            return val
        }
        set := (_, v) {
            val := v
            for fn, _v in subs
                fn()
        }
        return {Get: get, Set: set}
    }

    ; Computed: derived value that auto-tracks its dependencies
    static Computed(fn) {
        val := ""
        subs := Map()
        recompute := () {
            prev := Rx._observer
            Rx._observer := recompute
            val := fn()
            Rx._observer := prev
            for sub, _v in subs
                sub()
        }
        recompute()
        return {Get: (_) {
            if Rx._observer != ""
                subs[Rx._observer] := true
            return val
        }}
    }

    ; Effect: side effect that re-runs when dependencies change
    static Effect(fn) {
        run := () {
            prev := Rx._observer
            Rx._observer := run
            fn()
            Rx._observer := prev
        }
        run()
    }
}

; ═══════════════════════════════════════════════════════════════
; RESULT MONAD — safe clipboard operations
; ═══════════════════════════════════════════════════════════════

class Outcome {
    __New(ok, val) {
        this._ok := ok
        this._val := val
    }
    Match(onOk, onErr) => this._ok ? onOk(this._val) : onErr(this._val)
}
Pass(v) => Outcome(true, v)
Fail(v) => Outcome(false, v)

TryCopy(text) {
    try {
        A_Clipboard := text
        return Pass(text)
    } catch as e {
        return Fail(e.Message)
    }
}

; ═══════════════════════════════════════════════════════════════
; COLOR MATH
; ═══════════════════════════════════════════════════════════════

RgbToHsl(r, g, b) {
    r /= 255.0, g /= 255.0, b /= 255.0
    cmax := Max(r, g, b), cmin := Min(r, g, b)
    d := cmax - cmin, l := (cmax + cmin) / 2
    if d = 0
        return {h: 0, s: 0, l: Round(l * 100)}
    s := d / (1 - Abs(2 * l - 1))
    if cmax = r
        h := 60 * Mod((g - b) / d + 6, 6)
    else if cmax = g
        h := 60 * ((b - r) / d + 2)
    else
        h := 60 * ((r - g) / d + 4)
    return {h: Round(h), s: Round(s * 100), l: Round(l * 100)}
}

RelLuminance(r, g, b) {
    _lin(c) {
        c /= 255.0
        return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
    }
    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)
}

; ═══════════════════════════════════════════════════════════════
; DARK MODE HELPERS
; ═══════════════════════════════════════════════════════════════

; Enable dark mode for common controls (Win 10 1903+, undocumented)
try {
    uxtheme := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr")
    if pSetMode := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 135, "Ptr")
        DllCall(pSetMode, "Int", 2)
}

; Dark title bar via DWM
DarkTitleBar(hwnd) {
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 20, "UInt*", 1, "UInt", 4)
}

; ═══════════════════════════════════════════════════════════════
; THEME — design system from CLAUDE.md
; ═══════════════════════════════════════════════════════════════

class T {
    ; Backgrounds
    static bg      := "0f0f0f"
    static surface := "141414"
    static card    := "121212"
    static raised  := "1a1a1a"
    ; Borders
    static border  := "303030"
    ; Accent
    static accent  := "5B9FEF"
    static green   := "7BC96F"
    static amber   := "F59E42"
    static red     := "DC3545"
    static purple  := "A855F7"
    static cyan    := "22D3EE"
    ; Text
    static bright  := "FFFFFF"
    static mid     := "A0A0A0"
    static dim     := "606060"
    ; COLORREF (0x00BBGGRR) for GDI SetTextColor
    static CR(hex) {
        return Integer("0x" SubStr(hex, 5, 2) SubStr(hex, 3, 2) SubStr(hex, 1, 2))
    }
}

; ═══════════════════════════════════════════════════════════════
; THE APP — OOP class wiring Rx signals to dark-mode GUI
; ═══════════════════════════════════════════════════════════════

class ColorLab {
    __New() {
        self := this    ; capture for nested closures (this can't be captured)

        ; ── Reactive state: three signals are the ONLY source of truth ──
        this.r := Rx.Signal(91)
        this.g := Rx.Signal(159)
        this.b := Rx.Signal(239)

        ; ── Build GUI ──
        win := Gui("-MaximizeBox", "Reactive Color Lab")
        this.win := win
        win.BackColor := T.bg
        win.MarginX := 0, win.MarginY := 0
        DarkTitleBar(win.Hwnd)

        ; Per-control text color map for WM_CTLCOLORSTATIC
        colors := Map()
        brush := DllCall("CreateSolidBrush", "UInt", T.CR(T.bg), "Ptr")
        surfBrush := DllCall("CreateSolidBrush", "UInt", T.CR(T.card), "Ptr")
        this._surfCtrls := Map()

        ; Gui.OnMessage callback: (GuiObj, wParam, lParam, Msg)
        win.OnMessage(0x0138, (_gui, wp, lp, *) {
            cr := colors.Has(lp) ? colors[lp] : T.CR(T.bright)
            DllCall("SetTextColor", "Ptr", wp, "UInt", cr)
            if self._surfCtrls.Has(lp) {
                DllCall("SetBkColor", "Ptr", wp, "UInt", T.CR(T.card))
                return surfBrush
            }
            DllCall("SetBkMode", "Ptr", wp, "UInt", 1)
            return brush
        })

        ; Also handle Edit controls (WM_CTLCOLOREDIT)
        editBrush := DllCall("CreateSolidBrush", "UInt", T.CR(T.raised), "Ptr")
        win.OnMessage(0x0133, (_gui, wp, lp, *) {
            DllCall("SetTextColor", "Ptr", wp, "UInt", T.CR(T.bright))
            DllCall("SetBkColor", "Ptr", wp, "UInt", T.CR(T.raised))
            return editBrush
        })

        ; ── MAIN COLOR SWATCH (child Gui) ──
        swatch := Gui("+Parent" win.Hwnd " -Caption")
        swatch.BackColor := T.accent
        this.swatch := swatch

        ; ── SLIDER SECTION ──
        ; Channel labels — colored per channel
        win.SetFont("s13 Bold", "Segoe UI")
        rLbl := win.Add("Text", "x195 y32 w18", "R")
        gLbl := win.Add("Text", "x195 y87 w18", "G")
        bLbl := win.Add("Text", "x195 y142 w18", "B")
        colors[rLbl.Hwnd] := T.CR(T.red)
        colors[gLbl.Hwnd] := T.CR(T.green)
        colors[bLbl.Hwnd] := T.CR(T.cyan)

        ; Sliders
        slR := win.Add("Slider", "x218 y28 w225 Range0-255 NoTicks ToolTip", 91)
        slG := win.Add("Slider", "x218 y83 w225 Range0-255 NoTicks ToolTip", 159)
        slB := win.Add("Slider", "x218 y138 w225 Range0-255 NoTicks ToolTip", 239)
        this.slR := slR, this.slG := slG, this.slB := slB

        ; Numeric readouts (monospace)
        win.SetFont("s11", "JetBrains Mono")
        rVal := win.Add("Text", "x452 y32 w55 Right", "91")
        gVal := win.Add("Text", "x452 y87 w55 Right", "159")
        bVal := win.Add("Text", "x452 y142 w55 Right", "239")
        this.rVal := rVal, this.gVal := gVal, this.bVal := bVal

        ; ── HEX DISPLAY (accent, large) ──
        win.SetFont("s18 Bold", "JetBrains Mono")
        hexDisp := win.Add("Text", "x25 y175 w145 Center", "#5B9FEF")
        colors[hexDisp.Hwnd] := T.CR(T.accent)
        this.hexDisp := hexDisp

        ; ── INVERT SWATCH ──
        win.SetFont("s9", "Segoe UI")
        invLabel := win.Add("Text", "x25 y208 w145 Center", "invert")
        colors[invLabel.Hwnd] := T.CR(T.dim)

        invSwatch := Gui("+Parent" win.Hwnd " -Caption")
        invSwatch.BackColor := "A46010"
        this.invSwatch := invSwatch

        win.SetFont("s10", "JetBrains Mono")
        invHex := win.Add("Text", "x25 y285 w145 Center", "#A46010")
        colors[invHex.Hwnd] := T.CR(T.mid)
        this.invHex := invHex

        ; ── INFO PANEL ──
        ; Separator
        win.Add("Text", "x185 y180 w325 h1 Background" T.border)

        ; Labels (dim)
        win.SetFont("s10", "Segoe UI")
        for pair in [["Hex", 198], ["RGB", 224], ["HSL", 250], ["Luma", 276]] {
            lbl := win.Add("Text", "x195 y" pair[2] " w55", pair[1])
            colors[lbl.Hwnd] := T.CR(T.dim)
        }

        ; Values (white, monospace)
        win.SetFont("s10", "JetBrains Mono")
        hexInfo  := win.Add("Text", "x260 y198 w250", "")
        rgbInfo  := win.Add("Text", "x260 y224 w250", "")
        hslInfo  := win.Add("Text", "x260 y250 w250", "")
        lumaInfo := win.Add("Text", "x260 y276 w250", "")
        this.hexInfo := hexInfo, this.rgbInfo := rgbInfo
        this.hslInfo := hslInfo, this.lumaInfo := lumaInfo

        ; WCAG contrast badge
        wcagLabel := win.Add("Text", "x195 y303 w55", "WCAG")
        colors[wcagLabel.Hwnd] := T.CR(T.dim)
        wcagInfo := win.Add("Text", "x260 y303 w250", "")
        this.wcagInfo := wcagInfo

        ; ── BUTTONS ──
        win.Add("Text", "x20 y340 w495 h1 Background" T.border)

        win.SetFont("s10", "Segoe UI")
        btnHex    := win.Add("Button", "x25  y355 w115 h32", "Copy Hex")
        btnRgb    := win.Add("Button", "x148 y355 w115 h32", "Copy RGB")
        btnRandom := win.Add("Button", "x271 y355 w115 h32", "Randomize")
        btnReset  := win.Add("Button", "x394 y355 w115 h32", "Reset")

        ; ── STATUS LINE ──
        win.SetFont("s9", "Segoe UI")
        status := win.Add("Text", "x25 y397 w485", "Ready — drag sliders or randomize")
        colors[status.Hwnd] := T.CR(T.dim)
        this.status := status

        ; ── WIRE: Slider Change → Signal.Set ──
        slR.OnEvent("Change", (ctrl, *) => self.r.Set(ctrl.Value))
        slG.OnEvent("Change", (ctrl, *) => self.g.Set(ctrl.Value))
        slB.OnEvent("Change", (ctrl, *) => self.b.Set(ctrl.Value))

        ; ══════════════════════════════════════════════════════
        ; COMPUTED VALUES — derived from the 3 source signals
        ; No manual recalculation anywhere. Ever.
        ; ══════════════════════════════════════════════════════

        hexC := Rx.Computed(() => Format("{:02X}{:02X}{:02X}",
            self.r.Get(), self.g.Get(), self.b.Get()))

        hslC := Rx.Computed(() =>
            RgbToHsl(self.r.Get(), self.g.Get(), self.b.Get()))

        lumaC := Rx.Computed(() =>
            RelLuminance(self.r.Get(), self.g.Get(), self.b.Get()))

        invC := Rx.Computed(() => Format("{:02X}{:02X}{:02X}",
            255 - self.r.Get(), 255 - self.g.Get(), 255 - self.b.Get()))

        ; ══════════════════════════════════════════════════════
        ; EFFECTS — auto-update every GUI element reactively
        ; When ANY signal changes, the whole UI stays in sync.
        ; ══════════════════════════════════════════════════════

        ; Swatch + hex display
        Rx.Effect(() {
            h := hexC.Get()
            self.swatch.BackColor := h
            self.hexDisp.Text := "#" h
            self.hexInfo.Text := "#" h
        })

        ; Channel values
        Rx.Effect(() {
            rv := self.r.Get(), gv := self.g.Get(), bv := self.b.Get()
            self.rVal.Text := String(rv)
            self.gVal.Text := String(gv)
            self.bVal.Text := String(bv)
            self.rgbInfo.Text := rv ", " gv ", " bv
        })

        ; HSL
        Rx.Effect(() {
            hsl := hslC.Get()
            self.hslInfo.Text := hsl.h "°  " hsl.s "%  " hsl.l "%"
        })

        ; Luminance + WCAG contrast
        Rx.Effect(() {
            luma := lumaC.Get()
            self.lumaInfo.Text := Round(luma * 100) "%"
            bgL := RelLuminance(15, 15, 15)
            ratio := (Max(luma, bgL) + 0.05) / (Min(luma, bgL) + 0.05)
            grade := ratio >= 7 ? "AAA" : ratio >= 4.5 ? "AA" : ratio >= 3 ? "A" : "Fail"
            self.wcagInfo.Text := Format("{:.1f}:1  {}", ratio, grade)
        })

        ; Invert swatch
        Rx.Effect(() {
            ih := invC.Get()
            self.invSwatch.BackColor := ih
            self.invHex.Text := "#" ih
        })

        ; ── BUTTON EVENTS ──
        btnHex.OnEvent("Click", (*) {
            TryCopy("#" hexC.Get()).Match(
                (v) => self.status.Text := "Copied " v,
                (e) => self.status.Text := "Error: " e
            )
        })

        btnRgb.OnEvent("Click", (*) {
            rv := self.r.Get(), gv := self.g.Get(), bv := self.b.Get()
            TryCopy(Format("rgb({}, {}, {})", rv, gv, bv)).Match(
                (v) => self.status.Text := "Copied " v,
                (e) => self.status.Text := "Error: " e
            )
        })

        btnRandom.OnEvent("Click", (*) {
            self._setRgb(Random(0, 255), Random(0, 255), Random(0, 255))
            self.status.Text := "Randomized"
        })

        btnReset.OnEvent("Click", (*) {
            self._setRgb(91, 159, 239)
            self.status.Text := "Reset to Ocean Blue"
        })

        ; ── KEYBOARD SHORTCUTS ──
        ; Escape to close
        win.OnEvent("Escape", (*) => ExitApp())
        win.OnEvent("Close", (*) => ExitApp())

        ; ── SHOW ──
        swatch.Show("x25 y20 w145 h148")
        invSwatch.Show("x25 y225 w145 h52")
        win.Show("w530 h425")
    }

    ; Sync sliders + signals in one call
    _setRgb(r, g, b) {
        this.slR.Value := r
        this.slG.Value := g
        this.slB.Value := b
        this.r.Set(r)
        this.g.Set(g)
        this.b.Set(b)
    }
}

; ═══════════════════════════════════════════════════════════════
; LAUNCH
; ═══════════════════════════════════════════════════════════════

app := ColorLab()
