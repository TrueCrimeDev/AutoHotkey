# v2.1-alpha.37: five regressions in the DllCall, NumPut, CallbackCreate and property-call changes

Draft upstream report. Found 2026-10-25 by GitHub Copilot's review of the
fork's merge PR (TrueCrimeDev/AutoHotkey #33) and reproduced on a build of
`upstream/alpha` `279247ee` (the announced but not yet tagged
v2.1-alpha.37), x64 and x86, before being fixed in the fork. Each item names
the alpha.36 behaviour (`0b8e6fa3`) for comparison.

## 1. `NumPut` accepts an invalid type in any pair after the first

`2cdf79a6` ("Fixed NumGet/NumPut to throw if an incorrect Struct class is
passed") changed `NumGetParams::num_size` to default to 0 and removed the
`default: op.num_size = 0;` arm from `ConvertNumGetType`'s switch, so an
unrecognized type string no longer resets the size. `BIF_NumPut` reuses one
`NumGetParams` across its type/value pairs, so the second pair below inherits
the first pair's four bytes:

```autohotkey
buf := Buffer(16, 0)
NumPut("Int", 1, "Bogus", 2, buf)   ; alpha.36: ValueError "Invalid parameter(s)."
                                    ; alpha.37: writes 2 at offset 4, no error
```

`NumGet(buf, "Bogus")` alone still throws, because its `op` starts fresh.

Fix (`source/lib/interop.cpp`): set `op.num_size = 0;` at the top of
`ConvertNumGetType`, so a failed string or class conversion reaches the
existing invalid-parameter check for every pair.

## 2. `a.b()` replaces a throwing getter's exception with `UnsetError`

`2f4f3967` ("Fixed a.b() to throw UnsetError when a.b => unset, not crash")
tests `method_token.symbol == SYM_MISSING` in `Object::CallProperty` before
looking at `result`. A getter that throws also leaves the token unset, so the
original exception is discarded:

```autohotkey
class C {
    b {
        get => (throw ValueError("original"))
    }
}
C().b()   ; alpha.36: ValueError "original"
          ; alpha.37: UnsetError "No value was returned."
```

In a debug build this also trips the pending-exception assertion.

Fix (`source/script_object.cpp`): `if (result == OK && method_token.symbol ==
SYM_MISSING)`, so a failed getter propagates unchanged.

## 3. `CallbackCreate` rejects a struct subclass with only inherited fields

`c20d449d` ("Fixed typed callback parameters of an array subtype") replaced
`GetStructMdType` with `GetStructCallbackArgInfo`, which returns false when
`StructInfoInitialized` is clear. A subclass that adds no fields has no
`StructInfo` of its own until an instance is created or the layout is locked,
so it is now rejected where alpha.36's `MdType::Void` fallback accepted it:

```autohotkey
struct Base {
    x : Int32
}
struct Derived extends Base {
}
cb := CallbackCreate((s) => 0, , [Derived, "Void"])
; alpha.36: ok
; alpha.37: ValueError "Parameter #3 of CallbackCreate is invalid."
; alpha.37 after `d := Derived()`: ok
```

Fix (`source/script_object.cpp`): obtain the layout through
`GetStructInfo(true)` (as `CanConstruct` does) instead of requiring it to be
initialized already.

## 4. Win32: `"Int64*", unset` and `"Double*", unset` occupy eight bytes

`1fa8d1f1` ("Changed DllCall "Str" and */P types to allow `unset` to mean
null") sets `ptr = nullptr` and clears `passed_by_address` but leaves the
parameter's type. On x86 `DLL_ARG_INT64` and `DLL_ARG_DOUBLE` are pushed as
eight bytes, so the pointer takes two slots:

```autohotkey
DllCall("kernel32\lstrlenW", "Int64*", unset, "Int")
; x86 alpha.37: Error "Parameter list too large." (stdcall stack mismatch)
DllCall("msvcrt\_wcsnicmp", "Double*", unset, "Str", "abc", "UPtr", 0, "Cdecl Int")
; x86 alpha.37: 2147483647 (the following arguments are read from the wrong slots); x64: 0
```

An unset `"AStr"` has a second effect on both architectures: it skips the
`pStr[nStr++]` allocation but keeps type `DLL_ARG_xSTR`, and the output loop
increments `nxStr` for every parameter of that type, so a later `"AStr*"`
output parameter reads `pStr[nxStr]` one entry past what was allocated (from
source; not observed to misbehave in a probe).

Fix (`source/lib/DllCall.cpp`): in the unset branch, zero the flags union
(`struct_size = 0`), set `type = DLLARGTYPE_INTPTR`, then `ptr = nullptr`.

## 5. Win32: an array callback parameter is counted at its struct size

`c20d449d` makes an array-typed callback parameter decay to a pointer
(`MdType::Array`, one slot), but `RegisterCallbackCStub` still advances
`next_param` by `(StructSize + 3) >> 2` on Win32 and `CallbackCreate` still
adds the same expansion to `param_slot_count`. For an `Int32[2]` parameter
the decoder skips one extra slot, so the following argument is read from the
wrong place, and the generated `stdcall` cleanup pops four extra bytes. From
source only: an array class is reachable from script only as a field type
(`v : Int32[2]`), and `ObjGetBase` on a field value yields its prototype,
which `CallbackCreate` rejects, so no script-level reproduction was found.

Fix (`source/lib/CCallback.cpp`): skip the `next_param` adjustment when `arr`
is true, and exclude `MdType::Array` from the `param_slot_count` expansion.

## Verification

Fork build `0cea936a` + these fixes, MSVC x64 and Win32:
`qa/tests/test_alpha37.ahk` section 9 (6 asserts) passes on both; on the
unfixed merge build (`6460921b`, x64) its three x64-observable asserts fail
and the two Win32 cases fail on the unfixed x86 CI build (`5d296fb2`,
run 40217057809). A struct passed by value to a Win32 callback
(`[QaPt, Int32, Int32]`, size 8) still arrives intact after the
`param_slot_count` change.
