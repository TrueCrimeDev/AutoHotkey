# AutoHotkey v2 Changes Research

## v2.0.20 Release (February 8, 2025)

Substantial bug-fix release. No new features. A hotfix v2.0.21 followed the next day for a `StrGet` crash regression.

### Crashes/Safety
- `GuiFromHwnd` no longer crashes when passed another script's GUI HWND
- ListView with `Sort` option no longer crashes when `Add` is called with Col1 omitted
- Fixed undefined behavior in message callbacks during script termination
- `Run` now properly closes the process handle (was leaking)

### Parser/Language
- Leading space in `For( a in b )` no longer raises a false error
- Semicolons inside `/* ; */` no longer prematurely end block comments
- Erroneous `Else` placement now raises an error instead of crashing on load
- Static functions can now access static variables from grandparent functions
- Enumerator calls (For) no longer treat implicitly returned "" as true

### Hotkey System (5 fixes)
- `~RAlt & <::` no longer causes `RAlt::` to fire on release despite `~`
- Remap with nonexistent source key no longer causes silent exit
- Key-up hotkey passthrough and suppression edge cases fixed
- `1::` no longer fires after `1 & LButton up::` is used
- Unpaired key-up hotkey now correctly suppresses the key if also used as prefix

### Other
- `StrPut`/`StrGet` 32-bit integer limits fixed on x64
- String return values no longer corrupted during debugging
- `RegWrite` parameter 1 made mandatory
- `A_MaxHotkeysPerInterval` / `A_HotkeyInterval` return correct values regardless of casing
- `IsOptional` and `IsByRef` return values fixed for built-in methods
- `FileSelect` no longer duplicates the filter pattern if it lacks `*.`
- ListBox tab-stop spacing fixed when T option is used during control creation

---

## Major v1 to v2 Breaking Changes

### Syntax Overhaul
- **Command syntax eliminated.** Every former "command" is now a function call: `MsgBox, Hello` becomes `MsgBox("Hello")`
- **Legacy assignment removed.** `var = value` gone; all assignments use `:=`
- **Percent-sign dereferencing removed.** `%var%` gone; use expression syntax
- **Legacy If statements removed.** Only `if expression` remains; `IfEqual`, `IfWinActive` (as commands), `IfInString` all gone
- **`Gosub` removed entirely.** Use nested functions or function calls instead

### Object Model Restructured
- **`Object` split** into `Object`, `Array`, and `Map`
- **Arrays are 1-indexed**, bracket syntax required (`a[1]`)
- **Map replaces associative arrays.** String keys are case-sensitive by default
- **`new` keyword removed.** `MyClass()` replaces `new MyClass()`
- **Class-prototype architecture.** Proper class definitions with static members, prototypes, `super` keyword
- **Property vs. item access explicit.** Dot notation (`.prop`) for properties; brackets (`[key]`) for items

### Error Handling
- **`ErrorLevel` largely eliminated.** Functions throw exceptions instead
- **`Try/Catch/Finally`** is primary mechanism; `Catch` can filter by error class
- **Unset variables throw errors** instead of silently producing empty strings
- **`OnError()` and `OnExit()` require function objects**, not labels or strings

### ByRef and Functions
- **`ByRef param` becomes `&param`**, callers must explicitly pass `&var`
- **Function library auto-inclusion removed**
- **Nested functions and closures added**
- **Fat arrow functions:** `Fn(x) => x * 2`

### Type System
- **`"0"` is now falsy** (was truthy in v1)
- **Relational operators throw on non-numeric strings.** `"abc" > "def"` throws
- **No silent type coercion caching.** `"123"` stays string, `123` stays integer
- **Float formatting changed** from `0.6f` to `.17g`

### GUI System
- **Full OOP redesign.** `Gui()` creates an object; `GuiControl` objects replace command-based control manipulation
- **Client coordinates** used by `ControlMove()`, `ControlGetPos()`, `ControlClick()`

### Key Renames

