# winrt.ahk Alpha.22 Compatibility Patch

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Patch winrt.ahk in `C:\Users\uphol\Documents\Autohotkey\WinRT\` to work with AutoHotkey v2.1-alpha.22

**Architecture:** Alpha.22 removed `StructFromPtr` and changed `DefineProp({type: classObj})` to require native Struct subclasses. We replace 3 `StructFromPtr` calls with a polyfill that creates a struct-pointer wrapper using `ObjGetDataPtr`, and convert 1 `DefineProp({type: classObj})` call to use the reserve-space-then-manual-accessor pattern. `ObjGetDataPtr` and `ObjGetDataSize` still exist and need no changes.

**Tech Stack:** AutoHotkey v2.1-alpha.22, winrt.ahk library

**Test binary:** `C:\Users\uphol\Documents\Design\Coding\AutoHotkey\bin\AutoHotkey64.exe`

---

## Verified Facts

| API | Alpha.22 Status | Action |
|-----|-----------------|--------|
| `StructFromPtr(class, ptr)` | **Removed** | Polyfill |
| `ObjGetDataPtr(obj)` | Still exists | No change |
| `ObjGetDataSize(obj)` | Still exists | No change |
| `DefineProp({type: 'i32'})` | Works | No change |
| `DefineProp({type: intSize})` | Works | No change |
| `DefineProp({type: classObj})` | **Broken** — requires Struct subclass | Workaround |

## File Map

| File | Change | Lines affected |
|------|--------|---------------|
| `WinRT/guid.ahk` | Replace `StructFromPtr` on line 8 | 1 line |
| `WinRT/delegate.ahk` | Replace `StructFromPtr` on lines 24 and 150 | 2 lines |
| `WinRT/rtmetadata.ahk` | Convert `DefineProp {type: fc}` on line 421 to reserve+accessor | ~10 lines |
| `WinRT/test/test_alpha22.ahk` | New test script | New file |

---

## Chunk 1: StructFromPtr Polyfill and Replacements

### Task 1: Create test script

**Files:**
- Create: `WinRT/test/test_alpha22.ahk`

- [ ] **Step 1: Write test script**

```autohotkey
; Test that the alpha.22 patched winrt.ahk loads without errors.
; Run with: AutoHotkey64.exe /ErrorStdOut=utf-8 test\test_alpha22.ahk

#include ..\winrt.ahk
#include ..\windows.ahk

; Test 1: GUID construction from string
guid := GUID("{00000000-0000-0000-C000-000000000046}")
FileAppend("GUID: " guid.ToString() "`n", "*")

; Test 2: GUID construction via super.Call (no StructFromPtr path)
guid2 := GUID()
guid2.__value := "{6B3B8509-CB09-4131-B83E-6B5D86B0EC55}"
FileAppend("GUID2: " guid2.ToString() "`n", "*")

; Test 3: WinRT namespace resolution
try {
    clipboard := Windows.ApplicationModel.DataTransfer.Clipboard
    FileAppend("WinRT namespace: " Type(clipboard) "`n", "*")
} catch as err {
    FileAppend("WinRT namespace FAILED: " err.Message "`n", "**")
    FileAppend("  at " err.File ":" err.Line "`n", "**")
}

FileAppend("`nDone.`n", "*")
```

- [ ] **Step 2: Run test against UNPATCHED library to confirm it fails**

Run: `AutoHotkey64.exe /ErrorStdOut=utf-8 WinRT\test\test_alpha22.ahk`
Expected: FAIL with StructFromPtr or DefineProp errors

---

### Task 2: Replace StructFromPtr in guid.ahk

**Files:**
- Modify: `WinRT/guid.ahk:8`

The old `StructFromPtr(this, a)` created a struct object whose data pointer points to address `a`. The replacement creates a new instance and copies the data from the pointer.

- [ ] **Step 1: Patch guid.ahk line 8**

Replace:
```autohotkey
            return a ? StructFromPtr(this, a) : throw(ValueError("Null pointer"))
