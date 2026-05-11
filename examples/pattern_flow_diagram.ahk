/*
    Pattern Flow Diagram — Interactive Reactive Signal Architecture Visualizer
    ──────────────────────────────────────────────────────────────────────────
    Uses GDI+ to draw a live architecture diagram showing how reactive
    signals propagate through Computed and Effect nodes.

    Three RGB sliders drive the entire graph — when any value changes,
    connection lines pulse amber to show data flowing through the system.

    Architecture:
      Signal(R,G,B) ──► Computed(Hex,HSL,Luma) ──► Effect(Swatch,Labels,WCAG)

    Run: bin\AutoHotkey64.exe examples\pattern_flow_diagram.ahk
*/
#Requires AutoHotkey v2.1-alpha.26

; ═══════════════════════════════════════════════════════════════
; REACTIVE PRIMITIVES
; ═══════════════════════════════════════════════════════════════

class Rx {
    static _observer := ""

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
            for fn, _x in subs
                fn()
        }
        return {Get: get, Set: set}
    }

    static Computed(fn) {
        val := ""
        subs := Map()
        recompute := () {
            prev := Rx._observer
            Rx._observer := recompute
            val := fn()
            Rx._observer := prev
            for sub, _x in subs
                sub()
        }
        recompute()
        return {Get: (_) {
            if Rx._observer != ""
                subs[Rx._observer] := true
            return val
        }}
    }

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

try {
    uxtheme := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr")
    if pSetMode := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 135, "Ptr")
        DllCall(pSetMode, "Int", 2)
}

DarkTitleBar(hwnd) {
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 20, "UInt*", 1, "UInt", 4)
}

; ═══════════════════════════════════════════════════════════════
; GDI+ RENDERER
; ═══════════════════════════════════════════════════════════════

class GdiCanvas {
    ; Canvas dimensions
    static W := 780, H := 350

    ; GDI+ handles
    _token := 0
    _bmp := 0
    _gfx := 0
    _fontUI := 0
    _fontMono := 0
    _fontSmall := 0
    _fontTitle := 0
    _familyUI := 0
    _familyMono := 0
    _fmtCenter := 0
    _fmtLeft := 0
    _frameIdx := 0

    __New(picCtrl) {
        this._pic := picCtrl
        this._tmpDir := A_Temp
        this._Init()
    }

    _Init() {
        ; Load GDI+
        si := Buffer(24, 0)
        NumPut("UInt", 1, si, 0)
        DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok := 0, "Ptr", si, "Ptr", 0)
        this._token := tok

