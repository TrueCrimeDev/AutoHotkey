# v2.1-alpha.38: four regressions in the open-structure changes, and one import fix already upstream

Draft upstream report. Found 2026-11-12 by GitHub Copilot's review of the
fork's merge PR (TrueCrimeDev/AutoHotkey #35) and reproduced on a build of
the `v2.1-alpha.38` tag (`afde2333`), x64 and x86, before being fixed in the
fork (`b2885254`). Each item names the alpha.37 behaviour (fork build
`a911f73d`, upstream `279247ee` plus fork fixes unrelated to these paths)
for comparison.

Sections 1 to 4 are still present on `upstream/alpha` (`42ddbabc`).
Section 5 was fixed upstream after the tag by `c727bdf0`, and the fork
cherry-picked that commit.

## 1. A struct that contains itself by value is accepted, then corrupts the heap

`ad5cfae6` ("Changed typed property offsets to be calculated later") moved
layout calculation into `Object::CloseStructInfo`, which sets
`StructInfoClosed` before it walks the fields. When a field's type leads back
to the structure being closed, the recursive `CloseStructInfo` returns the
unfinished `StructInfo` (size 0, `kind` already `Struct`), so the field is
laid out with size 0. Constructing the struct then writes nested-object data
past the instance's suffix:

```autohotkey
struct S {
    a : Int32
    x : S            ; also S[2], mutual A{b : B}/B{a : A}, or T{s : S} with S extends T
}
S()   ; alpha.37: "Cannot add typed property." from DefineProp when x was defined
      ; alpha.38: ObjGetDataSize(S.Prototype) = 4, then exit 127 (the mutual and
      ;           array forms report "Invalid memory read/write."; the base form exits 139)
```

The same happens for `S := Class(Struct)` with
`DefineProp(S.Prototype, "x", {Type: S})`. A struct that points to itself
(`next : S.Ptr`) is unaffected, because pointer classes are closed when they
are created and never close their target.

For the base form (`struct T { s : S }`, `struct S extends T {}`), closing
`S` closes `T`, whose field closes `S` again. The inner call finishes `S`,
and the outer call, which has already passed the `StructInfoClosed` test,
then lays `S` out a second time over the finished `StructInfo`.

Fix (`source/script_object.cpp`, `CloseStructInfo`):

- Keep the final kind in a local and store `StructKind::Invalid` in `si.kind`
  until the layout is complete. A by-value reference back to the structure
  then fails `IsValidPropertyType()`, and the containing structure becomes
  invalid.
- For an array class, an item whose kind is `Invalid` (including the
  structure being closed) makes the array invalid, with no size or alignment
  taken from the item.
- After closing the base, return at once if this structure was closed in the
  meantime.

Every construction path already refuses `StructKind::Invalid`, so `S()`,
`S.At(buf)` and `ObjCreateWithDataPtr(S, buf)` throw `TypeError` "Invalid
struct.", and `ObjGetDataSize(S.Prototype)` is 0. The error now comes at
first use instead of at `DefineProp`, which is unavoidable once offsets are
calculated late.

## 2. `DefineProp` with a COM wrapper as the field type dereferences null

`ad5cfae6` rewrote `Object::DefineTypedProperty(name, Object *aClass, ...)`
to start with `aClass->ClassGetPrototype()`. `DefineProp` passes
`dynamic_cast<Object*>(TokenToObject(tclass))`, which is null for a
`ComObject`, and the descriptor check before it only tests for `SYM_OBJECT`:

```autohotkey
S := Class(Struct)
DefineProp(S.Prototype, "x", {Type: ComValue(3, 0)})
; alpha.37: ValueError "Parameter #3 invalid."
; alpha.38: exit 11 "Invalid memory read/write."
```

Fix: `auto proto = aClass ? aClass->ClassGetPrototype() : nullptr;`, so a
non-`Object` reaches the existing `FR_E_ARGS` path.

## 3. A field whose type is a numeric subclass loses its class

In `CloseStructInfo` a subclass inherits `bsi.kind` (reverting only `Ptr` to
`Struct`), while `native_type` stays `MdType::Void` for a subclass ("Revert
to a normal struct if extending a numeric type"). A subclass of `Int32` is
therefore `StructKind::Number` with no native type. When it is a field's
type, the loop releases the field's class and sets
`tprop->type = MdType::Void`:

```autohotkey
N := Class(Int32)
H := Class(Struct)
DefineProp(H.Prototype, "n", {Type: N})
rec := H()
rec.n := 9
rec.n          ; alpha.37: 9 (or the subclass's own __Value getter)
               ; alpha.38: "" (the value was never stored)
Object.Prototype.GetOwnPropDesc.Call(H.Prototype, "n")   ; alpha.38: reads sPrimitiveClass[-1]
```

Fix: revert `Number` to `Struct` for a subclass as `Ptr` already is, so the
field keeps its class, constructs it, and runs its `__Value`. `N()` itself,
`DllCall(..., N, inst, ...)`, `N[2]` and `NumGet(buf, N)` (still
`ValueError`) behave as on alpha.37.

## 4. `GetOwnPropDesc` loses an `Offset` that names a later-sorted field

`ad5cfae6`'s `GetOwnPropDesc` reports an `Offset` given by name, while the
structure is open, by searching `mFields` backward from the described field.
`mFields` is sorted by name, not definition order:

```autohotkey
S := Class(Struct)
DefineProp(S.Prototype, "m", {Type: Int32})
DefineProp(S.Prototype, "a", {Type: Int16, Offset: "m"})
Object.Prototype.GetOwnPropDesc.Call(S.Prototype, "a").HasOwnProp("Offset")   ; 0, should be "m"
```

Fix: search every own field for the referenced `TypedProperty`.

## 5. Wildcard import lookup stops at an import-free enclosing function

`41c751bc` ("Fixed wildcard import to respect scope regardless of #import
order") walks outward through enclosing functions in
`ScriptModule::FindImportedVar`, but stops at the first one with no imports,
so a nested function inside an import-free function no longer sees a global
`#Import M {*}`. Upstream fixed this after the tag in `c727bdf0` ("Fixed
import resolution in nested functions which don't use #Import."). The fork
cherry-picked it (`9a2cf75e`); nothing to report.

## Verification

Fork build `b2885254`, MSVC x64 and Win32: `qa/tests/test_alpha38.ahk`
section 9 (11 asserts) passes on both, and the full qa suite is 1032/1032 on
each. On the unfixed merge build (`c47c4c8b`, x64), 9 of the 11 fail. The two
that pass there pin what the fix must keep: a `Node { next : Node.Ptr }`
self-reference and a plain `Class(Int32)` instance. Also unchanged:
`test_alpha38.ahk` section 4's mutually referencing structs in both orders,
section 6's `Class(X.Ptr)` field, and every `examples/alpha37` and
`examples/alpha38` script.
