# AutoHotkey v2.1-alpha.22 Examples

These examples demonstrate the new features and changes in alpha.22.

## What's New

### 1. `Type()` Returns "unset" for Omitted Parameters
`Type()` now returns the string `"unset"` if its parameter is omitted or unset, instead of throwing an error. This makes type-dispatching functions cleaner.

**Example:** `01_type_unset.ahk`

### 2. `IsSet()` Permits Unset Expressions
`IsSet()` can now accept an unset expression without requiring an assignment. Also fixes `IsSet(p)` to correctly return 0 for unset virtual references.

**Example:** `02_isset_expression.ahk`

### 3. `DefineProp()` Function
New top-level function for programmatically defining properties on objects. Complements the existing `obj.DefineProp()` method — useful when the target object is dynamic.

**Example:** `03_defineprop.ahk`

### 4. `Struct` Keyword and Class
Native struct support with typed fields and automatic `.Ptr` subclasses.

| Change | Description |
|--------|-------------|
| **`Struct` keyword** | Define memory-layout-aware data structures |
| **Automatic `.Ptr` classes** | Each struct gets a pointer subclass |
| **DllCall integration** | DllCall now requires a Struct subclass (not arbitrary objects) |
| **StructFromPtr removed** | Use Struct `.Ptr` classes instead |
| **ObjGetDataPtr fallback removed** | No longer falls back for DllCall Ptr parameters |

**Example:** `04_struct_basics.ahk`

### 5. `export a() => b` Behavior Change
`export a() => b` is now treated as a function call statement (matching v2.0 behavior), not an exported fat-arrow function definition. Use block syntax for exported functions.

**Example:** `05_export_function_call.ahk`

### 6. Bug Fixes
- `IsSet(p)` returns 0 for unset virtual references
- `#Import __Init` works without sub-modules
- `!~=` operator works correctly
- Correct module reopened at end of file with `#Module`
- `DllCall(... "str",&var:={} ...)` detected as error

**Example:** `06_bug_fixes.ahk`

## Running

```powershell
& "path\to\AutoHotkey64.exe" examples\alpha22\01_type_unset.ahk
```

## Requirements

- AutoHotkey v2.1-alpha.22 or later
