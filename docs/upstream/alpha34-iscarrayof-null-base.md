# Upstream report: `IsCArrayOf` dereferences a null base (since v2.1-alpha.34)

Filed 2026-11-12 as [AutoHotkey/AutoHotkey#380](https://github.com/AutoHotkey/AutoHotkey/issues/380).

**Affects:** upstream `8fcbf453` ("Changed typed properties and DllCall to
let S.Array decay to S.Ptr", v2.1-alpha.34) through `upstream/alpha`
`42ddbabc`; `source/script_object.cpp`, `Object::IsCArrayOf`.
**Found:** by Copilot's review of the fork's PR #32 (2026-10); reproduced on
the fork's alpha.35-38 builds, then on 2026-11-12 on the official alpha.34,
alpha.36, alpha.37 and alpha.38 zips, `AutoHotkey64.exe` and
`AutoHotkey32.exe`. (The alpha.35 zip was locked after download, probably by
antivirus, and was not run.)
**Status:** fixed in this fork in `a6763d81`; pinned by
`qa/tests/test_alpha38.ahk` section 10.

## Bug

`IsCArrayOf` calls `aCandidate->Base()->GetStructInfo()` without checking the
base, and `Any.Prototype` has none. Both callers reach it with any object
they do not otherwise recognize: the `XX.Ptr` parameter branch in `DllCall`
and the typed pointer-field setter.

```autohotkey
DllCall("kernel32\lstrlenW", Int32.Ptr, Any.Prototype, "Int")
struct P {
    p : Int32.Ptr
}
P().p := Any.Prototype
```

| Engine | `DllCall` | Field |
| --- | --- | --- |
| Official alpha.33 | `TypeError` "Expected a Number but got a Prototype." | `TypeError` "Expected an Int32 but got a Prototype." |
| Official alpha.34, 36, 37, 38 (x64, x86) | "Critical Error: Invalid memory read/write." | the same |
| Fork `e13b80d8` | exit 11 "Invalid memory read/write." | the same |
| Fork `a6763d81` | `TypeError`, as alpha.33 | `TypeError`, as alpha.33 |

## Patch

```diff
 bool Object::IsCArrayOf(IObject *aCandidate, Object *aPrototype)
 {
-	if (!aCandidate)
+	auto base = aCandidate ? aCandidate->Base() : nullptr;
+	if (!base) // Any.Prototype has no base.
 		return false;
-	auto &vsi = *aCandidate->Base()->GetStructInfo();
+	auto &vsi = *base->GetStructInfo();
```

An `Int32[3]` still decays to an `Int32.Ptr` argument and field value
(`RtlMoveMemory` copies its first two elements; the field holds its address).