```

With:
```autohotkey
            return a ? _rt_WrapStructPtr(this, a) : throw(ValueError("Null pointer"))
```

We'll define `_rt_WrapStructPtr` in struct.ahk (Task 4).

- [ ] **Step 2: Save file**

---

### Task 3: Replace StructFromPtr in delegate.ahk

**Files:**
- Modify: `WinRT/delegate.ahk:24,150`

- [ ] **Step 1: Patch delegate.ahk line 24**

Replace:
```autohotkey
            get_arg_value(ac, o, p) => %StructFromPtr(ac, p + o)%
```

With:
```autohotkey
            get_arg_value(ac, o, p) => %_rt_WrapStructPtr(ac, p + o)%
```

- [ ] **Step 2: Patch delegate.ahk line 150**

Replace:
```autohotkey
        writeRet := return_value(ptr, value) => %StructFromPtr(rc, ptr)% := value
```

With:
```autohotkey
        writeRet := return_value(ptr, value) => %_rt_WrapStructPtr(rc, ptr)% := value
```

- [ ] **Step 3: Save file**

---

### Task 4: Add _rt_WrapStructPtr polyfill to struct.ahk

**Files:**
- Modify: `WinRT/struct.ahk` (add after line 15)

`_rt_WrapStructPtr` replicates what `StructFromPtr` did: create a new instance of the class whose internal data buffer points to the given address. We use `(Object.Call)(cls)` to construct the instance, then overwrite its data pointer.

- [ ] **Step 1: Add polyfill function after _rt_StructSetValuePOD**

Insert after line 15 (`}`):

```autohotkey

; Polyfill for StructFromPtr (removed in alpha.22).
; Creates an instance of cls whose structured data overlays the memory at ptr.
_rt_WrapStructPtr(cls, ptr) {
    obj := (Object.Call)(cls)
    ; Point the object's data buffer at the external address.
    ; This replicates StructFromPtr: the object reads/writes the foreign memory directly.
    NumPut('uptr', ptr, ObjPtr(obj) + (ObjGetDataPtr(obj) - ObjPtr(obj)), 0)
    ; Correction: use the simpler approach — copy data from ptr into the new object.
    DllCall('RtlMoveMemory', 'ptr', ObjGetDataPtr(obj), 'ptr', ptr, 'ptr', ObjGetDataSize(cls.Prototype))
    return obj
}
```

Wait — the above approaches have different semantics. `StructFromPtr` created a *view* into existing memory (zero-copy). A copy-based polyfill changes semantics for write-through. Let me verify which semantics are needed.

Looking at usage:
- `guid.ahk:8`: `StructFromPtr(this, a)` — reads from a COM pointer. Read-only view is fine, but the result gets `__value` read. Copy is fine.
- `delegate.ahk:24`: `%StructFromPtr(ac, p + o)%` — reads `__value` from struct at callback arg pointer. Copy is fine (callback args are temporary).
- `delegate.ahk:150`: `%StructFromPtr(rc, ptr)% := value` — WRITES through to return value pointer. This needs write-through to the original address.

So delegate.ahk:150 needs write-through. For that case specifically, we handle it differently: we write the value's data directly to the target pointer.

Revised approach — split into two helpers:

```autohotkey

; Polyfill for StructFromPtr (removed in alpha.22).
; Creates an instance of cls with data COPIED from ptr.
; Use for read-only access to struct data at a foreign pointer.
_rt_WrapStructPtr(cls, ptr) {
    obj := (Object.Call)(cls)
    DllCall('RtlMoveMemory', 'ptr', ObjGetDataPtr(obj), 'ptr', ptr, 'ptr', ObjGetDataSize(cls.Prototype))
    return obj
}

