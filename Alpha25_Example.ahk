/*
Alpha25_Example.ahk -- AutoHotkey v2.1-alpha.25 feature showcase

New features and fixes:
  1. ahk_opt for inline WinTitle search options
  2. Key-up hotkey consistency fixes
  3. Custom combo hotkeys with neutral modifiers
  4. DllCall safety: rejects array classes for return type
  5. Module system fixes (ModuleA.B init, wildcard imports)
  6. WinExist exclusion logic fixes
  7. GUI control calculations fix (Windows 7)
  8. Timer/MsgBox interaction fix

Run: bin\AutoHotkey64.exe Alpha25_Example.ahk
*/
#Requires AutoHotkey v2.1-alpha.25

stdout := FileOpen("*", "w", "UTF-8")
Print(text) => stdout.Write(text)
PrintLine(text := "") => stdout.Write(text "`n")

PrintLine "=== AutoHotkey v2.1-alpha.25 Feature Showcase ==="
PrintLine Format("Version: {}", A_AhkVersion)
PrintLine ""

; ─────────────────────────────────────────────────────
; 1. ahk_opt -- inline window search options
; ─────────────────────────────────────────────────────
PrintLine "── 1. ahk_opt (inline search options) ──"

; New WinTitle criterion: ahk_opt lets you override
; DetectHiddenWindows, SetTitleMatchMode, and DetectHiddenText
; directly in the WinTitle string -- no need to change globals.
;
; Supported options:
;   Hidden / Hidden1  -- detect hidden windows (for this call)
;   Hidden0           -- ignore hidden windows
;   HiddenText / HiddenText1  -- detect hidden text
;   HiddenText0       -- ignore hidden text
;   1 / 2 / 3 / RegEx -- title match mode
;   Fast / Slow       -- title find speed
;
; Syntax: "WinTitle ahk_opt Option1 Option2 ..."

; Example: find any window matching "Notepad" even if hidden
; (without changing DetectHiddenWindows globally)
hwnd := WinExist("Notepad ahk_opt Hidden 2")
PrintLine Format("  WinExist with ahk_opt Hidden 2: {}", hwnd ? "found" : "not found")

; Combine with other ahk_ criteria
hwnd := WinExist("ahk_class Shell_TrayWnd ahk_opt Hidden")
PrintLine Format("  Taskbar (ahk_class + ahk_opt Hidden): {}",
    hwnd ? Format("0x{:X}", hwnd) : "not found")

; ahk_opt with RegEx match mode
hwnd := WinExist("ahk_exe explorer.exe ahk_opt Hidden RegEx")
PrintLine Format("  Explorer (ahk_exe + ahk_opt Hidden RegEx): {}",
    hwnd ? Format("0x{:X}", hwnd) : "not found")

; Current global settings are NOT affected
PrintLine Format("  Global DetectHiddenWindows still: {}", A_DetectHiddenWindows)
PrintLine ""

; ─────────────────────────────────────────────────────
; 2. WinExist exclusion fixes
; ─────────────────────────────────────────────────────
PrintLine "── 2. WinExist exclusion fixes ──"

; Fixed: WinExist("A",,,"ExcludeText") no longer excludes
; windows that have no controls (was incorrectly excluding
; all controlless windows regardless of ExcludeText).

hwnd_a := WinExist("A")
PrintLine Format("  WinExist('A'): {}", hwnd_a ? Format("0x{:X}", hwnd_a) : "none")

; Fixed: WinExist("", "Text") no longer retrieves the title
; of every window to check -- performance improvement.
PrintLine "  WinExist('', 'Text') no longer reads all window titles"
PrintLine "  WinExist('A',,,'Excl') exclusion logic corrected"
PrintLine ""

; ─────────────────────────────────────────────────────
; 3. DllCall safety: array class rejection
; ─────────────────────────────────────────────────────
PrintLine "── 3. DllCall rejects array return types ──"

; Previously, passing a struct array class as a DllCall return
; type caused a crash. Now it raises a proper error.
;
; Example (would error, not crash):
;   Struct POINT { x: i32, y: i32 }
;   DllCall("SomeFunc", POINT[3])  ; Error in alpha.25, crash before

Struct POINT {
    x: i32
    y: i32
}

PrintLine "  DllCall now rejects array classes for return type"
PrintLine "  POINT[3] as return type -> proper error (was crash)"
PrintLine ""

; ─────────────────────────────────────────────────────
; 4. Struct.Ptr.__Value moved to Struct.Ptr
; ─────────────────────────────────────────────────────
PrintLine "── 4. Struct.Ptr.__Value consolidation ──"

; .Ptr.Prototype.__Value has been moved from individual struct
; classes up to Struct.Ptr. This means all struct pointer types
; inherit the same __Value behavior, reducing redundancy.

Struct Vec2 {
    x: Float32
    y: Float32
}

v := Vec2()
v.x := 10.5
v.y := 20.5
PrintLine Format("  Vec2({:.1f}, {:.1f}) -- Ptr type works via Struct.Ptr.__Value",
    v.x, v.y)
PrintLine ""

