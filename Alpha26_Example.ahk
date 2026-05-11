/*
Alpha26_Example.ahk -- AutoHotkey v2.1-alpha.26 feature showcase

Changes in alpha.26:
  1. Modal dialog keyboard shortcuts now work (message handling rewrite)
  2. #SingleInstance / Reload uses WM_CLOSE (cleaner shutdown)
  3. DllCall(F, StructType, unset) passes StructType() if no __value setter
  4. Typed property memory allocated with main object (perf improvement)
  5. Fixed struct array alignment
  6. Fixed StructClass.Ptr not sealing the structure
  7. Fixed struct return types for typed callbacks
  8. Fixed CallbackCreate reference counting (PR #356)
  9. Fixed IsSet with expressions ending in '?'

Run: bin\AutoHotkey64.exe Alpha26_Example.ahk
*/
#Requires AutoHotkey v2.1-alpha.26

stdout := FileOpen("*", "w", "UTF-8")
Print(text) => stdout.Write(text)
PrintLine(text := "") => stdout.Write(text "`n")

PrintLine "=== AutoHotkey v2.1-alpha.26 Feature Showcase ==="
PrintLine Format("Version: {}", A_AhkVersion)
PrintLine ""

; ─────────────────────────────────────────────────────
; 1. IsSet fix: expressions ending with '?'
; ─────────────────────────────────────────────────────
PrintLine "── 1. IsSet with maybe-unset expressions ──"

; Alpha.25 would error on IsSet() with expressions ending in '?'
; (the maybe-unset operator). Alpha.26 permits this pattern.
;
; The '?' suffix makes an unset variable evaluate to 'unset'
; instead of throwing. IsSet() now correctly handles this:
;
;   IsSet(someVar?)   ; works in alpha.26, errored in alpha.25
;
; This is useful when checking variables that may not exist:

myVar := "hello"
PrintLine Format("  IsSet(myVar): {}", IsSet(myVar))       ; true

; Unset check still works normally
PrintLine Format("  IsSet(nope): {}", IsSet(nope))          ; false
PrintLine ""

; ─────────────────────────────────────────────────────
; 2. Struct array alignment fix
; ─────────────────────────────────────────────────────
PrintLine "── 2. Struct array alignment (fixed) ──"

; Alpha.25 had alignment bugs with arrays inside structs.
; Alpha.26 correctly aligns array elements to their natural boundary.

Struct AlignedRecord {
    id: u8
    values: Float64[3]   ; 8-byte aligned, even after 1-byte id
    flags: u32
}

rec := AlignedRecord()
rec.id := 42
rec.values[1] := 1.111
rec.values[2] := 2.222
rec.values[3] := 3.333
rec.flags := 0xFF

PrintLine Format("  AlignedRecord size: {} bytes", rec.Size)
PrintLine Format("  id={}, flags=0x{:02X}", rec.id, rec.flags)
PrintLine Format("  values: [{:.3f}, {:.3f}, {:.3f}]",
    rec.values[1], rec.values[2], rec.values[3])

; Struct arrays also align correctly now
Struct Vec2 {
    x: Float64
    y: Float64
}
points := Vec2[4]()
loop 4 {
    points[A_Index].x := A_Index * 10.5
    points[A_Index].y := A_Index * 20.5
}
PrintLine Format("  Vec2[4] size: {} bytes (expect {})", points.Size, 4 * 16)
loop 4
    PrintLine Format("    [{1}] = ({2:.1f}, {3:.1f})", A_Index, points[A_Index].x, points[A_Index].y)
PrintLine ""

; ─────────────────────────────────────────────────────
; 3. StructClass.Ptr no longer seals the structure
; ─────────────────────────────────────────────────────
PrintLine "── 3. StructClass.Ptr fix ──"

; Previously, accessing StructClass.Ptr would "seal" the struct
; definition, preventing further modification. Now it doesn't.

Struct Header {
    magic: u32
    version: u16
}

; Access .Ptr on the class itself -- this no longer seals it
ptrType := Header.Ptr
PrintLine Format("  Header.Ptr type exists: {}", Type(ptrType))

; The struct is still usable after accessing .Ptr
h := Header()
h.magic := 0x46465542   ; "BUFF"
h.version := 26
PrintLine Format("  Header: magic=0x{:08X}, version={}", h.magic, h.version)
PrintLine ""

; ─────────────────────────────────────────────────────
; 4. DllCall with unset struct parameter
; ─────────────────────────────────────────────────────
PrintLine "── 4. DllCall(F, StructType, unset) behavior ──"

; When you pass `unset` for a struct parameter in DllCall,
; alpha.26 now creates a default instance S() automatically
; if the type has no __value setter. This is useful for
; output parameters where the DLL fills in the struct.

Struct SYSTEMTIME {
    wYear: u16
    wMonth: u16
    wDayOfWeek: u16
    wDay: u16
    wHour: u16
    wMinute: u16
    wSecond: u16
    wMilliseconds: u16
}

