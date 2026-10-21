# Upstream report: `ObjCreateWithDataPtr` stores the data pointer inside a native subclass (v2.1-alpha.36)

**Affects:** upstream `v2.1-alpha.36` (`7aa2e0ea`, "Added ObjCreateWithDataPtr."),
`source/script_object.cpp`, `Object::CreateStructPtr`.
**Found:** 2026-10-21 while merging alpha.36 into this fork. Reproduced on the
official `AutoHotkey_2.1-alpha.36.zip` (`AutoHotkey64.exe`; zip sha256
`300f9610664b4f3c22468579a30ca993d3f473a307f1421f45c6ede2ab9a5550`).
**Status:** fixed in this fork on branch `m1/upstream-alpha36`; not yet reported upstream.

## Symptom

`ObjCreateWithDataPtr` accepts any class that supports direct construction,
including native ones such as `Map`, `Array` and `Buffer`. For those:

- `ObjGetDataPtr(obj)` does not return the address that was passed (for
  Address 0 it returns an arbitrary value such as `17170407378780265`);
- the address is written over the object's own native fields;
- the heap is corrupted: a script that creates such a `Map` and releases it
  runs to the end and then exits with code 127, or 0xC0000374 in a larger script.

Struct classes and ordinary script classes are not affected.

## Cause

`7aa2e0ea` changed `CreateStructPtr` to construct through `si.create`, so the
object can now be a `Map` (`sizeof(Map)`) or any other native class, but kept the
offset of the pointer slot:

```cpp
	Object *obj = si.create(si.nested_object_size + sizeof(void*));
	...
	void *data = obj + 1;          // sizeof(Object) past the start
```

Every reader of that slot uses the class's `object_size` instead:
`Object::DataPtr()` and `Object::SetDataPtr()` read
`(char*)this + si->object_size + si->nested_object_size`, and `NewInstance`
places the suffix at `(UINT_PTR)obj + si->object_size`. Before `7aa2e0ea` the
function only built struct objects, whose `object_size` is `sizeof(Object)`, so
the two agreed. For a `Map` the pointer now lands on the `Map`'s first member,
and `~Map` later frees it.

## Fix

Start the suffix at `object_size`, as the readers do:

```cpp
	void *data = (char*)obj + si.object_size;
```

This also places the zeroed nested-object area of a subclass with typed
properties (`class M extends Map { x : Int32 }`) after the `Map` instead of over it.

## Reproduction

```autohotkey
buf := Buffer(16, 0)
m := ObjCreateWithDataPtr(Map, buf.Ptr)
FileAppend((ObjGetDataPtr(m) = buf.Ptr) "`n", "*")   ; 0 (expected 1)
m := ""
FileAppend("released`n", "*")                         ; printed, then the process exits 127
```

Pinned in this fork by `qa/tests/test_alpha36.ahk` section 3 (the child exits
0xC0000374 on an engine without the fix).