        ; Create bitmap + graphics
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", GdiCanvas.W, "Int", GdiCanvas.H,
            "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &bmp := 0)
        this._bmp := bmp
        DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bmp, "Ptr*", &gfx := 0)
        this._gfx := gfx
        DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", gfx, "Int", 4)
        DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", gfx, "Int", 5)

        ; Create font families
        DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe UI", "Ptr", 0, "Ptr*", &fUI := 0)
        this._familyUI := fUI

        ; Try JetBrains Mono, fall back to Consolas
        res := DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "JetBrains Mono", "Ptr", 0, "Ptr*", &fMono := 0)
        if res != 0
            DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Consolas", "Ptr", 0, "Ptr*", &fMono)
        this._familyMono := fMono

        ; Create fonts (Unit 2 = Point)
        DllCall("gdiplus\GdipCreateFont", "Ptr", fUI, "Float", Float(9.0), "Int", 0, "Int", 2, "Ptr*", &fs := 0)
        this._fontSmall := fs
        DllCall("gdiplus\GdipCreateFont", "Ptr", fUI, "Float", Float(9.0), "Int", 1, "Int", 2, "Ptr*", &ft := 0)
        this._fontTitle := ft
        DllCall("gdiplus\GdipCreateFont", "Ptr", fUI, "Float", Float(11.0), "Int", 0, "Int", 2, "Ptr*", &fu := 0)
        this._fontUI := fu
        DllCall("gdiplus\GdipCreateFont", "Ptr", fMono, "Float", Float(10.0), "Int", 0, "Int", 2, "Ptr*", &fm := 0)
        this._fontMono := fm

        ; String formats
        DllCall("gdiplus\GdipCreateStringFormat", "Int", 0, "Int", 0, "Ptr*", &fmtC := 0)
        DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", fmtC, "Int", 1)
        DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", fmtC, "Int", 1)
        this._fmtCenter := fmtC

        DllCall("gdiplus\GdipCreateStringFormat", "Int", 0, "Int", 0, "Ptr*", &fmtL := 0)
        DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", fmtL, "Int", 0)
        DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", fmtL, "Int", 1)
        this._fmtLeft := fmtL
    }

    ; Create a solid brush (caller must delete)
    _Brush(argb) {
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &br := 0)
        return br
    }

    ; Create a pen (caller must delete)
    _Pen(argb, width := 1.0) {
        DllCall("gdiplus\GdipCreatePen1", "UInt", argb, "Float", Float(width), "Int", 2, "Ptr*", &p := 0)
        return p
    }

    ; Create rounded rect path (caller must delete)
    _RoundRect(x, y, w, h, rad) {
        DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path := 0)
        d := Float(rad * 2)
        fx := Float(x), fy := Float(y), fw := Float(w), fh := Float(h)
        ; Top-left
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path,
            "Float", fx, "Float", fy, "Float", d, "Float", d,
            "Float", Float(180.0), "Float", Float(90.0))
        ; Top-right
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path,
            "Float", Float(fx + fw - d), "Float", fy, "Float", d, "Float", d,
            "Float", Float(270.0), "Float", Float(90.0))
        ; Bottom-right
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path,
            "Float", Float(fx + fw - d), "Float", Float(fy + fh - d), "Float", d, "Float", d,
            "Float", Float(0.0), "Float", Float(90.0))
        ; Bottom-left
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path,
            "Float", fx, "Float", Float(fy + fh - d), "Float", d, "Float", d,
            "Float", Float(90.0), "Float", Float(90.0))
        DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
        return path
    }

    ; Draw text into a rectangle
    _Text(text, x, y, w, h, font, argb, centered := true) {
        br := this._Brush(argb)
        rect := Buffer(16)
        NumPut("Float", Float(x), "Float", Float(y), "Float", Float(w), "Float", Float(h), rect)
        fmt := centered ? this._fmtCenter : this._fmtLeft
        DllCall("gdiplus\GdipDrawString", "Ptr", this._gfx, "WStr", text, "Int", -1,
            "Ptr", font, "Ptr", rect, "Ptr", fmt, "Ptr", br)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
    }

    ; Draw a node (rounded rect with title + value)
    _Node(x, y, w, h, title, value, accentArgb, isActive) {
        gfx := this._gfx

        ; Fill
        fillPath := this._RoundRect(x, y, w, h, 10)
        fillBr := this._Brush(0xFF121212)
        DllCall("gdiplus\GdipFillPath", "Ptr", gfx, "Ptr", fillBr, "Ptr", fillPath)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", fillBr)

        ; Border — bright when active, dim otherwise
        borderArgb := isActive ? accentArgb : (accentArgb & 0x00FFFFFF) | 0x60000000
        borderPen := this._Pen(borderArgb, isActive ? 2.0 : 1.5)
        DllCall("gdiplus\GdipDrawPath", "Ptr", gfx, "Ptr", borderPen, "Ptr", fillPath)
        DllCall("gdiplus\GdipDeletePen", "Ptr", borderPen)
        DllCall("gdiplus\GdipDeletePath", "Ptr", fillPath)

        ; Title text (accent colored, top area)
        titleArgb := isActive ? accentArgb : (accentArgb & 0x00FFFFFF) | 0xB0000000
        this._Text(title, x, y + 2, w, h * 0.48, this._fontSmall, titleArgb)

        ; Value text (white, monospace, bottom area)
        valArgb := isActive ? 0xFFFFFFFF : 0xFFD0D0D0
        this._Text(value, x, y + h * 0.38, w, h * 0.55, this._fontMono, valArgb)
    }

    ; Draw a line
    _Line(x1, y1, x2, y2, argb, width := 1.0) {
        pen := this._Pen(argb, width)
        DllCall("gdiplus\GdipDrawLine", "Ptr", this._gfx, "Ptr", pen,
            "Float", Float(x1), "Float", Float(y1), "Float", Float(x2), "Float", Float(y2))
        DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    }

    ; Draw a small filled triangle arrowhead pointing right
    _Arrow(x, y, argb, size := 5) {
        br := this._Brush(argb)
        DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path := 0)
        ; Triangle points: tip at (x,y), base behind
        pts := Buffer(24)  ; 3 points, 8 bytes each (Float,Float)
        NumPut("Float", Float(x), "Float", Float(y), pts, 0)
        NumPut("Float", Float(x - size * 1.5), "Float", Float(y - size), pts, 8)
        NumPut("Float", Float(x - size * 1.5), "Float", Float(y + size), pts, 16)
        DllCall("gdiplus\GdipAddPathPolygon", "Ptr", path, "Ptr", pts, "Int", 3)
        DllCall("gdiplus\GdipFillPath", "Ptr", this._gfx, "Ptr", br, "Ptr", path)
        DllCall("gdiplus\GdipDeletePath", "Ptr", path)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
    }

    ; Draw a filled rounded rect (for color swatches)
    _FillRoundRect(x, y, w, h, rad, argb) {
        path := this._RoundRect(x, y, w, h, rad)
        br := this._Brush(argb)
        DllCall("gdiplus\GdipFillPath", "Ptr", this._gfx, "Ptr", br, "Ptr", path)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
        ; Border
        pen := this._Pen(0xFF303030, 1.0)
        DllCall("gdiplus\GdipDrawPath", "Ptr", this._gfx, "Ptr", pen, "Ptr", path)
        DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
        DllCall("gdiplus\GdipDeletePath", "Ptr", path)
    }

    ; Clear and render a full frame
    Draw(rv, gv, bv, hexStr, hsl, luma, isActive) {
        gfx := this._gfx

        ; Clear canvas
        DllCall("gdiplus\GdipGraphicsClear", "Ptr", gfx, "UInt", 0xFF0F0F0F)

        ; Colors
        cBlue   := 0xFF5B9FEF
        cPurple := 0xFFA855F7
        cGreen  := 0xFF7BC96F
        cAmber  := 0xFFF59E42
        cDim    := 0xFF303030
        cMuted  := 0xFF606060

        lineColor := isActive ? cAmber : cDim
        lineWidth := isActive ? 2.0 : 1.0

        ; ── Column headers ──
        this._Text("SIGNALS", 25, 8, 145, 20, this._fontSmall, cMuted)
        this._Text("COMPUTED", 255, 8, 150, 20, this._fontSmall, cMuted)
        this._Text("EFFECTS", 480, 8, 130, 20, this._fontSmall, cMuted)
        this._Text("PREVIEW", 645, 8, 110, 20, this._fontSmall, cMuted)

        ; ── Signal nodes ──
        this._Node(25, 42, 145, 52, "Signal: R", String(rv), cBlue, isActive)
        this._Node(25, 114, 145, 52, "Signal: G", String(gv), cBlue, isActive)
        this._Node(25, 186, 145, 52, "Signal: B", String(bv), cBlue, isActive)

        ; ── Computed nodes ──
        hslStr := Format("{}° {}% {}%", hsl.h, hsl.s, hsl.l)
        lumaStr := Format("{}%", Round(luma * 100))
        this._Node(255, 42, 150, 52, "Computed: Hex", "#" hexStr, cPurple, isActive)
        this._Node(255, 114, 150, 52, "Computed: HSL", hslStr, cPurple, isActive)
        this._Node(255, 186, 150, 52, "Computed: Luma", lumaStr, cPurple, isActive)

        ; ── Effect nodes ──
        ; WCAG calculation
        bgL := RelLuminance(15, 15, 15)
        ratio := (Max(luma, bgL) + 0.05) / (Min(luma, bgL) + 0.05)
        grade := ratio >= 7 ? "AAA" : ratio >= 4.5 ? "AA" : ratio >= 3 ? "A" : "Fail"

        this._Node(480, 42, 130, 52, "Effect: Swatch", "Repaint", cGreen, isActive)
        this._Node(480, 114, 130, 52, "Effect: Labels", "Update", cGreen, isActive)
        this._Node(480, 186, 130, 52, "Effect: WCAG", grade " " Format("{:.1f}:1", ratio), cGreen, isActive)

        ; ── Connection lines ──
        ; Vertical bus line at x=195
        busX := 195
        this._Line(busX, 55, busX, 225, lineColor, lineWidth)

        ; Signal right edges → bus
        sigRightX := 170
        sigYs := [68, 140, 212]
        for yVal in sigYs {
            this._Line(sigRightX, yVal, busX, yVal, lineColor, lineWidth)
        }

        ; Bus → computed left edges
        compLeftX := 255
        compYs := [68, 140, 212]
        for yVal in compYs {
            this._Line(busX, yVal, compLeftX, yVal, lineColor, lineWidth)
            this._Arrow(compLeftX, yVal, lineColor, 4)
        }

        ; Horizontal taps from bus to each computed (small horizontal stubs)
        ; Already drawn above

        ; Computed right edges → effect left edges
        compRightX := 405
        effLeftX := 480
        effYs := [68, 140, 212]
        loop 3 {
            cy := compYs[A_Index]
            ey := effYs[A_Index]
            this._Line(compRightX, cy, effLeftX, ey, lineColor, lineWidth)
            this._Arrow(effLeftX, ey, lineColor, 4)
        }

        ; ── Color preview swatch ──
        rgbArgb := 0xFF000000 | (rv << 16) | (gv << 8) | bv
        this._FillRoundRect(645, 42, 110, 80, 10, rgbArgb)
        ; Label inside/below swatch
        ; Choose text color based on luminance
        swatchTextColor := luma > 0.4 ? 0xFF000000 : 0xFFFFFFFF
        this._Text("#" hexStr, 645, 90, 110, 28, this._fontMono, swatchTextColor)

        ; ── Invert preview ──
        ir := 255 - rv, ig := 255 - gv, ib := 255 - bv
        invArgb := 0xFF000000 | (ir << 16) | (ig << 8) | ib
        this._FillRoundRect(645, 145, 110, 52, 10, invArgb)
        invHex := Format("{:02X}{:02X}{:02X}", ir, ig, ib)
        invLuma := RelLuminance(ir, ig, ib)
        invTextColor := invLuma > 0.4 ? 0xFF000000 : 0xFFFFFFFF
        this._Text("#" invHex, 645, 165, 110, 28, this._fontMono, invTextColor)

        ; Invert label
        this._Text("Invert", 645, 145, 110, 20, this._fontSmall, cMuted)

        ; ── Connection from effects to preview ──
        this._Line(610, 68, 645, 82, lineColor, lineWidth)
        this._Arrow(645, 82, lineColor, 4)

        ; ── Legend at bottom ──
        legendY := 260
        ; Signal dot + label
        this._FillRoundRect(25, legendY, 8, 8, 4, cBlue)
        this._Text("Signal", 38, legendY - 4, 55, 16, this._fontSmall, cMuted, false)
        ; Computed dot + label
        this._FillRoundRect(105, legendY, 8, 8, 4, cPurple)
        this._Text("Computed", 118, legendY - 4, 70, 16, this._fontSmall, cMuted, false)
        ; Effect dot + label
        this._FillRoundRect(200, legendY, 8, 8, 4, cGreen)
        this._Text("Effect", 213, legendY - 4, 55, 16, this._fontSmall, cMuted, false)
        ; Active indicator
        this._FillRoundRect(280, legendY, 8, 8, 4, cAmber)
        this._Text("Propagating", 293, legendY - 4, 85, 16, this._fontSmall, cMuted, false)

        ; Decorative tagline
        this._Text("Reactive Signal Flow — data propagates automatically through the graph",
            25, 290, 600, 20, this._fontSmall, 0xFF404040, false)

        ; Data flow direction label
        this._Text("data flow ───────►", 25, 320, 200, 20, this._fontSmall, 0xFF353535, false)
    }

    ; Save bitmap to file and load into Picture control
    Render() {
        ; Alternate between two temp files for reliable reload
        this._frameIdx := !this._frameIdx
        path := this._tmpDir "\ahk_flow_" this._frameIdx ".bmp"

        ; Save as BMP
        clsid := Buffer(16)
        DllCall("ole32\CLSIDFromString", "WStr", "{557CF400-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)
        DllCall("gdiplus\GdipSaveImageToFile", "Ptr", this._bmp, "WStr", path, "Ptr", clsid, "Ptr", 0)

        ; Load into Picture control
        this._pic.Value := path
    }

    Cleanup() {
        if this._gfx
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", this._gfx)
        if this._bmp
            DllCall("gdiplus\GdipDisposeImage", "Ptr", this._bmp)
        if this._fontUI
            DllCall("gdiplus\GdipDeleteFont", "Ptr", this._fontUI)
        if this._fontMono
            DllCall("gdiplus\GdipDeleteFont", "Ptr", this._fontMono)
        if this._fontSmall
            DllCall("gdiplus\GdipDeleteFont", "Ptr", this._fontSmall)
        if this._fontTitle
            DllCall("gdiplus\GdipDeleteFont", "Ptr", this._fontTitle)
        if this._familyUI
            DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", this._familyUI)
        if this._familyMono
            DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", this._familyMono)
        if this._fmtCenter
            DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", this._fmtCenter)
        if this._fmtLeft
            DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", this._fmtLeft)
        if this._token
            DllCall("gdiplus\GdiplusShutdown", "Ptr", this._token)

        ; Clean up temp files
        try FileDelete(this._tmpDir "\ahk_flow_0.bmp")
        try FileDelete(this._tmpDir "\ahk_flow_1.bmp")
    }
}

