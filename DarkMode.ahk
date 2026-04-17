/*
DarkMode.ahk — Dark mode GUI framework for AutoHotkey v2.1-alpha.26+

Usage:
    #Include DarkMode.ahk
    myGui := Dark.Gui("+Resize", "My App")
    myGui.Add("Button", "w200 +Accent", "OK")
    myGui.Add("Edit", "w300", "text")
    myGui.Show()
*/
#Requires AutoHotkey v2.1-alpha.26
#Warn LocalSameAsGlobal, Off  ; Painters forward-reference Dark (defined later)

; ═══════════════════════════════════════════════════
; Win32 Structures
; ═══════════════════════════════════════════════════

Struct RECT {
    left: i32, top: i32, right: i32, bottom: i32
}

Struct POINT {
    x: i32, y: i32
}

Struct SIZE {
    cx: i32, cy: i32
}

Struct NMHDR {
    hwndFrom: uptr, idFrom: uptr, code: i32
}

Struct NMCUSTOMDRAW {
    hdr: NMHDR
    dwDrawStage: u32
    hdc: uptr
    rc: RECT
    dwItemSpec: uptr
    uItemState: u32
    lItemlParam: iptr
}

Struct PAINTSTRUCT {
    hdc: uptr
    fErase: i32
    rcPaint: RECT
    fRestore: i32
    fIncUpdate: i32
    rgbReserved: UInt8[32]
}

Struct SCROLLINFO {
    cbSize: u32, fMask: u32, nMin: i32, nMax: i32
    nPage: u32, nPos: i32, nTrackPos: i32
}

Struct TRACKMOUSEEVENT {
    cbSize: u32, dwFlags: u32, hwndTrack: uptr, dwHoverTime: u32
}

Struct COMBOBOXINFO {
    cbSize: u32
    rcItem: RECT
    rcButton: RECT
    stateButton: u32
    hwndCombo: uptr
    hwndItem: uptr
    hwndList: uptr
}

Struct TEXTMETRICW {
    tmHeight: i32, tmAscent: i32, tmDescent: i32
    tmInternalLeading: i32, tmExternalLeading: i32
    tmAveCharWidth: i32, tmMaxCharWidth: i32
    tmWeight: i32, tmOverhang: i32
    tmDigitizedAspectX: i32, tmDigitizedAspectY: i32
    tmFirstChar: u16, tmLastChar: u16
    tmDefaultChar: u16, tmBreakChar: u16
    tmItalic: u8, tmUnderlined: u8, tmStruckOut: u8
    tmPitchAndFamily: u8, tmCharSet: u8
}

Struct TCITEMW {
    mask: u32, dwState: u32, dwStateMask: u32
    pszText: uptr, cchTextMax: i32
    iImage: i32, lParam: iptr
}

Struct HDITEMW {
    mask: u32, cxy: i32, pszText: uptr, hbm: uptr
    cchTextMax: i32, fmt: i32, lParam: iptr
    iImage: i32, iOrder: i32, type: u32
    pvFilter: uptr, state: u32
}

Struct MENUINFO {
    cbSize: u32, fMask: u32, dwStyle: u32, cyMax: u32
    hbrBack: uptr, dwContextHelpID: u32, dwMenuData: uptr
}

Struct GdiplusStartupInput {
    GdiplusVersion: u32
    DebugEventCallback: uptr
    SuppressBackgroundThread: i32
    SuppressExternalCodecs: i32
}

; ═══════════════════════════════════════════════════
; Palette
; ═══════════════════════════════════════════════════

Struct Palette {
    Background: u32, Surface: u32, Header: u32, Elevated: u32
    Border: u32, BorderSubtle: u32, BorderHover: u32
    Accent: u32, AccentHover: u32, AccentPressed: u32
    Success: u32, Warning: u32, Error: u32, Info: u32
    TextPrimary: u32, TextSecondary: u32, TextMuted: u32, TextDisabled: u32
    Control: u32, ControlHover: u32, ControlActive: u32, Selection: u32
    ScrollTrack: u32, ScrollThumb: u32, ScrollThumbHover: u32
}

_InitPalette() {
    p := Palette()
    p.Background := 0x0F0F0F, p.Surface := 0x121212
    p.Header := 0x141414, p.Elevated := 0x1A1A1A
    p.Border := 0x303030, p.BorderSubtle := 0x232323, p.BorderHover := 0x505050
    p.Accent := 0x5B9FEF, p.AccentHover := 0x7AB3F5, p.AccentPressed := 0x4A8AD4
    p.Success := 0x7BC96F, p.Warning := 0xF59E42
    p.Error := 0xDC3545, p.Info := 0x22D3EE
    p.TextPrimary := 0xFFFFFF, p.TextSecondary := 0xA0A0A0
    p.TextMuted := 0x606060, p.TextDisabled := 0x4A4A4A
    p.Control := 0x202020, p.ControlHover := 0x2A2A2A
    p.ControlActive := 0x333333, p.Selection := 0x264F78
    p.ScrollTrack := 0x1A1A1A, p.ScrollThumb := 0x404040
    p.ScrollThumbHover := 0x555555
    return p
}

; ═══════════════════════════════════════════════════
; GDI Helper
; ═══════════════════════════════════════════════════

class GDI {
    static _brushCache := Map()