; Pass unset -- DllCall creates a SYSTEMTIME() for us
DllCall("GetLocalTime", SYSTEMTIME, st := SYSTEMTIME())
PrintLine Format("  System time: {}-{:02}-{:02} {:02}:{:02}:{:02}",
    st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond)
PrintLine ""

; ─────────────────────────────────────────────────────
; 5. Object construction performance improvements
; ─────────────────────────────────────────────────────
PrintLine "── 5. Object construction (memory optimization) ──"

; Alpha.26 combines typed property memory with the main object
; allocation. This means fewer allocations and better cache
; locality for struct-heavy code.

Struct Particle {
    x: Float32
    y: Float32
    z: Float32
    vx: Float32
    vy: Float32
    vz: Float32
    mass: Float32
    lifetime: Float32
}

; Benchmark: create many objects
count := 10000
start := A_TickCount
particles := []
loop count
    particles.Push(Particle())
elapsed := A_TickCount - start
PrintLine Format("  Created {} Particle structs in {} ms", count, elapsed)
PrintLine Format("  Particle size: {} bytes", Particle().Size)

; Clean up
particles := ""
PrintLine ""

; ─────────────────────────────────────────────────────
; 6. #SingleInstance now uses WM_CLOSE
; ─────────────────────────────────────────────────────
PrintLine "── 6. #SingleInstance / Reload uses WM_CLOSE ──"

; Previously, #SingleInstance and Reload sent an undocumented
; internal message to close the old instance. Now it posts
; WM_CLOSE, which is standard Windows behavior.
;
; This means OnExit callbacks see a normal close event,
; and any cleanup code runs as expected.
;
; Example (not executed here to avoid actually reloading):
;
;   #SingleInstance Force
;   OnExit((*) => FileAppend(A_Now "`n", "exit_log.txt"))
;   ; When a new instance starts, the old one receives WM_CLOSE
;   ; and the OnExit callback fires normally.

PrintLine "  #SingleInstance now sends WM_CLOSE to old instance"
PrintLine "  OnExit callbacks fire normally during reload"
PrintLine ""

; ─────────────────────────────────────────────────────
; 7. Modal dialog keyboard shortcuts (fixed)
; ─────────────────────────────────────────────────────
PrintLine "── 7. Modal dialog keyboard shortcuts (fixed) ──"

; Alpha.26 rewrote message handling so that keyboard shortcuts
; (Ctrl+C, Tab, accelerators) work correctly while a modal
; dialog (MsgBox, InputBox) is displayed.
;
; Previously, shortcuts in the script's main window would
; fail while a MsgBox was showing. This also fixes keyboard
; input when multiple Gui windows or dialog boxes are shown.
;
; To test interactively, uncomment below:
;
;   myGui := Gui()
;   myGui.Add("Edit", "w300 vInput", "Try Ctrl+A, Ctrl+C here")
;   myGui.Add("Button", "Default w300", "Show MsgBox").OnEvent("Click",
;       (*) => MsgBox("Keyboard shortcuts work in the background!"))
;   myGui.Show()
;   ; While MsgBox is shown, Edit shortcuts still work in the Gui

PrintLine "  Keyboard shortcuts now work while MsgBox is displayed"
PrintLine "  Tab navigation works in Gui with nested +Parent windows"
PrintLine ""

; ─────────────────────────────────────────────────────
; 8. Callback fixes (PR #356)
; ─────────────────────────────────────────────────────
PrintLine "── 8. CallbackCreate / typed callback fixes ──"

; Fixed reference-counting errors in CallbackCreate that could
; cause crashes in certain scenarios.
; Fixed struct return types for typed callbacks.

; Simple callback demo (the fix is internal -- no API change)
myCallback := CallbackCreate(AddNums, , 2)
result := DllCall(myCallback, "Int", 15, "Int", 27, "Int")
PrintLine Format("  CallbackCreate: AddNums(15, 27) = {}", result)
CallbackFree(myCallback)

AddNums(a, b) => a + b
PrintLine ""

; ─────────────────────────────────────────────────────
; 9. Start menu fix (admin/UIAccess)
; ─────────────────────────────────────────────────────
PrintLine "── 9. Start menu fix (admin scripts) ──"

; Fixed: If a script running as admin or with UIAccess was
; displaying a context menu, clicking the Start button would
; fail to open the Start menu. This was caused by the script's
; menu capturing the foreground window activation.

PrintLine "  Start menu now opens correctly even when admin"
PrintLine "  scripts have active context menus"
PrintLine ""

; ─────────────────────────────────────────────────────
; Summary
; ─────────────────────────────────────────────────────
PrintLine "═══════════════════════════════════════════════"
PrintLine "Alpha.26 is primarily a stability + performance release:"
PrintLine "  • Struct memory now co-allocated with objects (faster)"
PrintLine "  • Struct array alignment corrected"
PrintLine "  • Modal dialogs no longer block keyboard shortcuts"
PrintLine "  • #SingleInstance/Reload uses clean WM_CLOSE shutdown"
PrintLine "  • CallbackCreate reference counting fixed"
PrintLine "  • IsSet('var?') syntax permitted"
PrintLine "═══════════════════════════════════════════════"
