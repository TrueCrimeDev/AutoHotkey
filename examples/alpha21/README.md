# AutoHotkey v2.1-alpha.21 Examples

These examples demonstrate the new features and changes in alpha.21.

## What's New

### 1. `!~=` Operator (was `~!=`)
The not-RegExMatch operator syntax changed from `~!=` to `!~=` for readability.

**Example:** `01_not_regex_operator.ahk`

### 2. Module System Refinements

The `#Module` / `#Import` system received major improvements:

| Change | Description |
|--------|-------------|
| **File scoping** | `#Module` ends at end of file — no leaking across `#Include` |
| **Private names** | Module names are private to each file — two files can define `#Module Helper` without conflict |
| **Valid identifiers** | `#Module` now requires a valid identifier name |
| **`__Init` reopening** | `#Module __Init` reopens the initial module of a file import |
| **Error detection** | Repeated `#Module` via `#Include` and hotkey-before-`#Module` are now errors |
| **Removed `Import` statement** | Only the `#Import` directive remains (not the bare `Import` keyword) |
| **`#Import "file:mod"`** | Import a specific named module from a multi-module file |
| **Lazy initialization** | Modules execute on first reference, not at load time |
| **Forward references** | `#Import` recognizes imported names regardless of declaration order |

**Examples:**
- `02_module_basics.ahk` — Defining modules, exports, and imports
- `03_import_from_file.ahk` — Importing from external `.ahk` files
- `04_import_selective.ahk` — Selective imports, renaming with `as`, wildcard `*`
- `05_lazy_module_init.ahk` — Lazy initialization and forward references
- `06_module_file_scoping.ahk` — File-scoped modules and name privacy

## Running

```powershell
& "path\to\AutoHotkey64.exe" examples\alpha21\01_not_regex_operator.ahk
```

## Requirements

- AutoHotkey v2.1-alpha.21 or later
