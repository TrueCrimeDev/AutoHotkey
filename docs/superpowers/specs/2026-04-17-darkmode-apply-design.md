# DarkMode.ahk — Apply-Based Dark Mode Framework

**Date:** 2026-04-17
**Target:** AutoHotkey v2.1-alpha.26+
**Replaces:** existing `DarkMode.ahk` (overwrite in place)

## Goal

A single-file dark-mode framework for AHK v2 GUIs. Primary entry is `Dark.Apply(gui)` — retrofit any existing `Gui` instance. Factory `Dark.Gui(opts, title)` is sugar over Apply. No `Dark.Gui extends Gui` class; everything is instance-level so users can retrofit their own Gui subclasses.

## Public API

```
Dark.Apply(gui)                 ; theme a Gui + hook future .Add; idempotent
Dark.Gui(opts?, title?)         ; new Gui() + Dark.Apply; returns Gui
Dark.Palette                    ; Map of color name → 0xRRGGBB; writable pre-use
Dark.SetColor(name, value)      ; update color + recreate brush at runtime
Dark.TitleBar(hwnd)             ; apply DWM dark titlebar to any HWND
Dark.Menu()                     ; apply uxtheme dark mode to all app menus
Dark.Subclass                   ; { Install, Uninstall, DefSubclass } utility
Dark.Painters                   ; Map of controlType → painter class (read-only-ish)
```

Accent buttons: include `+Accent` in options; Dark.Apply's Add hook strips it before forwarding to super.Add and stores the flag for ButtonPainter.

Opt-out: include `+NoDark` in options to skip theming for a single control.

## Architecture (layers)

1. **Win32 structs** (alpha.26 `Struct`): RECT, POINT, SIZE, NMHDR, NMCUSTOMDRAW, PAINTSTRUCT, SCROLLINFO, TRACKMOUSEEVENT, DRAWITEMSTRUCT, MEASUREITEMSTRUCT, NMLVCUSTOMDRAW, NMTBCUSTOMDRAW.
2. **Foundation**: DarkTheme (palette + brush/pen cache + refcount + OnExit cleanup), DarkSubclass (CallbackCreate + SetWindowSubclass/RemoveWindowSubclass wrappers, DefSubclass helper), DarkGDI (brush/pen/font helpers, DrawTextW wrapper, RoundRect).
3. **Painters** — one class per control type, each with a static `Apply(ctrl, flags?)` method:
   - **Tier 1 (theme-only)**: Edit, TreeView, ListBox, Progress, CheckBox, Hotkey, DateTime, MonthCal, UpDown, Link, StatusBar. Single uxtheme SetWindowTheme call + color font.
   - **Tier 2 (subclassed)**: ComboBox, DDL, GroupBox, Radio (via text-label trick).
   - **Tier 3 (custom-draw)**: Button, ListView (+header), Slider, Tab, Scrollbar (non-client paint), Menu (owner-draw via WndProc).
4. **Registry**: `Dark.Painters` Map; Dark.Apply iterates `gui` children once and dispatches; instance-level `DefineProp("Add", ...)` keeps future Adds themed.
5. **Window-level**: Dark.Apply also installs a parent WndProc subclass for WM_CTLCOLOR*, WM_NCPAINT (for scrollbar repaint), WM_MENUCHAR, WM_UAHDRAWMENU* if menubar present. Titlebar via DWM attrs 19/20 (dark), 34/35/36 (Win11 colors).

## Prototype extension pattern

For every simple control type, install `SetDarkMode(ctrl)` on `Gui.<Type>.Prototype` at script load via `static __New` in a single `DarkPrototypes` class. Painters can then call `ctrl.SetDarkMode()` or just reuse the prototype method. This matches the DarkModeModular idiom and means stock `Gui()` windows can opt-in per-control if they don't want to use Dark.Apply for some reason.

## Retrofit mechanics (`Dark.Apply`)

```
Dark.Apply(gui):
  if gui has already been applied → return
  mark gui._dark := {applied: true, hwnds: Map()}
  Dark.TitleBar(gui.Hwnd)
  Dark.Menu()
  install parent WndProc subclass
  for ctrl in gui:
      dispatch(ctrl)     ; look up Dark.Painters[ctrl.Type], call painter.Apply
  gui.DefineProp("Add", { Call: wrapAdd })     ; per-instance Add hook

wrapAdd(gui, controlType, options?, content?):
  parse +Accent, +NoDark from options, strip them
  ctrl := originalAdd(gui, controlType, strippedOpts, content?)
  if !NoDark: dispatch(ctrl, {accent: isAccent})
  return ctrl
```

`gui.OnEvent("Close", …)` registers a one-shot cleanup that walks stored hwnds and Uninstalls any subclasses, drops refcount.

## Naming & paths

- File: `DarkMode.ahk` at repo root.
- Namespace: `Dark` class (static-only; never instantiated).
- Internal classes: `DarkTheme`, `DarkSubclass`, `DarkGDI`, `DarkPrototypes`, and per-painter classes `DarkButton`, `DarkListView`, `DarkComboBox`, `DarkSlider`, `DarkTab`, `DarkScrollbar`, `DarkMenu`, `DarkGroupBox`, `DarkRadio`, `DarkTitleBar`, `DarkWindowProc`.
- Painters implement: `static Apply(ctrl, opts?)` and optional `static Remove(hwnd)`.

## Testing

- `examples/DarkModeShowcase.ahk` — one window demonstrating every control type, accent buttons, live palette swap.
- Syntax check via `bin\AutoHotkey64.exe check DarkMode.ahk` (must exit 0).
- Manual visual verification on Win11.

## Scope / non-goals

- No light-mode toggle (users can restart the script).
- No per-control runtime color override API (use Palette + SetColor + force repaint).
- No MDI / child-Gui tree traversal beyond direct children (composites handle their own).
- No version-fallback code paths; alpha.26 is the floor.
