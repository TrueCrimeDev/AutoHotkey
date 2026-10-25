# AutoHotkey v2.1-alpha.37 Examples

Five short scripts, one per alpha.37 change, each built around a pattern the
change makes possible rather than a bare demonstration. They print what the
engine does; the comments record what alpha.36 did instead. Release notes:
[`docs/alpha/v2.1-alpha.37.md`](../../docs/alpha/v2.1-alpha.37.md).

| Script | Change | Pattern shown |
|--------|--------|---------------|
| `01_struct_constructors.ahk` | `Struct.Prototype.__New(fieldValues*)` | `POINT(10, 20)` literals, a `POINT` built inside a `DllCall` argument list (`PtInRect`), a table of corners in one expression, a `__New` that normalizes through `super.__New`, and the exact-count check |
| `02_isset_properties.ahk` | `IsSet(a.b)` / `IsSet(f())` imply a final `?` | optional settings with defaults, a finder that returns unset for "no result", feature detection on foreign objects, empty handler slots, and the "only the last access is optional" rule |
| `03_dllcall_unset_null.ahk` | `"Str"`, `"*"` and `"P"` parameters accept `unset` as null | a size query then the real call, `GetModuleHandleW(NULL)`, skipping an output you do not want, proof that it is a null pointer and not a pointer to 0, and a wrapper with an optional by-reference parameter |
| `04_numeric_structs_and_struct_at.ahk` | numeric struct instances pass by value; `Struct.At` accepts `Struct` | `Int32`/`Int64` counters passed straight to C, a typed default parameter, the same instance by pointer through `.Ptr`, and `Struct.At(ptr)` as an address carrier that other layouts reinterpret |
| `05_safer_errors.ahk` | four crashes or silent writes became catchable errors | a pipeline with optional hooks (`onItem => unset`), a method that is not indexable, validating `NumPut` type names from data, `DllCall(IntPtr, obj)`, and the fork's fix for a throwing getter |

## Things worth knowing

- **Calling a property calls its value as a method.** `obj.hook()` where
  `hook` is a getter returning a function invokes that function with `obj` as
  its first parameter, so hooks in `02` and `05` are written `(self, item) =>`.
- **`Size` is an instance property.** `Pair().Size`, not `Pair.Size` (`04`).
- **Type names match on their first letter.** `NumPut("Flaot", ...)` is
  accepted as `Float`; `05` uses `"Quad"` for its invalid example.
- **Do not name a variable `type`.** It shadows the `Type()` function for the
  whole script.
- The fork fixed five alpha.37 regressions before shipping it
  ([`docs/upstream/alpha37-regressions.md`](../../docs/upstream/alpha37-regressions.md));
  `05` section 5 shows one of them.

## Running

```powershell
& .\bin\AutoHotkey64Console.exe examples\alpha37\01_struct_constructors.ahk
```

```bash
# Git Bash
./bin/AutoHotkey64Console.exe examples/alpha37/01_struct_constructors.ahk
```

Every script needs `2.1-alpha.37+Console` or later (`#Requires AutoHotkey
v2.1-alpha.37`); on alpha.36 each stops at its first use of the new syntax.
