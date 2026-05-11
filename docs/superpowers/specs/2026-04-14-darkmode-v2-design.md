# DarkMode v2 — Design Spec

## Overview

A complete rewrite of the DarkGui framework (currently `Alpha22_Example.ahk`, 2770 lines) using AutoHotkey v2.1-alpha.26 features. Targets ~1400-1600 lines with better OOP, full control coverage, and zero repeated GDI boilerplate.

**File:** `DarkMode.ahk` (single self-contained file)
**API:** `Dark.Gui()` — one-line activation, clean break from old API
**Theme:** Single opinionated dark palette matching the project design system, customizable per-field before GUI creation

## Architecture

Three layers:

```
Dark.Gui (user API)
    |
Painter Registry (control type -> Painter class)
    |
Foundation (GDI helper, Palette struct, Win32 structs, Subclass utility)
```

### Layer 1: Foundation

#### Win32 Structs

Native alpha.26 struct definitions replace all `Buffer + NumPut/NumGet` patterns. Existing structs carried forward: RECT, POINT, SIZE, NMHDR, NMCUSTOMDRAW, PAINTSTRUCT, SCROLLBARINFO, SCROLLINFO, TRACKMOUSEEVENT, COMBOBOXINFO.

New structs added:

- `TCITEMW` — tab control item (replaces manual 32/64-bit offset calculations in _DarkTab)
- `HDITEMW` — ListView header item (replaces raw Buffer in _DarkListView)
- `MENUINFO` — menu styling (replaces raw Buffer in DarkMenuBar)
- `TEXTMETRICW` — font metrics (replaces raw Buffer in _DarkGroupBox)
- `GdiplusStartupInput` — GDI+ init (replaces raw Buffer in _DarkSlider)

All structs handle 32/64-bit pointer sizes automatically via `uptr`/`iptr` types.

#### Palette Struct

Single struct with every color as a `u32` field. One global instance at `Dark.palette`. Replaces `DarkTheme.Colors` Map (eliminates hash lookups and string keys).

```ahk
Struct Palette {
    ; Backgrounds
    Background: u32       ; 0x0F0F0F
    Surface: u32          ; 0x121212
    Header: u32           ; 0x141414
    Elevated: u32         ; 0x1A1A1A

    ; Borders
    Border: u32           ; 0x303030
    BorderSubtle: u32     ; 0x232323
    BorderHover: u32      ; 0x505050

    ; Accents
    Accent: u32           ; 0x5B9FEF
    AccentHover: u32      ; 0x7AB3F5
    AccentPressed: u32    ; 0x4A8AD4
    Success: u32          ; 0x7BC96F
    Warning: u32          ; 0xF59E42
    Error: u32            ; 0xDC3545
    Info: u32             ; 0x22D3EE

    ; Text
    TextPrimary: u32      ; 0xFFFFFF
    TextSecondary: u32    ; 0xA0A0A0
    TextMuted: u32        ; 0x606060
    TextDisabled: u32     ; 0x4A4A4A

    ; Controls
    Control: u32          ; 0x202020
    ControlHover: u32     ; 0x2A2A2A
    ControlActive: u32    ; 0x333333
    Selection: u32        ; 0x264F78

    ; Scrollbar
    ScrollTrack: u32      ; 0x1A1A1A
    ScrollThumb: u32      ; 0x404040
    ScrollThumbHover: u32 ; 0x555555
}
```

User customization: modify `Dark.palette` fields before creating `Dark.Gui()`.

#### GDI Helper Class

Static class centralizing all GDI operations. Eliminates ~50 create/fill/delete cycles and ~100 RGBtoBGR calls.

**Color conversion:** `GDI.ToBGR(rgb)` — internal, callers pass RGB always.

**Brush cache:** `GDI.Brush(rgb)` — returns cached HBRUSH, keyed by BGR value. All brushes freed on app exit via `GDI.Destroy()`.

**Drawing primitives:**
- `GDI.FillRect(hdc, rc, color)` — fill rectangle with cached brush
- `GDI.RoundRect(hdc, rc, color, radius)` — rounded rect with auto pen+brush creation/cleanup
- `GDI.DrawText(hdc, text, rc, color, flags?)` — SetTextColor + DrawTextW
- `GDI.FrameRect(hdc, rc, color)` — border only

