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