; ─────────────────────────────────────────────────────
; 5. Hotkey fixes
; ─────────────────────────────────────────────────────
PrintLine "── 5. Hotkey behavior fixes ──"

; Several key handling fixes in alpha.25:
;
; a) Key-up hotkeys now fire consistently when used as both
;    prefix and suffix:
;      LCtrl::Send "hello"      ; LCtrl as prefix
;      LCtrl up::ToolTip "up"   ; LCtrl up as suffix
;    Previously the up hotkey might not fire reliably.
;
; b) Custom combo hotkeys with neutral modifiers:
;      Alt & Esc::MsgBox "works"
;    Neutral modifier (Alt instead of LAlt/RAlt) now works
;    correctly as a prefix key in custom combos.
;
; c) Key suppression now depends on SendLevel:
;    A hotkey at SendLevel 0 won't suppress keys sent
;    at SendLevel > 0, making layered hotkey scripts
;    more predictable.
;
; These are behavioral fixes -- they can't be demonstrated
; in console output, but affect all hotkey scripts.

PrintLine "  Key-up hotkeys fire consistently (prefix+suffix)"
PrintLine "  Custom combos with neutral modifiers (Alt & Esc::)"
PrintLine "  Key suppression respects SendLevel"
PrintLine ""

; ─────────────────────────────────────────────────────
; 6. Module system fixes
; ─────────────────────────────────────────────────────
PrintLine "── 6. Module system fixes ──"

; Several fixes to the module/import system:
;
; a) ModuleA.B now properly initializes classes and imported
;    modules when accessed. Previously, accessing a sub-module
;    could skip initialization.
;
; b) A.B where B is wildcard-imported into module A now works
;    correctly. Previously this would fail silently.
;
; c) Fixed crash when calling an unset global via a Module object.
;    Now raises a proper error instead of segfaulting.
;
; d) Fixed conflict between `global g` in a function and a
;    prior `export global g` in the same module.
;
; Example (requires separate module files):
;
;   ; mylib.ahk
;   #Module MyLib
;   export class Config {
;       static version := "1.0"
;   }
;
;   ; app.ahk
;   #Import MyLib
;   MsgBox MyLib.Config.version  ; now initializes correctly

PrintLine "  ModuleA.B initializes classes on access"
PrintLine "  Wildcard imports resolve correctly in A.B"
PrintLine "  Unset globals via Module -> error, not crash"
PrintLine "  `global g` / `export global g` conflict resolved"
PrintLine ""

; ─────────────────────────────────────────────────────
; 7. GUI and timer fixes
; ─────────────────────────────────────────────────────
PrintLine "── 7. GUI and timer fixes ──"

; a) Fixed GUI control calculations that caused a Critical Error
;    dialog on Windows 7. The control sizing math produced invalid
;    values on older Windows versions.
;
; b) Fixed timer threads interrupting MsgBox before the window
;    is fully shown. Previously a timer could fire in the gap
;    between MsgBox creation and display, causing odd behavior.
;
; Example of the timer fix (not executed in console):
;
;   SetTimer () => ToolTip("tick"), 100
;   MsgBox "This MsgBox is no longer interrupted during creation"
;   ; Previously, the timer could fire between MsgBox() call
;   ; and the dialog appearing, potentially re-entering code.

PrintLine "  GUI control sizing fixed for Windows 7"
PrintLine "  Timer threads wait for MsgBox to fully display"
PrintLine ""

; ─────────────────────────────────────────────────────
; 8. Practical demo: ahk_opt in action
; ─────────────────────────────────────────────────────
PrintLine "── 8. Practical: window enumeration with ahk_opt ──"

; Use ahk_opt to find hidden system windows without
; changing the global DetectHiddenWindows setting.
; This is the main user-facing feature of alpha.25.

found := []

; Find common system windows that are usually hidden
for title in ["Program Manager", "MSCTFIME UI", "Default IME"] {
    hwnd := WinExist(title " ahk_opt Hidden 1")
    if hwnd
        found.Push(Format("{} (0x{:X})", title, hwnd))
}

; Also check with class-based matching
hwnd := WinExist("ahk_class Progman ahk_opt Hidden")
if hwnd
    found.Push(Format("Progman class (0x{:X})", hwnd))

PrintLine Format("  Found {} hidden system windows:", found.Length)
for item in found
    PrintLine Format("    • {}", item)
PrintLine ""

; ─────────────────────────────────────────────────────
; Summary
; ─────────────────────────────────────────────────────
PrintLine "═══════════════════════════════════════════════"
PrintLine "Alpha.25 is a stability + compatibility release:"
PrintLine "  • ahk_opt: inline WinTitle search options"
PrintLine "  • Key-up hotkeys fire reliably as prefix+suffix"
PrintLine "  • Custom combos with neutral modifiers work"
PrintLine "  • DllCall rejects array return types (safety)"
PrintLine "  • Module initialization and import fixes"
PrintLine "  • WinExist exclusion logic corrected"
PrintLine "  • GUI sizing fix for Windows 7"
PrintLine "  • Timer/MsgBox interaction fix"
PrintLine "═══════════════════════════════════════════════"