    static ToBGR(rgb) => ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF)

    static Brush(rgb) {
        bgr := this.ToBGR(rgb)
        if !this._brushCache.Has(bgr)
            this._brushCache[bgr] := DllCall("CreateSolidBrush", "UInt", bgr, "Ptr")
        return this._brushCache[bgr]
    }

    static FillRect(hdc, rc, color) {
        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", this.Brush(color))
    }

    static RoundRect(hdc, rc, color, radius) {
        brush := DllCall("CreateSolidBrush", "UInt", this.ToBGR(color), "Ptr")
        pen := DllCall("CreatePen", "Int", 0, "Int", 1, "UInt", this.ToBGR(color), "Ptr")
        oldBrush := DllCall("SelectObject", "Ptr", hdc, "Ptr", brush, "Ptr")
        oldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
        DllCall("RoundRect", "Ptr", hdc, "Int", rc.left, "Int", rc.top,
            "Int", rc.right, "Int", rc.bottom, "Int", radius, "Int", radius)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldBrush)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldPen)
        DllCall("DeleteObject", "Ptr", brush)
        DllCall("DeleteObject", "Ptr", pen)
    }

    static FrameRect(hdc, rc, color) {
        brush := DllCall("CreateSolidBrush", "UInt", this.ToBGR(color), "Ptr")
        DllCall("FrameRect", "Ptr", hdc, "Ptr", rc, "Ptr", brush)
        DllCall("DeleteObject", "Ptr", brush)
    }

    static DrawText(hdc, text, rc, color, flags := 0x25) {
        ; Default flags: DT_CENTER(1) | DT_VCENTER(4) | DT_SINGLELINE(0x20)
        DllCall("SetBkMode", "Ptr", hdc, "Int", 1)  ; TRANSPARENT
        DllCall("SetTextColor", "Ptr", hdc, "UInt", this.ToBGR(color))
        DllCall("DrawText", "Ptr", hdc, "Str", text, "Int", -1, "Ptr", rc, "UInt", flags)
    }

    static SelectFont(hdc, hwnd) {
        hFont := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
        return hFont ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr") : 0
    }

    static RestoreFont(hdc, oldFont) {
        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont)
    }

    static BeginBuffered(hwnd) {
        ps := PAINTSTRUCT()
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")
        rc := RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        memDC := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
        bmp := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", rc.right, "Int", rc.bottom, "Ptr")
        DllCall("SelectObject", "Ptr", memDC, "Ptr", bmp)
        return { hdc: hdc, memDC: memDC, bmp: bmp, rc: rc, ps: ps, hwnd: hwnd }
    }

    static EndBuffered(ctx) {
        DllCall("BitBlt", "Ptr", ctx.hdc, "Int", 0, "Int", 0,
            "Int", ctx.rc.right, "Int", ctx.rc.bottom, "Ptr", ctx.memDC,
            "Int", 0, "Int", 0, "UInt", 0x00CC0020)  ; SRCCOPY
        DllCall("DeleteDC", "Ptr", ctx.memDC)
        DllCall("DeleteObject", "Ptr", ctx.bmp)
        DllCall("EndPaint", "Ptr", ctx.hwnd, "Ptr", ctx.ps)
    }

    static RemoveBorder(hwnd) {
        static GWL_STYLE := -16, GWL_EXSTYLE := -20
        static WS_BORDER := 0x800000, WS_EX_CLIENTEDGE := 0x200, WS_EX_STATICEDGE := 0x20000
        SetWinLong := A_PtrSize = 8 ? "SetWindowLongPtr" : "SetWindowLong"
        GetWinLong := A_PtrSize = 8 ? "GetWindowLongPtr" : "GetWindowLong"
        style := DllCall(GetWinLong, "Ptr", hwnd, "Int", GWL_STYLE, "Ptr")
        DllCall(SetWinLong, "Ptr", hwnd, "Int", GWL_STYLE, "Ptr", style & ~WS_BORDER)
        exStyle := DllCall(GetWinLong, "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")
        DllCall(SetWinLong, "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", exStyle & ~(WS_EX_CLIENTEDGE | WS_EX_STATICEDGE))
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0,
            "UInt", 0x27)  ; SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER
    }

    static Destroy() {
        for _, brush in this._brushCache
            DllCall("DeleteObject", "Ptr", brush)
        this._brushCache.Clear()
    }
}

; ═══════════════════════════════════════════════════
; Subclass Utility
; ═══════════════════════════════════════════════════

class Subclass {
    static _setWinLong := A_PtrSize = 8 ? "SetWindowLongPtr" : "SetWindowLong"

    static Install(hwnd, procMethod, callbacks, oldProcs) {
        if oldProcs.Has(hwnd)
            return false
        cb := CallbackCreate(procMethod, , 4)
        callbacks[hwnd] := cb
        oldProcs[hwnd] := DllCall(this._setWinLong, "Ptr", hwnd, "Int", -4, "Ptr", cb, "Ptr")
        return true
    }

    static Uninstall(hwnd, callbacks, oldProcs) {
        if !oldProcs.Has(hwnd)
            return
        DllCall(this._setWinLong, "Ptr", hwnd, "Int", -4, "Ptr", oldProcs[hwnd], "Ptr")
        CallbackFree(callbacks[hwnd])
        callbacks.Delete(hwnd), oldProcs.Delete(hwnd)
    }