; ═══════════════════════════════════════════════════════════════
; THE APP
; ═══════════════════════════════════════════════════════════════

class FlowDiagramApp {
    __New() {
        self := this

        ; ── Reactive state ──
        this.r := Rx.Signal(91)
        this.g := Rx.Signal(159)
        this.b := Rx.Signal(239)
        this._active := false
        this._redrawPending := false

        ; ── Build GUI ──
        win := Gui("-MaximizeBox -Resize", "Pattern Flow Diagram")
        this.win := win
        win.BackColor := "0f0f0f"
        win.MarginX := 0, win.MarginY := 0
        DarkTitleBar(win.Hwnd)

        ; WM_CTLCOLORSTATIC for dark text
        bgBrush := DllCall("CreateSolidBrush", "UInt", 0x000F0F0F, "Ptr")
        colorMap := Map()
        this._colorMap := colorMap

        win.OnMessage(0x0138, (_gui, wp, lp, *) {
            cr := colorMap.Has(lp) ? colorMap[lp] : 0x00FFFFFF
            DllCall("SetTextColor", "Ptr", wp, "UInt", cr)
            DllCall("SetBkMode", "Ptr", wp, "UInt", 1)
            return bgBrush
        })

        ; ── Canvas (Picture control) ──
        pic := win.Add("Picture", "x0 y0 w780 h350")
        this._pic := pic

        ; ── Initialize GDI+ canvas ──
        this._canvas := GdiCanvas(pic)

        ; ── Sliders ──
        win.SetFont("s10 Bold", "Segoe UI")

        rLbl := win.Add("Text", "x25 y365 w25", "R")
        colorMap[rLbl.Hwnd] := 0x005B5BDC  ; Red in BGR

        gLbl := win.Add("Text", "x25 y400 w25", "G")
        colorMap[gLbl.Hwnd] := 0x006FC97B  ; Green in BGR

        bLbl := win.Add("Text", "x25 y435 w25", "B")
        colorMap[bLbl.Hwnd] := 0x00EFD322  ; Cyan in BGR

        slR := win.Add("Slider", "x60 y362 w220 Range0-255 NoTicks ToolTip", 91)
        slG := win.Add("Slider", "x60 y397 w220 Range0-255 NoTicks ToolTip", 159)
        slB := win.Add("Slider", "x60 y432 w220 Range0-255 NoTicks ToolTip", 239)
        this.slR := slR, this.slG := slG, this.slB := slB

        ; Value readouts
        win.SetFont("s10", "JetBrains Mono")
        rValCtrl := win.Add("Text", "x290 y365 w45 Right", "91")
        gValCtrl := win.Add("Text", "x290 y400 w45 Right", "159")
        bValCtrl := win.Add("Text", "x290 y435 w45 Right", "239")
        this._rValCtrl := rValCtrl
        this._gValCtrl := gValCtrl
        this._bValCtrl := bValCtrl

        ; ── Buttons ──
        win.SetFont("s10", "Segoe UI")
        btnRandom := win.Add("Button", "x380 y370 w120 h30", "Randomize")
        btnReset := win.Add("Button", "x510 y370 w120 h30", "Reset")

        ; ── Hex display ──
        win.SetFont("s16 Bold", "JetBrains Mono")
        hexCtrl := win.Add("Text", "x380 y415 w250", "#5B9FEF")
        colorMap[hexCtrl.Hwnd] := 0x00EF9F5B  ; Ocean Blue in BGR
        this._hexCtrl := hexCtrl

        ; ── Status ──
        win.SetFont("s9", "Segoe UI")
        statusCtrl := win.Add("Text", "x25 y475 w720", "Ready — drag sliders to see reactive propagation")
        colorMap[statusCtrl.Hwnd] := 0x00606060
        this._statusCtrl := statusCtrl

        ; ── Wire slider events ──
        slR.OnEvent("Change", (ctrl, *) {
            self.r.Set(ctrl.Value)
        })
        slG.OnEvent("Change", (ctrl, *) {
            self.g.Set(ctrl.Value)
        })
        slB.OnEvent("Change", (ctrl, *) {
            self.b.Set(ctrl.Value)
        })

        ; ── Button events ──
        btnRandom.OnEvent("Click", (*) {
            self._SetRgb(Random(0, 255), Random(0, 255), Random(0, 255))
            self._statusCtrl.Text := "Randomized — signals propagated through graph"
        })
        btnReset.OnEvent("Click", (*) {
            self._SetRgb(91, 159, 239)
            self._statusCtrl.Text := "Reset to Ocean Blue (#5B9FEF)"
        })

        ; ── Computed values ──
        hexC := Rx.Computed(() => Format("{:02X}{:02X}{:02X}",
            self.r.Get(), self.g.Get(), self.b.Get()))

        hslC := Rx.Computed(() =>
            RgbToHsl(self.r.Get(), self.g.Get(), self.b.Get()))

        lumaC := Rx.Computed(() =>
            RelLuminance(self.r.Get(), self.g.Get(), self.b.Get()))

        ; ── Effect: schedule redraw on any change ──
        Rx.Effect(() {
            ; Touch all computed values to subscribe
            hexC.Get()
            hslC.Get()
            lumaC.Get()
            self._ScheduleRedraw()
        })

        ; Store computed refs for rendering
        this._hexC := hexC
        this._hslC := hslC
        this._lumaC := lumaC

        ; ── Close handler ──
        win.OnEvent("Close", (*) {
            self._canvas.Cleanup()
            ExitApp()
        })
        win.OnEvent("Escape", (*) {
            self._canvas.Cleanup()
            ExitApp()
        })

        ; ── Initial render ──
        this._DoRender()

        ; ── Show ──
        win.Show("w780 h500")
    }

