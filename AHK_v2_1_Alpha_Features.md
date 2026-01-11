# AutoHotkey v2.1 Alpha Features & Changes

This document summarizes the new features, changes, and optimizations introduced in AutoHotkey v2.1 Alpha (up to v2.1-alpha.18).

## Major Features

### Structures and Typed Properties
- **Typed Properties**: Support for defining structures using typed properties.
- **Struct Pointers**: Added `StructFromPtr` for working with pointers to structures.
- **Nested Structs**: Improvements to nested struct behavior and memory management.

### Modules
- **New Module System**: Introduced `#Module`, `Import`, and `Export` keywords.
- **Import Capabilities**:
    - Import from file: `Import "path\name"`
    - Import from resource: `Import "*RESNAME"`
    - Import specific names: `Import ModuleName {*, Names}`
    - Export and Import simultaneously: `Export Import ...`

### Unset and "Maybe" Operators
- **Unset Support**: Functions and properties can return `unset`.
- **Maybe Operator (`?`)**: Allows handling unset values (e.g., `value ?? default`).
- **Optional Chaining (`?.`)**: Safe property access (e.g., `obj?.prop`).
- **Maybe-Assign (`??=`)**: Assign only if unset.
- **Default Return**: Experimental directive `#DefaultReturn unset|""`.

### Per-Monitor DPI Awareness
- **New Default**: Default DPI awareness mode changed to **per-monitor v2**.
- **Automatic Scaling**:
    - Main window font adjusts automatically.
    - GUI controls (position, size, font) adjust automatically.
    - `ListView` columns rescale automatically.
- **`disableWindowFiltering`**: Added to manifest to allow detection of more windows.

### Virtual References
- **`__value` Property**: Objects with `__value` can act as virtual references.
- **Reference Operator (`&`)**:
    - Works with built-in/virtual variables.
    - Can be used with properties (e.g., `&x.y` invokes `x.__ref('y')`).
- **`Object.Prototype.Props()`**: Enumerates own and inherited properties.

## Version-by-Version Breakdown

### v2.1-alpha.18
- **Optional Parameters**: User-defined functions now permit optional parameters mid-list.
- **`ahk_class`**: Now case-insensitive.
- **Optimizations**: Window searches and `ProcessGetPath`/`WinGetProcessPath` optimized.
- **Fixes**: `MinParams` calculation fixed.

### v2.1-alpha.17
- **Menu**: Added `RTL` option for `Menu.Prototype.Add`.
- **Modules**: Added module search path (removed "Lib" from defaults).
- **Gui**: Fixed various DPI scaling issues (initialization, default font, calculations).

### v2.1-alpha.16
- **DPI**: Implemented basic per-monitor DPI awareness (see Major Features).

### v2.1-alpha.15
- **Fixes**: `HotIf(obj)`, `#DefaultReturn` with nested functions, named function hotkeys, non-raw hotstrings, debugger float parsing.

### v2.1-alpha.14
- **InputHook**:
    - Added `H` option to intercept hotkeys.
    - Improved text input collection and dead key handling.
- **`A_HotIf`**: Added `A_HotIf` and return value for `HotIf`.
- **Tray**: `TraySetIcon` updates the main window icon.

### v2.1-alpha.13
- **Debugger**: Improved property listing (Prototypes, non-Object classes).
- **Warnings**: Added warning for UTF-8 decoding errors.

### v2.1-alpha.12
- **`#Warn`**: Settings are copied from previous module; `Mode` sets program default.

### v2.1-alpha.11
- **Modules**: Initial introduction of Modules.

### v2.1-alpha.10
- **Virtual References**: Implemented (see Major Features).
- **`WinTitle`**: Two different `ahk_id` values now yield no match.
- **`RegExReplace`**: Support for binary zero in replacement.
- **Debugger**: Improved DBGp property and context commands.
- **InputHook**: Changed `KeyOpt` option removal behavior.

### v2.1-alpha.9
- **Structs**: Added `StructFromPtr`.
- **`MouseGetPos`**: Throws `OSError` on failure.

### v2.1-alpha.8
- **Optimizations**: Auto-replace hotstrings avoid retyping identical leading parts.
- **Case Sensitivity**: ASCII-only case insensitivity for `UseTab`, `Choose`, `Text` (Tab control), and `Menu.Add`.

### v2.1-alpha.7
- **Gui**: Added `SetCue` for Edit/ComboBox.
- **Shortcuts**: `FileCreateShortcut` permits modifiers (`^`, `+`, `!`).
- **Hooks**: Added `A_KeybdHookInstalled` and `A_MouseHookInstalled`.
- **`GuiControl`**: Added `OnMessage` method.

### v2.1-alpha.6
- **Fixes**: `return (){`, closures in function definition expressions.

### v2.1-alpha.5
- **Remapping**: Support for `WheelUp/Down/Left/Right` on either side.
- **`Ctrl::Alt`**: No longer sends unsuppressed `{Ctrl up}`.

### v2.1-alpha.4
- **Fixes**: Control flow statements followed by braces, static property merging.

### v2.1-alpha.3
- **Functions**: Added function definition expressions.
- **Classes**: Added `Class()` function.
- **Hotkeys**: Support for left/right modifiers in `{Blind}`.
- **`DllCall`**: `CDecl` can be omitted.
- **`ListVars`**: Shows unset vars as "unset".
- **`Throw`**: Now a function (continuable errors).

### v2.1-alpha.2
- **Unset/Maybe**: Added operators `?`, `??`, `??=`, `?.` (see Major Features).
- **Optimizations**: `Pause`, `ProcessWaitClose`, `RunWait` (reduced CPU usage).
- **`ImageSearch`/`PixelSearch`**: X and Y can be omitted.
- **`ProcessWait`**: Shows "STILL WAITING" in ListLines.

### v2.1-alpha.1
- **`RegExReplace`**: Callback function support.
- **Window**: Added `WinGetEnabled`, `WinGetAlwaysOnTop`.
- **Gui**: Added `Gui.OnMessage`, `Edit` filename parameter.
- **Menu**: Modeless menus, `Wait` parameter for `Show`.
- **Math**: Added `ATan2`.
- **COM**: Support for `ByRef VARIANT`, two-variable enumerators for IDispatch objects.