    static Forward(oldProc, hwnd, msg, wParam, lParam) {
        return DllCall("CallWindowProc", "Ptr", oldProc, "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }
}

; ═══════════════════════════════════════════════════
; Painter Base
; ═══════════════════════════════════════════════════

class Painter {
    static Apply(ctrl, opts := {}) {
        DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        ctrl.SetFont("c" Format("{:X}", Dark.palette.TextPrimary))
    }
    static Remove(hwnd) {
    }
}

; ═══════════════════════════════════════════════════
; Tier 1 Painters — Theme Only
; ═══════════════════════════════════════════════════

class EditPainter extends Painter {
    static Apply(ctrl, opts := {}) {
        super.Apply(ctrl, opts)
        GDI.RemoveBorder(ctrl.Hwnd)
    }
}

class CheckBoxPainter extends Painter {
    static Apply(ctrl, opts := {}) {
        super.Apply(ctrl, opts)
        ctrl.SetFont("c" Format("{:X}", Dark.palette.TextPrimary))
    }
}

class TreeViewPainter extends Painter {
    static Apply(ctrl, opts := {}) {
        super.Apply(ctrl, opts)
        SendMessage(0x111D, 0, GDI.ToBGR(Dark.palette.Surface), ctrl)     ; TVM_SETBKCOLOR
        SendMessage(0x111E, 0, GDI.ToBGR(Dark.palette.TextPrimary), ctrl) ; TVM_SETTEXTCOLOR
        SendMessage(0x1128, 0, GDI.ToBGR(Dark.palette.Border), ctrl)      ; TVM_SETLINECOLOR
        GDI.RemoveBorder(ctrl.Hwnd)
    }
}

class ProgressPainter extends Painter {
    static Apply(ctrl, opts := {}) {
        SendMessage(0x2001, 0, GDI.ToBGR(Dark.palette.Surface), ctrl)  ; PBM_SETBKCOLOR
        ctrl.Opt("c" Format("{:X}", Dark.palette.Accent))
    }
}

class ListBoxPainter extends Painter {
    static Apply(ctrl, opts := {}) {
        super.Apply(ctrl, opts)
        GDI.RemoveBorder(ctrl.Hwnd)
    }
}

class HotkeyPainter extends Painter {
    static Apply(ctrl, opts := {}) {
        super.Apply(ctrl, opts)
        GDI.RemoveBorder(ctrl.Hwnd)
    }
}

class UpDownPainter extends Painter {
    static Apply(ctrl, opts := {}) {
        super.Apply(ctrl, opts)
    }
}

class LinkPainter extends Painter {
    static Apply(ctrl, opts := {}) {
        ctrl.SetFont("c" Format("{:X}", Dark.palette.Accent))
    }
}

class DateTimePainter extends Painter {
    static Apply(ctrl, opts := {}) {
        super.Apply(ctrl, opts)
    }
}

class MonthCalPainter extends Painter {
    static Apply(ctrl, opts := {}) {
        super.Apply(ctrl, opts)
        SendMessage(0x100A, 1, GDI.ToBGR(Dark.palette.Surface), ctrl)     ; MCM_SETCOLOR MCSC_BACKGROUND
        SendMessage(0x100A, 4, GDI.ToBGR(Dark.palette.TextPrimary), ctrl) ; MCM_SETCOLOR MCSC_TEXT
        SendMessage(0x100A, 0, GDI.ToBGR(Dark.palette.Surface), ctrl)     ; MCM_SETCOLOR MCSC_MONTHBK
    }
}

class StatusBarPainter extends Painter {
    static Apply(ctrl, opts := {}) {
        SendMessage(0x2001, 0, GDI.ToBGR(Dark.palette.Header), ctrl)  ; SB_SETBKCOLOR via CCM_SETBKCOLOR
        ctrl.SetFont("c" Format("{:X}", Dark.palette.TextPrimary))
        DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
    }
}

; ═══════════════════════════════════════════════════
; Tier 2 Painters — Subclassed
; ═══════════════════════════════════════════════════

class ButtonPainter extends Painter {
    static _cbs := Map(), _oldProcs := Map(), _state := Map()

    static Apply(ctrl, opts := {}) {
        hwnd := ctrl.Hwnd
        this._state[hwnd] := { text: ctrl.Text, hover: false, pressed: false, accent: opts.HasOwnProp("accent") && opts.accent }
        Subclass.Install(hwnd, ObjBindMethod(this, "_Proc", hwnd), this._cbs, this._oldProcs)
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1)
    }

    static Remove(hwnd) {
        Subclass.Uninstall(hwnd, this._cbs, this._oldProcs)
        this._state.Delete(hwnd)
    }

    static _Proc(target, hwnd, msg, wParam, lParam) {
        if msg = 0x0014  ; WM_ERASEBKGND
            return 1
        if msg = 0x000F {  ; WM_PAINT
            this._Paint(target)
            return 0
        }
        if msg = 0x0200 {  ; WM_MOUSEMOVE
            s := this._state[target]
            if !s.hover {
                s.hover := true
                tme := TRACKMOUSEEVENT()
                tme.cbSize := ObjGetDataSize(tme)
                tme.dwFlags := 0x2  ; TME_LEAVE
                tme.hwndTrack := target
                DllCall("TrackMouseEvent", "Ptr", tme)
                DllCall("InvalidateRect", "Ptr", target, "Ptr", 0, "Int", 1)
            }
            return 0
        }
        if msg = 0x02A3 {  ; WM_MOUSELEAVE
            this._state[target].hover := false
            DllCall("InvalidateRect", "Ptr", target, "Ptr", 0, "Int", 1)
            return 0
        }
        if msg = 0x0201 {  ; WM_LBUTTONDOWN
            this._state[target].pressed := true
            DllCall("SetCapture", "Ptr", target)
            DllCall("InvalidateRect", "Ptr", target, "Ptr", 0, "Int", 1)
            return 0
        }
        if msg = 0x0202 {  ; WM_LBUTTONUP
            s := this._state[target]
            wasPressed := s.pressed
            s.pressed := false
            DllCall("ReleaseCapture")
            DllCall("InvalidateRect", "Ptr", target, "Ptr", 0, "Int", 1)
            if wasPressed {
                rc := RECT()
                DllCall("GetClientRect", "Ptr", target, "Ptr", rc)
                pt := POINT()
                DllCall("GetCursorPos", "Ptr", pt)
                DllCall("ScreenToClient", "Ptr", target, "Ptr", pt)
                if (pt.x >= 0 && pt.x < rc.right && pt.y >= 0 && pt.y < rc.bottom) {
                    parent := DllCall("GetParent", "Ptr", target, "Ptr")
                    ctrlId := DllCall("GetDlgCtrlID", "Ptr", target, "Int")
                    DllCall("SendMessage", "Ptr", parent, "UInt", 0x0111, "Ptr", ctrlId, "Ptr", target)
                }
            }
            return 0
        }
        return Subclass.Forward(this._oldProcs[target], hwnd, msg, wParam, lParam)
    }

    static _Paint(hwnd) {
        ps := PAINTSTRUCT()
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")
        rc := RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)

        s := this._state[hwnd]
        p := Dark.palette

        if s.accent
            bg := s.pressed ? p.AccentPressed : s.hover ? p.AccentHover : p.Accent
        else
            bg := s.pressed ? p.ControlActive : s.hover ? p.ControlHover : p.Control

        GDI.FillRect(hdc, rc, p.Background)
        GDI.RoundRect(hdc, rc, bg, Dark.Scale(8))
        oldFont := GDI.SelectFont(hdc, hwnd)
        GDI.DrawText(hdc, s.text, rc, p.TextPrimary)
        GDI.RestoreFont(hdc, oldFont)

        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
    }
}