    _SetRgb(rv, gv, bv) {
        this.slR.Value := rv
        this.slG.Value := gv
        this.slB.Value := bv
        this.r.Set(rv)
        this.g.Set(gv)
        this.b.Set(bv)
    }

    _ScheduleRedraw() {
        self := this
        if !this._redrawPending {
            this._redrawPending := true
            ; Activate pulse
            this._active := true
            SetTimer(() {
                self._redrawPending := false
                self._DoRender()
                ; Schedule deactivation
                SetTimer(() {
                    self._active := false
                    self._DoRender()
                }, -400)
            }, -30)
        }
    }

    _DoRender() {
        rv := this.r.Get()
        gv := this.g.Get()
        bv := this.b.Get()
        hexStr := this._hexC.Get()
        hsl := this._hslC.Get()
        luma := this._lumaC.Get()

        ; Update text controls
        this._rValCtrl.Text := String(rv)
        this._gValCtrl.Text := String(gv)
        this._bValCtrl.Text := String(bv)
        this._hexCtrl.Text := "#" hexStr

        ; Draw and render
        this._canvas.Draw(rv, gv, bv, hexStr, hsl, luma, this._active)
        this._canvas.Render()

        if this._active
            this._statusCtrl.Text := "Propagating — signals → computed → effects"
    }
}

; ═══════════════════════════════════════════════════════════════
; LAUNCH
; ═══════════════════════════════════════════════════════════════

app := FlowDiagramApp()