**Double-buffer helper:**
- `GDI.BeginPaint(hwnd)` — returns context object `{ hdc, memDC, bitmap, rc, ps }`
- `GDI.EndPaint(ctx)` — BitBlt + cleanup of memDC/bitmap

**Temp resource helper:**
- `GDI.TempBrush(rgb)` — creates a brush that must be manually deleted (for one-shot use in owner-draw where cached brush isn't appropriate)
- `GDI.TempPen(rgb, width)` — same for pens

#### Subclass Utility

Carried forward from current framework — `SetWindowLongPtr` abstraction for message routing. Already clean, no changes needed.

#### DPI Scaling

`Dark.Scale(value)` — DPI-aware scaling using `GetDpiForWindow` or `GetDeviceCaps`. Applied consistently to all padding, radius, and spacing values.

### Layer 2: Painter Registry

#### Painter Base Class

```ahk
class Painter {
    static Apply(ctrl, opts)  ; Called once when control is added. Sets theme + subclass.
    static Remove(hwnd)       ; Called on cleanup. Removes subclass.
}
```

All painters are static-only classes (no instances). They extend `Painter` and override `Apply()`. Owner-drawn painters also provide an `OnDraw()` static method.

`opts` is a simple object with parsed options: `{ accent: bool }`.

#### Control Tiers

**Tier 1 — Theme-only** (SetWindowTheme + SendMessage colors, 5-10 lines each):
- `EditPainter` — DarkMode_Explorer theme, EM_SETBKGNDCOLOR, remove border
- `CheckBoxPainter` — DarkMode_Explorer theme, font color
- `TreeViewPainter` — DarkMode_Explorer theme, TVM_SETBKCOLOR/SETTEXTCOLOR/SETLINECOLOR, remove border
- `ProgressPainter` — PBM_SETBKCOLOR, accent bar color
- `ListBoxPainter` — DarkMode_Explorer theme, font color, remove border
- `HotkeyPainter` — same pattern as Edit
- `UpDownPainter` — DarkMode_Explorer theme
- `LinkPainter` — font color to TextPrimary
- `DateTimePainter` — DarkMode_Explorer theme, DTM_SETMCCOLOR
- `MonthCalPainter` — DarkMode_Explorer theme, MCM_SETCOLOR
- `StatusBarPainter` — SB_SETBKCOLOR, font color

**Tier 2 — Subclassed** (message interception, 30-60 lines each):
- `ButtonPainter` — BS_OWNERDRAW, WM_DRAWITEM handler. Rounded rect with hover/pressed states via WM_MOUSEMOVE/WM_MOUSELEAVE tracking. Accent variant uses `Dark.palette.Accent*` colors, default uses `Dark.palette.Control*` colors.
- `ComboBoxPainter` — WM_PAINT override. Rounded rect body, custom dropdown arrow via MoveToEx/LineTo, text retrieval via WM_GETTEXT.
- `GroupBoxPainter` — WM_PAINT override. Rounded border with title gap. Uses TEXTMETRICW struct for font height, SIZE struct for title width.
- `RadioPainter` — Native radio made invisible (WS_VISIBLE kept, BS_PUSHLIKE style). Separate Text control for label. DefineProp to bridge `.Text` and `.Value` between the pair.

**Tier 3 — Complex** (full custom draw, 80-150 lines each):
- `ListViewPainter` — NM_CUSTOMDRAW callback for items + header custom draw. Uses NMCUSTOMDRAW struct via Struct.At() for zero-copy. HDITEMW struct for header text. Scrollbar arrow hiding via region clipping. Selection colors via SetBkColor/SetTextColor in CDDS_ITEMPREPAINT.
- `TabPainter` — Full owner-draw via WM_PAINT. Double-buffered via GDI.BeginPaint/EndPaint. TCITEMW struct for tab text. Rounded pill for selected tab. Separator line between tabs and content.
- `SliderPainter` — GDI+ anti-aliased thumb. Double-buffered. GdiplusStartupInput struct for init. Channel drawn with GDI, knob drawn with GDI+ FillEllipse + DrawEllipse for anti-aliasing. GDI+ initialized once, cleaned up on exit.

**Tier 4 — Composite** (multi-component):
- `ScrollbarPainter` — Dark scrollbar overlay for ListView. Text control positioned over native scrollbar. Syncs via timer + LVM_ENSUREVISIBLE. Mouse drag for thumb, click for page-up/down.
- `MenuPainter` — Dark menu bar (Text controls as labels) + dark popup menus (MENUINFO struct for background brush, uxtheme ordinals 133/135/136 for dark mode). Optional toolbar row.

### Layer 3: Dark.Gui

#### Public API

```ahk
; Create dark GUI (one line)
myGui := Dark.Gui(options?, title?)

; Add controls (identical to native Gui.Add, auto-dark)
ctrl := myGui.Add(controlType, options?, content?)

; Optional: dark menu bar
myGui.SetDarkMenuBar(labels, menus, toolbarItems?)

; Show (native)
myGui.Show(options?)
```

#### Internal Flow

**`__New(options?, title?)`:**
1. `super.__New(options, title)`
2. `this.BackColor := Dark.palette.Background`
3. `this.SetFont("s9 c" Format("{:X}", Dark.palette.TextPrimary), "Segoe UI")`
4. Dark title bar: `DwmSetWindowAttribute(hwnd, 20, &true, 4)` (or attr 19 on older Win10)
5. Dark menus: uxtheme ordinals 135 (SetPreferredAppMode), 136 (FlushMenuThemes)
6. Install WM_CTLCOLOR* handler via window subclass
7. Track in `this._darkHwnds` Map for cleanup

**`Add(controlType, options?, content?)`:**
1. Parse `+Accent` from options string
2. `ctrl := super.Add(controlType, options, content?)`
3. `if Dark.painters.Has(controlType)` → `Dark.painters[controlType].Apply(ctrl, { accent })`
4. `this._darkHwnds[ctrl.Hwnd] := controlType`
5. Return ctrl

**`__Delete()`:**
1. For each tracked hwnd: `Dark.painters[type].Remove(hwnd)`
2. Uninstall window subclass
3. Clear tracking map

#### WM_CTLCOLOR Handler

Installed as window subclass. Handles:
- `WM_CTLCOLOREDIT` (0x0133) — SetTextColor to TextPrimary, SetBkColor to Control, return Control brush
- `WM_CTLCOLORLISTBOX` (0x0134) — same pattern
- `WM_CTLCOLORBTN` (0x0135) — SetBkColor to Background, return Background brush
- `WM_CTLCOLORSTATIC` (0x0138) — detect if Radio text control vs. other static, apply appropriate colors
- `WM_CTLCOLORDLG` (0x0136) — return Background brush

All colors read from `Dark.palette`, all brushes from `GDI.Brush()`.

### Dark Class (Container)

The `Dark` class serves as the namespace for everything:

```ahk
class Dark {
    static palette := Palette()  ; initialized with defaults

    static painters := Map(
        "Button",    ButtonPainter,
        "Edit",      EditPainter,
        ; ... all 18 painters
    )

    static Scale(v) => ...  ; DPI scaling

    class Gui extends Gui {
        ; ... as described above
    }
}
```

## File Organization

All in `DarkMode.ahk`, ordered:

1. `#Requires AutoHotkey v2.1-alpha.26`
2. Win32 struct definitions (~80 lines)
3. Palette struct + defaults (~40 lines)
4. GDI helper class (~100 lines)
5. Subclass utility (~50 lines)
6. Painter base class (~10 lines)
7. Tier 1 painters — theme-only (~120 lines total)
8. Tier 2 painters — subclassed (~200 lines total)
9. Tier 3 painters — complex (~350 lines total)
10. Tier 4 painters — composite (~300 lines total)
11. Dark class + Dark.Gui (~150 lines)
12. WM_CTLCOLOR handler (~60 lines)
13. Initialization (palette defaults, GDI+ init, exit cleanup) (~40 lines)

**Estimated total: ~1500 lines**

## What's NOT Included

- Showcase/demo code — separate example file
- Multiple theme support — single palette, user modifies fields
- CSS-like cascading styles — out of scope
- Backward compatibility with Alpha22_Example.ahk API

## Key Alpha.26 Features Used

1. **Struct memory co-allocation** — Palette struct lives inline with Dark class, zero extra heap allocations
2. **Struct array alignment fix** — TCITEMW, HDITEMW structs align correctly on both 32/64-bit
3. **DllCall with unset** — output struct params auto-created where applicable
4. **Improved object construction** — Painter classes and GDI cache benefit from faster allocation
5. **Native Struct keyword** — all Win32 structs use alpha.22+ Struct, carried forward and expanded
6. **Struct.At()** — zero-copy pointer views for NM_CUSTOMDRAW notification handling