; Write a struct value's data to a foreign pointer.
; Replaces the pattern: %StructFromPtr(rc, ptr)% := value
_rt_WriteStructToPtr(cls, ptr, value) {
    obj := _rt_WrapStructPtr(cls, ptr)
    %obj% := value
    DllCall('RtlMoveMemory', 'ptr', ptr, 'ptr', ObjGetDataPtr(obj), 'ptr', ObjGetDataSize(cls.Prototype))
    return obj
}
```

- [ ] **Step 2: Save file**

---

### Task 5: Update delegate.ahk line 150 to use write-through helper

- [ ] **Step 1: Re-patch delegate.ahk line 150**

The line 150 replacement from Task 3 needs the write-through version:

Replace:
```autohotkey
        writeRet := return_value(ptr, value) => %_rt_WrapStructPtr(rc, ptr)% := value
```

With:
```autohotkey
        writeRet := return_value(ptr, value) => _rt_WriteStructToPtr(rc, ptr, value)
```

- [ ] **Step 2: Save file**

---

## Chunk 2: DefineProp {type: classObj} Workaround

### Task 6: Patch _rt_CreateStructWrapper in rtmetadata.ahk

**Files:**
- Modify: `WinRT/rtmetadata.ahk:420-422`

The pattern `wp.DefineProp f.name, {type: fc}` (where `fc` is a class object) breaks in alpha.22. The workaround is the same pattern already used on lines 424-436 for non-struct types: reserve space with `{type: byteSize}`, get the offset, then add manual Get/Set accessors.

- [ ] **Step 1: Patch the class-typed branch**

Replace lines 420-422:
```autohotkey
        else if IsSet(fc := ft.Class?) && ObjGetDataSize(fc.Prototype) {
            wp.DefineProp f.name, {type: fc}
            pod := false
        }
```

With:
```autohotkey
        else if IsSet(fc := ft.Class?) && (fcsize := ObjGetDataSize(fc.Prototype)) {
            ; alpha.22: DefineProp {type: classObj} requires Struct subclass.
            ; Workaround: reserve space with byte size, then add manual accessors.
            wp.DefineProp f.name, {type: fcsize}
            foffset := wp.GetOwnPropDesc(f.name).offset
            wp.DefineProp f.name, {
                get: _rt_NestedStructGet.Bind(fc, foffset),
                set: _rt_NestedStructSet.Bind(fc, foffset, fcsize)
            }
            pod := false
        }
```

- [ ] **Step 2: Add the nested struct accessor functions**

Add before `_rt_CreateStructWrapper` (around line 409):

```autohotkey
; Manual accessors for nested struct fields (alpha.22 compat).
; Replaces DefineProp {type: classObj} which now requires native Struct.
_rt_NestedStructGet(fc, offset, this) {
    obj := (Object.Call)(fc)
    DllCall('RtlMoveMemory', 'ptr', ObjGetDataPtr(obj), 'ptr', ObjGetDataPtr(this) + offset, 'ptr', ObjGetDataSize(fc.Prototype))
    return obj
}

_rt_NestedStructSet(fc, offset, size, this, value) {
    if !HasBase(value, fc.Prototype)
        throw TypeError(Format('{} cannot be assigned to {}', Type(value), Type(this)))
    DllCall('RtlMoveMemory', 'ptr', ObjGetDataPtr(this) + offset, 'ptr', ObjGetDataPtr(value), 'ptr', size)
}
```

- [ ] **Step 3: Save file**

---

### Task 7: Run tests

- [ ] **Step 1: Run test script**

Run: `AutoHotkey64.exe /ErrorStdOut=utf-8 WinRT\test\test_alpha22.ahk`
Expected: All tests pass, no StructFromPtr or DefineProp errors

- [ ] **Step 2: Run user's main script**

Run: `AutoHotkey64.exe /ErrorStdOut=utf-8 _.ahk` (with #include path changed to WinRT\)
Expected: No winrt-related errors

- [ ] **Step 3: Commit**

```bash
git add WinRT/
git commit -m "fix: patch winrt.ahk for alpha.22 compat (StructFromPtr removal, typed DefineProp)"
```