| v1 | v2 |
|----|-----|
| `ComObjCreate()` | `ComObject()` |
| `VarSetCapacity()` | `Buffer` object |
| `StringSplit` | `StrSplit()` |
| `StringReplace` | `StrReplace()` |
| `#IfWinActive` | `#HotIf` |
| `Input` | `InputHook()` |
| `Asc()` | `Ord()` |
| `FileSelectFile()` | `FileSelect()` |
| `FileSelectFolder()` | `DirSelect()` |
| `FileCopyDir()` | `DirCopy()` |
| `FileCreateDir()` | `DirCreate()` |
| `UrlDownloadToFile()` | `Download()` |
| `Progress` | Use `Gui` |
| `SetBatchLines` | Removed entirely |

### Other Notable Changes
- `MsgBox` returns button names (`"OK"`, `"Yes"`) instead of requiring `IfMsgBox`
- Logical operators (`&&`, `||`) return the determining value (like JavaScript), not `0`/`1`
- Both single and double quotes valid for strings
- `#Include` relative to current file by default, not script directory
- `FileSelect` returns an array for multi-select instead of newline-delimited string
- Variable names cannot contain `@`, `#`, `$` and cannot start with digits

---

## v2.0.x Release Line Patterns

### Debugger Maturation
v2.0.14 was a landmark debugger release (property evaluation, exception handling in debugger contexts). v2.0.15 hotfixed regressions. v2.0.17 continued polishing breakpoint and step-out behavior. v2.0.20 fixed string corruption during debugging.

### Edge Cases in New Language Features
- Fat arrow functions in complex control flow (v2.0.19)
- Nested static function variable scoping (v2.0.20)
- Multi-level nested function reference counting (v2.0.11)
- Arrow functions under control flow without blocks (v2.0.17)

### Hotkey/Send System Refinement
- Modifier key state management across Send operations
- Key-up suppression edge cases
- Tilde prefix and remapping behavior
- InputHook interaction with modal dialogs (v2.0.19)

### Memory Safety and Crash Prevention
- Out-of-bounds memory access in RegEx (v2.0.19)
- GuiFromHwnd crashes (v2.0.20)
- ListView Sort crashes (v2.0.20)
- StrGet crashes (v2.0.21)
- String corruption during debugging (v2.0.20)

### Rapid Regression Fixes
- v2.0.15 followed v2.0.14 by 9 days
- v2.0.21 followed v2.0.20 by 1 day

The v2.0.x line is in **stabilization mode** -- language design is settled, focus is on correctness.

---

## Notable Individual Releases

### v2.0.14 (May 6, 2024) -- Major Debugger Release
- Property evaluation via debugger (`property_get` for complex expressions)
- Exception handling in debugger contexts
- Support for primitive value properties, float keys
- Debugger code size optimization

### v2.0.18 (July 6, 2024) -- Small/Targeted
- `A_Clipboard` silent exit when `GetClipboardData` returns NULL (data-loss scenario)
- Chained property assignment (`a.b[c] := d`) getter invocation fix

### v2.0.19 (January 25, 2025) -- Correctness Focus
- Out-of-bounds access during RegEx compilation fixed
- Send modifier handling: externally-released modifiers no longer incorrectly "restored"
- Modal dialogs no longer suppress InputHook events
- Try/Catch/Else/Finally now correctly executes Finally when Else returns
- MouseGetPos returns blank Control instead of throwing when ClassNN cannot be determined
- FileSelect now validates Options parameter

---

## Implications for This Project

For the MCP debugging ecosystem:
1. **v2.0.20 fixed string corruption during debugging** -- directly relevant to our DBGp client
2. **v2.0.14's debugger improvements** (property evaluation, exception handling) expanded what our MCP tools can inspect
3. **Static variable scoping fix in v2.0.20** may affect error analysis when scripts use nested static functions
4. **The `StrGet`/`StrPut` fixes** are relevant for any scripts doing COM or DLL interop that our error handler might capture
