; Easy Window Dragging -- KDE style (based on the v1 script by Jonny)
; https://www.autohotkey.com
; This script makes it much easier to move or resize a window: 1) Hold down
; the ALT key and LEFT-click anywhere inside a window to drag it to a new
; location; 2) Hold down ALT and RIGHT-click-drag anywhere inside a window
; to easily resize it; 3) Press ALT twice, but before releasing it the second
; time, left-click to minimize the window under the mouse cursor, right-click
; to maximize it, or middle-click to close it.

; The Double-Alt modifier is activated by pressing
; Alt twice, much like a double-click. Hold the second
; press down until you click.
;
; The shortcuts:
;  Alt + Left Button  : Drag to move a window.
;  Alt + Right Button : Drag to resize a window.
;  Double-Alt + Left Button   : Minimize a window.
;  Double-Alt + Right Button  : Maximize/Restore a window.
;  Double-Alt + Middle Button : Close a window.
;
; You can optionally release Alt after the first
; click rather than holding it down the whole time.

; This is the setting that runs smoothest on my
; system. Depending on your video card and cpu
; power, you may want to raise or lower this value.
SetWinDelay 2
CoordMode "Mouse"

g_DoubleAlt := false

!LButton::
{
    global g_DoubleAlt
    if g_DoubleAlt
    {
        MouseGetPos ,, &KDE_id
        PostMessage 0x0112, 0xf020,,, KDE_id
        g_DoubleAlt := false
        return
    }
    MouseGetPos &KDE_X1, &KDE_Y1, &KDE_id
    if WinGetMinMax(KDE_id)
        return
    WinGetPos &KDE_WinX1, &KDE_WinY1,,, KDE_id
    Loop
    {
        if !GetKeyState("LButton", "P")
            break
        MouseGetPos &KDE_X2, &KDE_Y2
        KDE_X2 -= KDE_X1
        KDE_Y2 -= KDE_Y1
        KDE_WinX2 := (KDE_WinX1 + KDE_X2)
        KDE_WinY2 := (KDE_WinY1 + KDE_Y2)
        WinMove KDE_WinX2, KDE_WinY2,,, KDE_id
    }
}

!RButton::
{
    global g_DoubleAlt
    if g_DoubleAlt
    {
        MouseGetPos ,, &KDE_id
        if WinGetMinMax(KDE_id)
            WinRestore KDE_id
        Else
            WinMaximize KDE_id
        g_DoubleAlt := false
        return
    }
    MouseGetPos &KDE_X1, &KDE_Y1, &KDE_id
    if WinGetMinMax(KDE_id)
        return
    WinGetPos &KDE_WinX1, &KDE_WinY1, &KDE_WinW, &KDE_WinH, KDE_id
    if (KDE_X1 < KDE_WinX1 + KDE_WinW / 2)
        KDE_WinLeft := 1
    else
        KDE_WinLeft := -1
    if (KDE_Y1 < KDE_WinY1 + KDE_WinH / 2)
        KDE_WinUp := 1
    else
        KDE_WinUp := -1
    Loop
    {
        if !GetKeyState("RButton", "P")
            break
        MouseGetPos &KDE_X2, &KDE_Y2
        WinGetPos &KDE_WinX1, &KDE_WinY1, &KDE_WinW, &KDE_WinH, KDE_id
        KDE_X2 -= KDE_X1
        KDE_Y2 -= KDE_Y1
        WinMove KDE_WinX1 + (KDE_WinLeft+1)/2*KDE_X2
              , KDE_WinY1 +   (KDE_WinUp+1)/2*KDE_Y2
              , KDE_WinW  -     KDE_WinLeft  *KDE_X2
              , KDE_WinH  -       KDE_WinUp  *KDE_Y2
              , KDE_id
        KDE_X1 := (KDE_X2 + KDE_X1)
        KDE_Y1 := (KDE_Y2 + KDE_Y1)
    }
}

!MButton::
{
    global g_DoubleAlt
    if g_DoubleAlt
    {
        MouseGetPos ,, &KDE_id
        WinClose KDE_id
        g_DoubleAlt := false
        return
    }
}

~Alt::
{
    global g_DoubleAlt := (A_PriorHotkey = "~Alt" and A_TimeSincePriorHotkey < 400)
    Sleep 0
    KeyWait "Alt"
}