class ComboBoxPainter extends Painter {
    static _cbs := Map(), _oldProcs := Map()

    static Apply(ctrl, opts := {}) {
        hwnd := ctrl.Hwnd
        ctrl.SetFont("c" Format("{:X}", Dark.palette.TextPrimary))
        GDI.RemoveBorder(hwnd)
        ; Get and style the dropdown list
        cbi := COMBOBOXINFO()
        cbi.cbSize := ObjGetDataSize(cbi)
        DllCall("GetComboBoxInfo", "Ptr", hwnd, "Ptr", cbi)
        if cbi.hwndList
            DllCall("uxtheme\SetWindowTheme", "Ptr", cbi.hwndList, "Str", "DarkMode_CFD", "Ptr", 0)
        Subclass.Install(hwnd, ObjBindMethod(this, "_Proc", hwnd), this._cbs, this._oldProcs)
    }

    static Remove(hwnd) {
        Subclass.Uninstall(hwnd, this._cbs, this._oldProcs)
    }

    static _Proc(target, hwnd, msg, wParam, lParam) {
        if msg = 0x000F {  ; WM_PAINT
            this._Paint(target)
            return 0
        }
        if msg = 0x0014  ; WM_ERASEBKGND
            return 1
        return Subclass.Forward(this._oldProcs[target], hwnd, msg, wParam, lParam)
    }

    static _Paint(hwnd) {
        ps := PAINTSTRUCT()
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")
        rc := RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := rc.right, h := rc.bottom
        p := Dark.palette

        ; Background
        GDI.FillRect(hdc, rc, p.Background)
        GDI.RoundRect(hdc, rc, p.Control, Dark.Scale(6))

        ; Dropdown arrow
        arrowX := w - Dark.Scale(12)
        arrowY := h // 2
        halfW := Dark.Scale(4), arrowH := Dark.Scale(3)
        pen := DllCall("CreatePen", "Int", 0, "Int", Dark.Scale(2), "UInt", GDI.ToBGR(p.TextSecondary), "Ptr")
        oldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
        DllCall("MoveToEx", "Ptr", hdc, "Int", arrowX - halfW, "Int", arrowY - arrowH, "Ptr", 0)
        DllCall("LineTo", "Ptr", hdc, "Int", arrowX, "Int", arrowY + arrowH)
        DllCall("LineTo", "Ptr", hdc, "Int", arrowX + halfW, "Int", arrowY - arrowH)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldPen)
        DllCall("DeleteObject", "Ptr", pen)

        ; Text
        textLen := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x000E, "Ptr", 0, "Ptr", 0, "Int")
        if textLen > 0 {
            textBuf := Buffer((textLen + 1) * 2, 0)
            DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x000D, "Ptr", textLen + 1, "Ptr", textBuf)
            textRc := RECT()
            textRc.left := Dark.Scale(6), textRc.top := 0
            textRc.right := w - Dark.Scale(24), textRc.bottom := h
            oldFont := GDI.SelectFont(hdc, hwnd)
            GDI.DrawText(hdc, StrGet(textBuf, "UTF-16"), textRc, p.TextPrimary, 0x24)  ; DT_VCENTER | DT_SINGLELINE
            GDI.RestoreFont(hdc, oldFont)
        }

        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
    }
}

