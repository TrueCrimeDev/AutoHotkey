# AutoHotkey v2.1-alpha.38 Examples

Five short scripts, one per alpha.38 change, each built around a pattern the
change makes possible rather than a bare demonstration. They print what the
engine does; the comments record what alpha.37 did instead. Release notes:
[`docs/alpha/v2.1-alpha.38.md`](../../docs/alpha/v2.1-alpha.38.md).

| Script | Change | Pattern shown |
|--------|--------|---------------|
| `01_open_structures.ahk` | structures stay open until their layout is needed | a list header that embeds its first link while each link points back to the list (in the order alpha.37 rejected), a layout built from a schema table and inspected with `GetOwnPropDesc` before and after closing, `ObjGetDataSize` padding, and the two definitions a closed structure now refuses |
| `02_struct_views_on_buffers.ahk` | `Struct.At`/`ObjCreateWithDataPtr` take a `Buffer`; `At` accepts small addresses | the running engine's DOS and PE headers read from a file `Buffer`, a counter that outlives its function-local `Buffer`, an ordinary class mapped over packed data, `IDI_INFORMATION` as `UInt16.At(32516)` for `LoadIconW` |
| `03_objgetdataptr_unset.ahk` | `ObjGetDataPtr` returns `unset` | one `AddressOf` helper for structs, Buffers and numbers, a dumper that prints typed objects as bytes and everything else as JSON, `?? 0` defaults |
| `04_custom_pointer_types.ahk` | `Class(X.Ptr)` subclasses are constructed | `PWSTR` and `PSTR` field types whose `__Value` returns the string, read from `NetWkstaGetInfo`'s `WKSTA_INFO_100` and the C runtime's `localeconv()`, and a field written through `UInt16.At(buffer)` |
| `05_module_fixes.ahk` | three module fixes | a module whose load-time `v := imported` runs the imported module first, a module run from inside a function with an empty `A_ThisFunc`, and a function's own wildcard import winning over a later global one |

## Things worth knowing

- **Modules run in reverse order of creation.** A module written later in the
  file runs first, so its first reference to an earlier module is what runs
  that module (`05`). `__Main` runs last.
- **A struct class's prototype has no `GetOwnPropDesc` method.** Call
  `Object.Prototype.GetOwnPropDesc.Call(Proto, name)` instead (`01`); the
  `DefineProp(Proto, ...)` function form works on any prototype.
- **`DefineProp`'s parameter numbers differ by form.** An invalid descriptor
  is "Parameter #2 invalid." from `obj.DefineProp(name, desc)` and
  "Parameter #3 invalid." from `DefineProp(obj, name, desc)`.
- **Inside a pointer class's `__Value`, `this.Ptr` is the field's address.**
  The pointer value is `NumGet(this.Ptr, "Ptr")` (`04`).
- **A pointer field is assigned an instance of its target class.** Assigning
  a `Buffer` to a `UInt16.Ptr` field throws "Expected an UInt16 but got a
  Buffer."; `UInt16.At(buffer)` is such an instance and keeps the Buffer alive.
- **Variable names are case-insensitive, and so is a class name.** A variable
  `nv` next to a struct `NV` is the same name: at file scope it is a load
  error, and inside a function it silently refers to the class.

## Running

```powershell
& .\bin\AutoHotkey64Console.exe examples\alpha38\01_open_structures.ahk
```

```bash
# Git Bash
./bin/AutoHotkey64Console.exe examples/alpha38/01_open_structures.ahk
```

Every script needs `2.1-alpha.38+Console` or later (`#Requires AutoHotkey
v2.1-alpha.38`). On alpha.37, `#Requires` stops each one before it runs.
