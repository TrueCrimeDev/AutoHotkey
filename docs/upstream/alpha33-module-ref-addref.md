# Upstream report: `&Module.Var` returns an uncounted VarRef (alpha.33)

Draft for an upstream issue. Nothing has been filed yet.

**Suggested title:** `&Module.Var` corrupts the heap: `ScriptModule::__Ref` returns `Var::GetRef()` without an `AddRef`

**Affects:** v2.1-alpha.33 (`Module.__Ref`, upstream `9f4df71b`), including the
official `AutoHotkey_2.1-alpha.33.zip` build. Not present before alpha.33, which
had no `&Module.Var`.

## Minimal repro

```ahk
#Requires AutoHotkey v2.1-alpha.33
#Module Mod
global X := 1
#Module __Main
#Import Mod

Bump(&v) {
    v += 10
}

ref := &Mod.X
MsgBox(%ref%)          ; 1: reading through the reference works
%ref% := 5
MsgBox(Mod.X)          ; 5: so does writing
Bump(&Mod.X)
MsgBox(Mod.X)          ; expected 15; alpha.33 throws UnsetError "This global
                       ; variable has not been assigned a value. Specifically: X"
ref := ""              ; alpha.33: process dies here, or at exit if ref is kept
```

Each `&Mod.X` goes through `ScriptModule::__Ref`, which returns the result of
`Var::GetRef()`. `GetRef()` deliberately returns an *uncounted* reference (its
comment: "Callers rely on the counted reference in this->mObject to keep the
object alive"), which is right for the `&x` operator, whose token is never
released by the expression evaluator. A method result is different: the
evaluator records every `SYM_OBJECT` result in `to_free[]` and releases it when
the expression ends (`ExpandExpression`). So the first `&Mod.X` leaves the
module variable aliased to a VarRef whose only count belongs to `ref`; the
second one, inside `Bump(&Mod.X)`, is released to zero and freed while `Mod.X`
still aliases it. The next read of `Mod.X` sees the dead alias as unset, and
freeing the variable or `ref` later double-frees the VarRef.

## Observed

| Engine | `Bump(&Mod.X)` then `Mod.X` | Exit |
| --- | --- | --- |
| Official alpha.33 GUI build (2026-10-08) | `UnsetError` | heap-corruption / access-violation exit after the script ends |
| Fork `2.1-alpha.33+Console` before the fix (`d9fd14ac`) | `UnsetError`, line of the `Mod.X` read | `0xC0000374` (STATUS_HEAP_CORRUPTION), also with no `Bump` when `ref` is kept until exit |
| Fork after the fix (`cb092d22` + patch) | `15` | `0` |

On the before engine, a script-side `ObjAddRef(ObjPtr(ref))` right after
`ref := &Mod.X` hides both symptoms, which points at the missing count.

## Patch

`source/script_module.cpp`, `ScriptModule::__Ref`:

```diff
 	auto ref = var ? var->GetRef() : nullptr;
 	if (ref)
+	{
+		// GetRef() returns an uncounted reference (kept alive by var->mObject),
+		// but a method result is owned by the caller, which releases it.
+		ref->AddRef();
 		_o_return(ref);
+	}
 	_o_return_unset;
```

`Object::__Ref` already follows this rule: it increments the nested object's
count before `_o_return(nested)` and otherwise returns a freshly created
(counted) PropRef. The other `GetRef()` callers (`&x` in the evaluator, ByRef
parameter aliasing, for-loop output variables) hand the uncounted pointer to
code that never releases it, so they are unaffected.

## Pins in this fork

- `qa/tests/test_alpha33.ahk`: read and write through `%ref%`, a second
  reference to the same variable, both released; ByRef and built-in output
  parameters; two child-process exit-code checks. 17 asserts; the file dies
  with the `UnsetError` and `0xC0000374` on the unfixed engine.
- `tests/test_runtime_regressions.py`: `test_module_var_ref_held_at_exit_exits_zero`
  and `test_module_var_ref_byref_and_release_keep_the_variable` (both return
  code 3221226356 on the unfixed engine, 0 after).