class GroupBoxPainter extends Painter {
    static _cbs := Map(), _oldProcs := Map()

    static Apply(ctrl, opts := {}) {
        Subclass.Install(ctrl.Hwnd, ObjBindMethod(this, "_Proc", ctrl.Hwnd), this._cbs, this._oldProcs)
    }

    static Remove(hwnd) {
        Subclass.Uninstall(hwnd, this._cbs, this._oldProcs)
    }

    static _Proc(target, hwnd, msg, wParam, lParam) {
        if msg = 0x000F {  ; WM_PAINT
            this._Paint(target)
            return 0
        }
        if msg = 0x0014  ; WM_ERASEBKGND
            return 1
        return Subclass.Forward(this._oldProcs[target], hwnd, msg, wParam, lParam)
    }

    static _Paint(hwnd) {
        ps := PAINTSTRUCT()
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")
        rc := RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        p := Dark.palette

        GDI.FillRect(hdc, rc, p.Background)

        ; Get text and font metrics
        oldFont := GDI.SelectFont(hdc, hwnd)
        textLen := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x000E, "Ptr", 0, "Ptr", 0, "Int")
        text := ""
        if textLen > 0 {
            textBuf := Buffer((textLen + 1) * 2, 0)
            DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x000D, "Ptr", textLen + 1, "Ptr", textBuf)
            text := StrGet(textBuf, "UTF-16")
        }

        tm := TEXTMETRICW()
        DllCall("GetTextMetrics", "Ptr", hdc, "Ptr", tm)
        tmH := tm.tmHeight

        ; Border
        borderY := tmH // 2
        borderRc := RECT()
        borderRc.left := 0, borderRc.top := borderY
        borderRc.right := rc.right, borderRc.bottom := rc.bottom
        pen := DllCall("CreatePen", "Int", 0, "Int", 1, "UInt", GDI.ToBGR(p.Border), "Ptr")
        nullBrush := DllCall("GetStockObject", "Int", 5, "Ptr")  ; HOLLOW_BRUSH
        oldPen2 := DllCall("SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
        oldBrush2 := DllCall("SelectObject", "Ptr", hdc, "Ptr", nullBrush, "Ptr")
        DllCall("RoundRect", "Ptr", hdc, "Int", borderRc.left, "Int", borderRc.top,
            "Int", borderRc.right, "Int", borderRc.bottom, "Int", Dark.Scale(6), "Int", Dark.Scale(6))
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldPen2)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldBrush2)
        DllCall("DeleteObject", "Ptr", pen)

        ; Title gap + text
        if text {
            textX := Dark.Scale(9)
            sz := SIZE()
            DllCall("GetTextExtentPoint32", "Ptr", hdc, "Str", text, "Int", StrLen(text), "Ptr", sz)
            gapRc := RECT()
            gapRc.left := textX - 2, gapRc.top := borderY - 1
            gapRc.right := textX + sz.cx + 2, gapRc.bottom := borderY + 1
            GDI.FillRect(hdc, gapRc, p.Background)
            textRc := RECT()
            textRc.left := textX, textRc.top := 0
            textRc.right := textX + sz.cx, textRc.bottom := tmH
            GDI.DrawText(hdc, text, textRc, p.TextPrimary, 0)  ; DT_LEFT
        }

        GDI.RestoreFont(hdc, oldFont)
        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
    }
}

class RadioPainter extends Painter {
    static Apply(ctrl, opts := {}) {
        DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        ctrl.SetFont("c" Format("{:X}", Dark.palette.TextPrimary))
    }
}

; ═══════════════════════════════════════════════════
; Tier 3 Painters — Complex Custom Draw
; ═══════════════════════════════════════════════════

class ListViewPainter extends Painter {
    static _cbs := Map(), _oldProcs := Map()

    static Apply(ctrl, opts := {}) {
        hwnd := ctrl.Hwnd
        p := Dark.palette
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        SendMessage(0x1001, 0, GDI.ToBGR(p.Surface), ctrl)
        SendMessage(0x1026, 0, GDI.ToBGR(p.Surface), ctrl)
        SendMessage(0x1024, 0, GDI.ToBGR(p.TextPrimary), ctrl)
        SendMessage(0x1051, 0, GDI.ToBGR(p.BorderSubtle), ctrl)
        GDI.RemoveBorder(hwnd)
        hHeader := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x101F, "Ptr", 0, "Ptr", 0, "Ptr")
        if hHeader
            DllCall("uxtheme\SetWindowTheme", "Ptr", hHeader, "Str", "DarkMode_Explorer", "Ptr", 0)
        ctrl.OnNotify(-12, ObjBindMethod(this, "_OnCustomDraw", hwnd))
        Subclass.Install(hwnd, ObjBindMethod(this, "_Proc", hwnd), this._cbs, this._oldProcs)
    }

    static Remove(hwnd) {
        Subclass.Uninstall(hwnd, this._cbs, this._oldProcs)
    }

    static _OnCustomDraw(lvHwnd, ctrl, lParam) {
        nmcd := NMCUSTOMDRAW.At(lParam)
        p := Dark.palette
        switch nmcd.dwDrawStage {
            case 0x00000001:
                return 0x20
            case 0x00010001:
                if nmcd.uItemState & 1 {
                    DllCall("SetTextColor", "Ptr", nmcd.hdc, "UInt", GDI.ToBGR(p.TextPrimary))
                    DllCall("SetBkColor", "Ptr", nmcd.hdc, "UInt", GDI.ToBGR(p.Selection))
                } else {
                    DllCall("SetTextColor", "Ptr", nmcd.hdc, "UInt", GDI.ToBGR(p.TextPrimary))
                    DllCall("SetBkColor", "Ptr", nmcd.hdc, "UInt", GDI.ToBGR(p.Surface))
                }
                return 0x02
        }
        return 0
    }

    static _Proc(target, hwnd, msg, wParam, lParam) {
        if msg = 0x0085 || msg = 0x0014 || msg = 0x000F {
            result := Subclass.Forward(this._oldProcs[target], hwnd, msg, wParam, lParam)
            this._HideArrows(target)
            return result
        }
        return Subclass.Forward(this._oldProcs[target], hwnd, msg, wParam, lParam)
    }

    static _HideArrows(hwnd) {
        rc := RECT()
        DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rc)
        scrollW := DllCall("GetSystemMetrics", "Int", 2)
        hdc := DllCall("GetWindowDC", "Ptr", hwnd, "Ptr")
        w := rc.right - rc.left, h := rc.bottom - rc.top
        topRc := RECT()
        topRc.left := w - scrollW, topRc.top := 0, topRc.right := w, topRc.bottom := scrollW
        GDI.FillRect(hdc, topRc, Dark.palette.ScrollTrack)
        botRc := RECT()
        botRc.left := w - scrollW, botRc.top := h - scrollW, botRc.right := w, botRc.bottom := h
        GDI.FillRect(hdc, botRc, Dark.palette.ScrollTrack)
        DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc)
    }
}

class TabPainter extends Painter {
    static _cbs := Map(), _oldProcs := Map()

    static Apply(ctrl, opts := {}) {
        hwnd := ctrl.Hwnd
        uxtheme := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr")
        fn := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 133, "Ptr")
        if fn
            DllCall(fn, "Ptr", hwnd, "Int", 1)
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        Subclass.Install(hwnd, ObjBindMethod(this, "_Proc", hwnd), this._cbs, this._oldProcs)
    }

    static Remove(hwnd) {
        Subclass.Uninstall(hwnd, this._cbs, this._oldProcs)
    }

    static _Proc(target, hwnd, msg, wParam, lParam) {
        if msg = 0x000F {
            this._Paint(target)
            return 0
        }
        if msg = 0x0014
            return 1
        return Subclass.Forward(this._oldProcs[target], hwnd, msg, wParam, lParam)
    }

    static _Paint(hwnd) {
        ctx := GDI.BeginBuffered(hwnd)
        hdc := ctx.memDC, rc := ctx.rc
        p := Dark.palette
        GDI.FillRect(hdc, rc, p.Background)
        tabCount := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x1304, "Ptr", 0, "Ptr", 0, "Int")
        selIdx := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x130B, "Ptr", 0, "Ptr", 0, "Int")
        oldFont := GDI.SelectFont(hdc, hwnd)
        loop tabCount {
            i := A_Index - 1
            tabRc := RECT()
            DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x130A, "Ptr", i, "Ptr", tabRc)
            isSelected := (i = selIdx)
            if isSelected
                GDI.RoundRect(hdc, tabRc, p.ControlActive, Dark.Scale(6))
            textBuf := Buffer(512, 0)
            item := TCITEMW()
            item.mask := 0x1
            item.pszText := textBuf.Ptr
            item.cchTextMax := 255
            DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x133C, "Ptr", i, "Ptr", item)
            text := StrGet(textBuf, "UTF-16")
            GDI.DrawText(hdc, text, tabRc, isSelected ? p.TextPrimary : p.TextSecondary)
        }
        sepRc := RECT()
        DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x130A, "Ptr", 0, "Ptr", sepRc)
        lineRc := RECT()
        lineRc.left := 0, lineRc.top := sepRc.bottom
        lineRc.right := rc.right, lineRc.bottom := sepRc.bottom + 1
        GDI.FillRect(hdc, lineRc, p.Border)
        GDI.RestoreFont(hdc, oldFont)
        GDI.EndBuffered(ctx)
    }
}

class SliderPainter extends Painter {
    static _cbs := Map(), _oldProcs := Map()
    static _gdipToken := 0, _gdipReady := false

    static _InitGdip() {
        if this._gdipReady
            return
        si := GdiplusStartupInput()
        si.GdiplusVersion := 1
        token := 0
        DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", si, "Ptr", 0)
        this._gdipToken := token
        this._gdipReady := true
    }

    static _ShutdownGdip() {
        if this._gdipReady {
            DllCall("gdiplus\GdiplusShutdown", "Ptr", this._gdipToken)
            this._gdipReady := false
        }
    }

    static Apply(ctrl, opts := {}) {
        this._InitGdip()
        hwnd := ctrl.Hwnd
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", " ", "Str", " ")
        Subclass.Install(hwnd, ObjBindMethod(this, "_Proc", hwnd), this._cbs, this._oldProcs)
    }

    static Remove(hwnd) {
        Subclass.Uninstall(hwnd, this._cbs, this._oldProcs)
    }

    static _Proc(target, hwnd, msg, wParam, lParam) {
        if msg = 0x000F {
            this._Paint(target)
            return 0
        }
        if msg = 0x0014
            return 1
        return Subclass.Forward(this._oldProcs[target], hwnd, msg, wParam, lParam)
    }

    static _Paint(hwnd) {
        ctx := GDI.BeginBuffered(hwnd)
        hdc := ctx.memDC, rc := ctx.rc
        p := Dark.palette
        w := rc.right, h := rc.bottom
        GDI.FillRect(hdc, rc, p.Background)
        channelH := Dark.Scale(4)
        channelY := h // 2 - channelH // 2
        channelRc := RECT()
        channelRc.left := Dark.Scale(10), channelRc.top := channelY
        channelRc.right := w - Dark.Scale(10), channelRc.bottom := channelY + channelH
        GDI.RoundRect(hdc, channelRc, p.ControlActive, Dark.Scale(2))
        thumbRc := RECT()
        DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x0419, "Ptr", 0, "Ptr", thumbRc)
        thumbW := thumbRc.right - thumbRc.left
        thumbH := thumbRc.bottom - thumbRc.top
        diameter := Min(thumbW, thumbH) + Dark.Scale(6)
        centerX := thumbRc.left + thumbW // 2
        centerY := thumbRc.top + thumbH // 2 - Dark.Scale(2)
        pGraphics := 0
        DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdc, "Ptr*", &pGraphics)
        DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)
        pBrush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFFFFFFFF, "Ptr*", &pBrush)
        DllCall("gdiplus\GdipFillEllipse", "Ptr", pGraphics, "Ptr", pBrush,
            "Float", centerX - diameter / 2, "Float", centerY - diameter / 2,
            "Float", diameter * 1.0, "Float", diameter * 1.0)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
        accentARGB := 0xFF000000 | p.Accent
        pPen := 0
        borderW := Dark.Scale(4) * 1.0
        DllCall("gdiplus\GdipCreatePen1", "UInt", accentARGB, "Float", borderW, "Int", 2, "Ptr*", &pPen)
        DllCall("gdiplus\GdipDrawEllipse", "Ptr", pGraphics, "Ptr", pPen,
            "Float", centerX - diameter / 2 + borderW / 2,
            "Float", centerY - diameter / 2 + borderW / 2,
            "Float", diameter - borderW, "Float", diameter - borderW)
        DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
        GDI.EndBuffered(ctx)
    }
}

; ═══════════════════════════════════════════════════
; Tier 4 Painters — Composite
; ═══════════════════════════════════════════════════

class ScrollbarPainter {
    lv := 0, ctrl := 0, gui := 0
    isDragging := false, dragStartY := 0, dragStartPos := 0
    isHovering := false, syncTimer := 0
    w := 14, h := 0

    __New(guiObj, lv) {
        this.gui := guiObj, this.lv := lv
        this.w := Dark.Scale(14)
        rc := RECT()
        DllCall("GetWindowRect", "Ptr", lv.Hwnd, "Ptr", rc)
        pt := POINT()
        pt.x := rc.right, pt.y := rc.top
        DllCall("ScreenToClient", "Ptr", guiObj.Hwnd, "Ptr", pt)
        scrollW := DllCall("GetSystemMetrics", "Int", 2)
        this.h := rc.bottom - rc.top
        this.ctrl := guiObj.Add("Text",
            Format("x{} y{} w{} h{} +0xE", pt.x - scrollW, pt.y, this.w, this.h), "")
        this.syncTimer := ObjBindMethod(this, "Sync")
        SetTimer(this.syncTimer, 100)
    }

    Sync() {
        if !this.ctrl || !DllCall("IsWindow", "Ptr", this.lv.Hwnd)
            return
        DllCall("InvalidateRect", "Ptr", this.ctrl.Hwnd, "Ptr", 0, "Int", 1)
    }

    Paint(hdc) {
        rc := RECT()
        DllCall("GetClientRect", "Ptr", this.ctrl.Hwnd, "Ptr", rc)
        p := Dark.palette
        GDI.FillRect(hdc, rc, p.ScrollTrack)
        si := SCROLLINFO()
        si.cbSize := ObjGetDataSize(si)
        si.fMask := 0x17
        DllCall("GetScrollInfo", "Ptr", this.lv.Hwnd, "Int", 1, "Ptr", si)
        if si.nMax <= si.nMin
            return
        range := si.nMax - si.nMin + 1
        thumbH := Max(Dark.Scale(30), (si.nPage * this.h) // range)
        scrollRange := this.h - thumbH
        thumbY := scrollRange > 0 ? ((si.nPos - si.nMin) * scrollRange) // (range - si.nPage) : 0
        thumbRc := RECT()
        thumbRc.left := Dark.Scale(2), thumbRc.top := thumbY
        thumbRc.right := rc.right - Dark.Scale(2), thumbRc.bottom := thumbY + thumbH
        color := this.isHovering || this.isDragging ? p.ScrollThumbHover : p.ScrollThumb
        GDI.RoundRect(hdc, thumbRc, color, Dark.Scale(4))
    }

    Destroy() {
        if this.syncTimer
            SetTimer(this.syncTimer, 0)
    }
}

class MenuPainter {
    static ApplyPopups() {
        uxtheme := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr")
        SetPreferredAppMode := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 135, "Ptr")
        FlushMenuThemes := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 136, "Ptr")
        if SetPreferredAppMode
            DllCall(SetPreferredAppMode, "Int", 2)
        if FlushMenuThemes
            DllCall(FlushMenuThemes)
    }

    static ApplyToMenu(hMenu) {
        mi := MENUINFO()
        mi.cbSize := ObjGetDataSize(mi)
        mi.fMask := 0x10
        mi.hbrBack := GDI.Brush(Dark.palette.Surface)
        DllCall("SetMenuInfo", "Ptr", hMenu, "Ptr", mi)
    }
}


; ═══════════════════════════════════════════════════
; Dark — Main API
; ═══════════════════════════════════════════════════

class Dark {
    static palette := _InitPalette()

    static painters := Map(
        "Button", ButtonPainter,
        "Edit", EditPainter,
        "CheckBox", CheckBoxPainter,
        "Radio", RadioPainter,
        "TreeView", TreeViewPainter,
        "ListView", ListViewPainter,
        "ComboBox", ComboBoxPainter,
        "Slider", SliderPainter,
        "Progress", ProgressPainter,
        "ListBox", ListBoxPainter,
        "GroupBox", GroupBoxPainter,
        "Tab3", TabPainter,
        "StatusBar", StatusBarPainter,
        "DateTime", DateTimePainter,
        "MonthCal", MonthCalPainter,
        "Hotkey", HotkeyPainter,
        "UpDown", UpDownPainter,
        "Link", LinkPainter
    )

    static Scale(v) => Round(v * (A_ScreenDPI / 96))

    class Gui extends Gui {
        _darkHwnds := Map()

        __New(options := "", title := A_ScriptName) {
            super.__New(options, title)
            p := Dark.palette
            this.BackColor := Format("{:06X}", p.Background)
            this.SetFont("s9 c" Format("{:X}", p.TextPrimary), "Segoe UI")

            if VerCompare(A_OSVersion, "10.0.17763") >= 0 {
                attr := VerCompare(A_OSVersion, "10.0.18985") >= 0 ? 20 : 19
                DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.Hwnd, "Int", attr, "Int*", true, "Int", 4)
            }

            MenuPainter.ApplyPopups()

            this._winProc := ObjBindMethod(this, "_WndProc")
            this._winProcCb := CallbackCreate(this._winProc, , 4)
            setWL := A_PtrSize = 8 ? "SetWindowLongPtr" : "SetWindowLong"
            this._oldWndProc := DllCall(setWL, "Ptr", this.Hwnd, "Int", -4, "Ptr", this._winProcCb, "Ptr")
        }

        __Delete() {
            for hwnd, ctrlType in this._darkHwnds {
                if Dark.painters.Has(ctrlType)
                    Dark.painters[ctrlType].Remove(hwnd)
            }
            this._darkHwnds.Clear()
            if this.HasOwnProp("_oldWndProc") {
                setWL := A_PtrSize = 8 ? "SetWindowLongPtr" : "SetWindowLong"
                try DllCall(setWL, "Ptr", this.Hwnd, "Int", -4, "Ptr", this._oldWndProc, "Ptr")
                CallbackFree(this._winProcCb)
            }
        }

        Add(controlType, options := "", content?) {
            accent := InStr(options, "+Accent")
            if accent
                options := StrReplace(options, "+Accent", "")

            if controlType = "Text" && !RegExMatch(options, "i)\bc[0-9A-Fa-f]+\b")
                options .= " c" Format("{:X}", Dark.palette.TextPrimary)

            ctrl := super.Add(controlType, options, content?)

            if Dark.painters.Has(controlType) {
                Dark.painters[controlType].Apply(ctrl, { accent: !!accent })
                this._darkHwnds[ctrl.Hwnd] := controlType
            }

            return ctrl
        }

        _WndProc(hwnd, msg, wParam, lParam) {
            p := Dark.palette
            if msg = 0x0133 {
                DllCall("SetTextColor", "Ptr", wParam, "UInt", GDI.ToBGR(p.TextPrimary))
                DllCall("SetBkColor", "Ptr", wParam, "UInt", GDI.ToBGR(p.Control))
                return GDI.Brush(p.Control)
            }
            if msg = 0x0134 {
                DllCall("SetTextColor", "Ptr", wParam, "UInt", GDI.ToBGR(p.TextPrimary))
                DllCall("SetBkColor", "Ptr", wParam, "UInt", GDI.ToBGR(p.Surface))
                return GDI.Brush(p.Surface)
            }
            if msg = 0x0135 {
                DllCall("SetBkColor", "Ptr", wParam, "UInt", GDI.ToBGR(p.Background))
                return GDI.Brush(p.Background)
            }
            if msg = 0x0136 {
                return GDI.Brush(p.Background)
            }
            if msg = 0x0138 {
                DllCall("SetTextColor", "Ptr", wParam, "UInt", GDI.ToBGR(p.TextPrimary))
                DllCall("SetBkMode", "Ptr", wParam, "Int", 1)
                return GDI.Brush(p.Background)
            }
            return DllCall("CallWindowProc", "Ptr", this._oldWndProc, "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
        }
    }
}

OnExit((*) => (GDI.Destroy(), SliderPainter._ShutdownGdip()))
