# `_Eval` Built-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an engine-level `_Eval(Expression)` built-in that evaluates an AHK expression string against the caller's live scope, gated by a `/Eval` CLI flag. v1 covers single expressions (assignments included) in caller scope, with a new `SyntaxError` class and full reentrancy.

**Architecture:** Reuse the existing parser at runtime — feed the expression string through the load-time tokenizer/`ExpressionToPostfix` pipeline against the caller's `UserFunc *`, then run the resulting postfix through the unchanged `Line::ExpandExpression`. A heap-allocated scratch `Line` carries the postfix and is freed per call; nothing leaks into `g_script.mLineList`.

**Tech Stack:** C++17/20 (msvc + mingw), CMake (mingw build) / MSBuild (MSVC build), AHK v2.1-alpha.29 test harness via `bin\AutoHotkey64.exe test`.

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `source/globaldata.h` | modify | declare `extern bool g_AllowEval;` |
| `source/globaldata.cpp` | modify | define `bool g_AllowEval = false;` |
| `source/AutoHotkey.cpp` | modify | parse the new `/Eval` / `--eval` CLI flag → `g_AllowEval = true` |
| `source/script.h` | modify | declare `Script::ParseExprToPostfix` and `Script::FindVarInScope` |
| `source/script.cpp` | modify | implement `ParseExprToPostfix` (heap-allocated scratch `Line`, snapshot/rollback of `mVarCount`) and `FindVarInScope` |
| `source/script_object.h` | modify | add `extern Object *Syntax;` to `namespace ErrorPrototype` |
| `source/script_object.cpp` | modify | register `SyntaxError` next to `ValueError` in the class-prototype table |
| `source/error.cpp` | modify | add the `BIF_Eval` implementation (using the same file as `_ScriptGetLines`) plus a small `SyntaxError` factory helper |
| `source/lib/functions.h` | modify | add `md_func(_Eval, …)` registration alongside `md_func(_ScriptGetLines, …)` |
| `tests/test_eval.ahk` | create | positive-path test harness (run with `/Eval test`) |
| `tests/test_eval_gated.ahk` | create | negative-path test (run without `/Eval`, must throw the "disabled" message) |

No new build-system files. No new CMakeLists or vcxproj edits. Everything lands in files already in the build.

---

## Rebuild + Test Cycle

Each task below ends with a rebuild + test run. The cycle is:

```bash
# MSVC build (fastest; canonical)
cd /mnt/c/Users/uphol/Documents/Design/Coding/AutoHotkey
cmd.exe /c build_local.bat
# kill any lingering AutoHotkey64.exe instances first if the link fails with LNK1104
cmd.exe /c "taskkill /IM AutoHotkey64.exe /F"

# Run a single test script
cmd.exe /c "bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk"
# Expected exit: 0 (pass) or 14 (fail). Output goes to stdout/stderr.
```

If you prefer the mingw build (slower; produces a larger static binary):

```bash
cd /mnt/c/Users/uphol/Documents/Design/Coding/AutoHotkey/build_mingw
cmd.exe /c rebuild.bat
```

Both builds produce `bin/AutoHotkey64.exe`. The MSVC build is the default for this plan.

---

## Task 1: Bootstrap `g_AllowEval` and the `/Eval` CLI flag

**Files:**
- Modify: `source/globaldata.h` (add extern declaration near other `g_Allow*` / `g_*` bools)
- Modify: `source/globaldata.cpp` (define the global, initialised `false`)
- Modify: `source/AutoHotkey.cpp` (add case in the existing arg parser)

- [ ] **Step 1: Add the global declaration in `source/globaldata.h`**

Find the block of `extern bool g_*` declarations (e.g., near `g_AllowMainWindow`) and add:

```cpp
extern bool g_AllowEval; // /Eval flag — when false, _Eval throws "_Eval is disabled".
```

- [ ] **Step 2: Define the global in `source/globaldata.cpp`**

In the matching block of bool definitions:

```cpp
bool g_AllowEval = false;
```

- [ ] **Step 3: Parse the flag in `source/AutoHotkey.cpp`**

Locate the existing CLI flag parser (the chain of `_tcsicmp(switch_name, ...)` tests handling `/Headless`, `/ErrorStdOut`, etc.). Add a new branch alongside them:

```cpp
else if (!_tcsicmp(switch_name, _T("Eval")))
{
    g_AllowEval = true;
}
```

Match the surrounding style — if the parser strips the leading `/` before comparing, mirror that; if it expects `--eval` too, add a parallel `_tcsicmp(switch_name, _T("eval"))` branch.

- [ ] **Step 4: Verify the binary still builds and accepts `/Eval`**

```bash
cmd.exe /c "taskkill /IM AutoHotkey64.exe /F" 2>/dev/null
cmd.exe /c build_local.bat
cmd.exe /c "bin\AutoHotkey64.exe /Eval test_console.ahk"
```

Expected: the build succeeds with `Build SUCCESS`; the run executes `test_console.ahk` normally (flag is accepted but does nothing visible yet).

- [ ] **Step 5: Commit**

```bash
git add source/globaldata.h source/globaldata.cpp source/AutoHotkey.cpp
git commit -m "Add /Eval CLI flag (no-op until _Eval lands)"
```

---

## Task 2: Stub `_Eval` so it's callable and always throws

This task creates the public surface — registers `_Eval` as a built-in that any script can call — but it just throws "not implemented yet" if `/Eval` is set, or "_Eval is disabled" if not. This unlocks the test harness for every subsequent task.

**Files:**
- Modify: `source/lib/functions.h` (add `md_func` registration)
- Modify: `source/error.cpp` (add `bif_impl FResult _Eval(...)` stub at the bottom, next to `_ScriptGetLines` at line 1386)
- Create: `tests/test_eval_gated.ahk` (negative-path test)
- Create: `tests/test_eval.ahk` (positive-path test; will grow over later tasks)

- [ ] **Step 1: Write the failing positive test**

Create `tests/test_eval.ahk`:

```ahk
#Requires AutoHotkey v2.1-alpha.29

; Lightweight Assert: exits the process with code 14 on first failure.
Assert(cond, msg := "assertion failed") {
    if !cond {
        FileAppend("FAIL: " . msg . "`n", "**")
        ExitApp 14
    }
}

stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")

PrintLine "=== _Eval test (with /Eval enabled) ==="

; --- Section A: presence ---
Assert(IsSet(_Eval),     "A.1 _Eval is defined")
Assert(_Eval is Func,    "A.2 _Eval is a function")

PrintLine "all checks passed"
ExitApp 0
```

- [ ] **Step 2: Write the failing negative-path test**

Create `tests/test_eval_gated.ahk`:

```ahk
#Requires AutoHotkey v2.1-alpha.29

Assert(cond, msg := "assertion failed") {
    if !cond {
        FileAppend("FAIL: " . msg . "`n", "**")
        ExitApp 14
    }
}

stdout := FileOpen("*", "w", "UTF-8")
PrintLine(text := "") => stdout.Write(text "`n")

PrintLine "=== _Eval test (no /Eval flag) ==="

threw := false
err   := unset
try
    _Eval("1 + 1")
catch Any as e {
    threw := true
    err := e
}

Assert(threw,                                       "must throw when /Eval not set")
Assert(InStr(err.Message, "_Eval is disabled") > 0, "message mentions disabled")

PrintLine "all checks passed"
ExitApp 0
```

- [ ] **Step 3: Run both tests to confirm they fail**

```bash
cmd.exe /c "bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk"
# Expected: error — _Eval is unknown
cmd.exe /c "bin\AutoHotkey64.exe test tests\test_eval_gated.ahk"
# Expected: error — _Eval is unknown (we haven't registered it yet)
```

- [ ] **Step 4: Register `_Eval` in `source/lib/functions.h`**

Add immediately under the existing `_ScriptGetLines` line (line 8):

```cpp
md_func(_Eval, (In, String, Expression), (Ret, Variant, RetVal))
```

- [ ] **Step 5: Implement the stub in `source/error.cpp`**

Add a new function near the `_ScriptGetLines` implementation (around line 1386). The body always errors — it's a real BIF only as of Task 6:

```cpp
bif_impl FResult _Eval(StrArg aExpression, ResultToken &aRetVal)
{
    if (!g_AllowEval)
        return FR_E_FAILSTR(_T("_Eval is disabled (pass /Eval to enable)"));
    return FR_E_FAILSTR(_T("_Eval not yet implemented"));
}
```

(Look at how nearby BIFs surface error strings — if `FR_E_FAILSTR` isn't the exact macro name here, mirror whichever pattern other `bif_impl` functions use for "throw with this message".)

- [ ] **Step 6: Rebuild and run both tests**

```bash
cmd.exe /c "taskkill /IM AutoHotkey64.exe /F" 2>/dev/null
cmd.exe /c build_local.bat
cmd.exe /c "bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk"
# Expected: exit 0, "all checks passed"
cmd.exe /c "bin\AutoHotkey64.exe test tests\test_eval_gated.ahk"
# Expected: exit 0, "all checks passed"
```

- [ ] **Step 7: Commit**

```bash
git add source/lib/functions.h source/error.cpp tests/test_eval.ahk tests/test_eval_gated.ahk
git commit -m "Add _Eval BIF stub (gated by /Eval; always throws for now)"
```

---

## Task 3: Add the `SyntaxError` exception class

**Files:**
- Modify: `source/script_object.h` (add `Syntax` to `namespace ErrorPrototype`)
- Modify: `source/script_object.cpp` (register `SyntaxError` in the class prototype table)
- Modify: `tests/test_eval.ahk` (add a section that confirms `SyntaxError is Error`)

- [ ] **Step 1: Extend the positive test**

Append to `tests/test_eval.ahk` before `PrintLine "all checks passed"`:

```ahk
; --- Section B: SyntaxError class exists ---
Assert(IsSet(SyntaxError),               "B.1 SyntaxError exists")
Assert(SyntaxError.Prototype is Error.Prototype.__Class
    || HasBase(SyntaxError.Prototype, Error.Prototype),
                                          "B.2 SyntaxError extends Error")
```

If `HasBase` isn't available, use whichever idiom existing tests in this repo use to check prototype chains.

- [ ] **Step 2: Run to confirm failure**

```bash
cmd.exe /c "bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk"
# Expected: FAIL: B.1 SyntaxError exists
```

- [ ] **Step 3: Add to `namespace ErrorPrototype` in `source/script_object.h`**

Modify the existing `extern` block (around line 1040):

```cpp
namespace ErrorPrototype
{
    extern Object *Error, *Memory, *Type, *Value, *OS, *ZeroDivision;
    extern Object *Target, *Unset, *Member, *Property, *Method, *Index, *UnsetItem;
    extern Object *Timeout;
    extern Object *Syntax; // New: thrown by _Eval on parse failure.
}
```

- [ ] **Step 4: Define the storage**

Find where the other `Object *` members of `ErrorPrototype` are defined (search for `ErrorPrototype::Value =` in `script_object.cpp` or similar). Add:

```cpp
Object *Syntax = nullptr;
```

next to the others.

- [ ] **Step 5: Register `SyntaxError` in the prototype table**

In `source/script_object.cpp` around line 4356, the `ValueError` entry is:

```cpp
{_T("ValueError"), &ErrorPrototype::Value, no_ctor, no_members, {
    {_T("IndexError"), &ErrorPrototype::Index}
}},
```

Add `SyntaxError` as a sibling under `Error` (not under `ValueError`), placed alphabetically between `OSError` and `TargetError`:

```cpp
{_T("SyntaxError"), &ErrorPrototype::Syntax},
```

- [ ] **Step 6: Rebuild and re-test**

```bash
cmd.exe /c "taskkill /IM AutoHotkey64.exe /F" 2>/dev/null
cmd.exe /c build_local.bat
cmd.exe /c "bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk"
# Expected: exit 0, "all checks passed"
```

- [ ] **Step 7: Commit**

```bash
git add source/script_object.h source/script_object.cpp tests/test_eval.ahk
git commit -m "Add SyntaxError exception class (thrown by _Eval on bad parse)"
```

---

## Task 4: `Script::FindVarInScope` helper

Resolves a name against a specific `UserFunc *`'s locals first, then globals. No-op cover until Task 5 wires it in, but write + test it standalone.

**Files:**
- Modify: `source/script.h` (declare the helper as a public method of `Script`)
- Modify: `source/script.cpp` (implement it, mirroring `Script::FindVar` minus the "create" behaviour)

- [ ] **Step 1: Declare the helper in `source/script.h`**

In the `class Script` body near other `FindVar*` methods, add:

```cpp
Var *FindVarInScope(LPCTSTR aName, UserFunc *aFunc); // For runtime parse (_Eval): look in aFunc's locals, then globals. Never creates.
```

- [ ] **Step 2: Implement in `source/script.cpp`**

Find the existing `Script::FindVar` implementation, then add this companion right after it:

```cpp
Var *Script::FindVarInScope(LPCTSTR aName, UserFunc *aFunc)
{
    // 1) Caller's locals/params, if there is a caller function.
    if (aFunc)
    {
        for (int i = 0; i < aFunc->mVarCount; ++i)
        {
            Var *v = aFunc->mVar[i];
            if (v && !_tcsicmp(v->mName, aName))
                return v;
        }
        // 2) Static/closure vars on the function, if any.
        for (int i = 0; i < aFunc->mLazyVarCount; ++i)
        {
            Var *v = aFunc->mLazyVar[i];
            if (v && !_tcsicmp(v->mName, aName))
                return v;
        }
    }
    // 3) Globals — reuse the existing path. nullptr if absent (we do NOT create).
    int unused;
    return FindVar(aName, 0, &unused, FINDVAR_GLOBAL, nullptr);
}
```

If `mLazyVar` or `mLazyVarCount` aren't the actual member names on `UserFunc`, drop that block and rely on `mVar` only — comment in the source explaining the simplification.

- [ ] **Step 3: Sanity rebuild**

```bash
cmd.exe /c "taskkill /IM AutoHotkey64.exe /F" 2>/dev/null
cmd.exe /c build_local.bat
```

Expected: `Build SUCCESS`. (No test yet — this is only exercised by `BIF_Eval` in Task 6.)

- [ ] **Step 4: Commit**

```bash
git add source/script.h source/script.cpp
git commit -m "Add Script::FindVarInScope helper for runtime parse"
```

---

## Task 5: `Script::ParseExprToPostfix` entry point

Wraps the existing tokenizer/postfix conversion so `BIF_Eval` can get a runnable scratch `Line` from an arbitrary expression string. Heap-allocated, never linked into `mLineList`, rolls back `mVarCount` on failure.

**Files:**
- Modify: `source/script.h` (declare it on `Script`)
- Modify: `source/script.cpp` (implement)

- [ ] **Step 1: Declare in `source/script.h`**

In the `class Script` body:

```cpp
// Parse a single AHK expression string into a heap-allocated scratch Line whose
// mArg[0].postfix is ready for Line::ExpandExpression. Variable identifiers
// resolve against aResolveScope first, then globals. The Line is NOT linked
// into mLineList. Caller owns the returned Line and must `delete` it.
// Returns OK on success; FAIL on parse failure (sets aErrMsg/aErrColumn).
ResultType ParseExprToPostfix(LPTSTR aExpr, UserFunc *aResolveScope,
                              Line *&aOutLine, LPTSTR &aErrMsg, int &aErrColumn);
```

- [ ] **Step 2: Implement in `source/script.cpp`**

Append near the other `Script::Parse*` methods:

```cpp
ResultType Script::ParseExprToPostfix(LPTSTR aExpr, UserFunc *aResolveScope,
                                      Line *&aOutLine, LPTSTR &aErrMsg, int &aErrColumn)
{
    aOutLine = nullptr;
    aErrMsg = nullptr;
    aErrColumn = 0;

    // 1) Snapshot the global Var table so a failed parse leaks nothing.
    const int saved_var_count = mVarCount;

    // 2) Tell the resolver "treat aResolveScope as the current function".
    UserFunc *saved_current_func = mCurrentFunc;
    mCurrentFunc = aResolveScope;

    // 3) Build a scratch ArgStruct holding the expression text.
    //    Line::Parse-style code calls ExpressionToPostfix on a Line's mArg[i].
    Line *scratch = new Line(0 /* file index */, 0 /* line number */,
                             ACT_EXPRESSION, nullptr /* mArg */, 0);
    if (!scratch)
    {
        mCurrentFunc = saved_current_func;
        return FAIL;
    }

    // Allocate one ArgStruct for the expression.
    ArgStruct *arg = (ArgStruct *)SimpleHeap::Alloc(sizeof(ArgStruct));
    memset(arg, 0, sizeof(*arg));
    arg->type = ARG_TYPE_INPUT_VAR; // gets re-flagged once postfix is attached
    arg->text = SimpleHeap::Malloc(aExpr);
    arg->is_expression = true;
    scratch->mArg = arg;
    scratch->mArgc = 1;

    // 4) Convert text to postfix using the existing pipeline.
    //    ExpressionToPostfix mutates arg->postfix in place. Returns OK or FAIL.
    if (ExpressionToPostfix(arg) != OK)
    {
        // Roll back any vars the parser might have created.
        mVarCount = saved_var_count;
        mCurrentFunc = saved_current_func;
        aErrMsg = mLastErrorText; // grab whatever the parser stored
        aErrColumn = 0; // best-effort; tokenizer doesn't surface columns directly
        delete scratch; // also frees its arg via existing ~Line
        return FAIL;
    }

    mCurrentFunc = saved_current_func;
    aOutLine = scratch;
    return OK;
}
```

The exact names `ExpressionToPostfix`, `mLastErrorText`, `SimpleHeap::Alloc`/`Malloc`, and the `Line` constructor signature may differ slightly — match what's in this repo. The key invariants are:
- snapshot/rollback `mVarCount` on the failure path
- swap `mCurrentFunc` so var resolution sees the caller's scope, then restore
- never link the scratch `Line` into `mLineList`
- delete the scratch on failure so we don't leak

- [ ] **Step 3: Sanity rebuild**

```bash
cmd.exe /c "taskkill /IM AutoHotkey64.exe /F" 2>/dev/null
cmd.exe /c build_local.bat
```

Expected: `Build SUCCESS`. Still no behaviour change at script level — Task 6 hooks it up.

- [ ] **Step 4: Commit**

```bash
git add source/script.h source/script.cpp
git commit -m "Add Script::ParseExprToPostfix runtime-parser entry point"
```

---

## Task 6: Wire `BIF_Eval` to actually evaluate

The payload task. Calls `ParseExprToPostfix`, then runs `Line::ExpandExpression` against the caller's frame, then copies the result into `aRetVal`.

**Files:**
- Modify: `source/error.cpp` (replace the stub body with the real implementation)
- Modify: `tests/test_eval.ahk` (add Section C: basic expressions)

- [ ] **Step 1: Extend the test with basic-expression coverage**

In `tests/test_eval.ahk`, before `PrintLine "all checks passed"`:

```ahk
; --- Section C: basic expressions ---
Assert(_Eval("1 + 2") = 3,                       "C.1 arithmetic")
Assert(_Eval("'hi ' . 'there'") = "hi there",    "C.2 string concat")
Assert(_Eval("[1,2,3].Length") = 3,              "C.3 method call")
Assert(_Eval("(()=> 7)()") = 7,                  "C.4 fat-arrow IIFE")
```

- [ ] **Step 2: Run to confirm failure**

```bash
cmd.exe /c "bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk"
# Expected: FAIL on C.1 — "_Eval not yet implemented"
```

- [ ] **Step 3: Replace the stub in `source/error.cpp`**

Replace the entire body of the stub from Task 2 with:

```cpp
bif_impl FResult _Eval(StrArg aExpression, ResultToken &aRetVal)
{
    if (!g_AllowEval)
        return FR_E_FAILSTR(_T("_Eval is disabled (pass /Eval to enable)"));

    // Walk to the caller's UserFunc *. g->CurrentFunc is set during the call.
    UserFunc *caller = g ? g->CurrentFunc : nullptr;

    // Copy the input — the parser may write into the buffer.
    size_t len = _tcslen(aExpression);
    LPTSTR buf = (LPTSTR)talloca(len + 1);
    _tcscpy(buf, aExpression);

    Line *scratch = nullptr;
    LPTSTR errMsg = nullptr;
    int errCol = 0;

    if (g_script.ParseExprToPostfix(buf, caller, scratch, errMsg, errCol) != OK)
    {
        // Throw SyntaxError with message + column.
        // Mirror whatever ThrowError(prototype, msg, ...) helper this codebase uses.
        return g_script.RuntimeError(errMsg ? errMsg : _T("Expression parse error"),
                                     nullptr, FAIL, nullptr, ErrorPrototype::Syntax);
    }

    // Evaluate.
    ResultType eval_result = scratch->ExpandExpression(/* arg index */ 0,
                                                       /* aResult */ &aRetVal,
                                                       /* aResultTokens */ &aRetVal,
                                                       /* buf */ nullptr,
                                                       /* deref buf */ nullptr,
                                                       /* deref buf size */ nullptr,
                                                       /* arg_deref */ nullptr,
                                                       /* extra_size */ 0);
    delete scratch;

    if (eval_result == FAIL || eval_result == EARLY_EXIT)
        return FR_FAIL; // propagate underlying error

    return OK;
}
```

The exact `ExpandExpression` overload and signature should match whatever exists in this repo — the `script_expression.cpp` patched in commit `7ec53636` is the source of truth. Adapt the call shape to match.

- [ ] **Step 4: Rebuild and run**

```bash
cmd.exe /c "taskkill /IM AutoHotkey64.exe /F" 2>/dev/null
cmd.exe /c build_local.bat
cmd.exe /c "bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk"
# Expected: exit 0, "all checks passed"
```

- [ ] **Step 5: Commit**

```bash
git add source/error.cpp tests/test_eval.ahk
git commit -m "Implement _Eval: parse + evaluate expression in caller scope"
```

---

## Task 7: Caller-scope read

**Files:**
- Modify: `tests/test_eval.ahk` (add Section D)

- [ ] **Step 1: Extend the test**

Before `PrintLine "all checks passed"`:

```ahk
; --- Section D: caller-scope read ---
x := 10
y := 20
Assert(_Eval("x + y") = 30,           "D.1 reads caller locals")
Assert(_Eval("A_AhkVersion") != "",   "D.2 reads built-in globals")
```

- [ ] **Step 2: Run**

```bash
cmd.exe /c "bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk"
```

If D.1 fails with "x not defined" or similar, the `ParseExprToPostfix` resolver from Task 5 isn't wired through correctly — recheck the `mCurrentFunc` swap. If D.2 fails, globals aren't reachable — check `FindVar` fallback in `FindVarInScope`.

- [ ] **Step 3: Fix any resolver bug, rebuild, rerun until pass**

- [ ] **Step 4: Commit**

```bash
git add tests/test_eval.ahk
git commit -m "_Eval test: reads caller's locals and globals"
```

---

## Task 8: Caller-scope write

**Files:**
- Modify: `tests/test_eval.ahk` (add Section E)

- [ ] **Step 1: Extend the test**

```ahk
; --- Section E: caller-scope write ---
x := 10
_Eval("x := 99")
Assert(x = 99,                                "E.1 mutates caller local")
_Eval("x += 1")
Assert(x = 100,                               "E.2 compound assignment")
```

- [ ] **Step 2: Run, debug, commit**

```bash
cmd.exe /c "bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk"
git add tests/test_eval.ahk
git commit -m "_Eval test: writes to caller's local vars"
```

If E.1 fails, the resolver is returning a *copy* of the var instead of a reference — confirm the `Var*` returned by `FindVarInScope` is the same pointer the caller frame is using.

---

## Task 9: Alpha.29 features pass through

**Files:**
- Modify: `tests/test_eval.ahk` (add Section F)

- [ ] **Step 1: Extend the test**

```ahk
; --- Section F: alpha.29 features ---
Assert(_Eval("(missing? > 0) ?? 'fb'") = "fb",     "F.1 maybe operator")
arr := [1, , 3]
removed := _Eval("arr.RemoveAt(2)") ?? "<unset>"
Assert(removed = "<unset>",                         "F.2 unset propagates")
Assert(_Eval("(() => unsetLocal? || 42)()") ?? 0,   "F.3 IIFE short-circuit doesn't crash")
```

- [ ] **Step 2: Run, fix, commit**

```bash
cmd.exe /c "bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk"
git add tests/test_eval.ahk
git commit -m "_Eval test: alpha.29 maybe-operator + unset propagation"
```

These should pass without further engine work because `ExpandExpression` is exactly the path alpha.29 uses for inline code. If they fail, something in the scratch `Line` setup is bypassing the alpha.29 codepath.

---

## Task 10: `SyntaxError` with `Column` info

**Files:**
- Modify: `source/error.cpp` (extend the `SyntaxError` factory to set a `Column` property)
- Modify: `tests/test_eval.ahk` (add Section G)

- [ ] **Step 1: Extend the test**

```ahk
; --- Section G: SyntaxError ---
threw := false
caught := unset
try _Eval("1 + + +")
catch SyntaxError as e {
    threw := true
    caught := e
}
Assert(threw,                              "G.1 bad input throws SyntaxError")
Assert(caught.Message != "",               "G.2 message is non-empty")
Assert(caught.HasProp("Column"),           "G.3 has Column property")
```

- [ ] **Step 2: Run — expect G.3 to fail**

```bash
cmd.exe /c "bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk"
# Expected: FAIL: G.3 — no Column property
```

- [ ] **Step 3: Set `Column` on the thrown error**

In `BIF_Eval`'s error path (replacing the simple `RuntimeError(...)` call), construct the error object explicitly, set `Column`, then return it:

```cpp
if (g_script.ParseExprToPostfix(buf, caller, scratch, errMsg, errCol) != OK)
{
    auto err = Object::Create();
    err->SetBase(ErrorPrototype::Syntax);
    err->SetOwnProp(_T("Message"), errMsg ? errMsg : _T("Expression parse error"));
    err->SetOwnProp(_T("File"),    _T("_Eval"));
    err->SetOwnProp(_T("Line"),    0);
    err->SetOwnProp(_T("Column"),  errCol);
    aRetVal.SetExitResult(FAIL);
    g->ThrownToken = err; // or whatever the existing "set thrown" path is
    return FR_FAIL;
}
```

Match this codebase's actual "throw a constructed object" pattern. If it has a helper like `g_script.Throw(ErrorPrototype::Syntax, msg, {Column: errCol})`, prefer that.

- [ ] **Step 4: Rebuild, run, commit**

```bash
cmd.exe /c "taskkill /IM AutoHotkey64.exe /F" 2>/dev/null
cmd.exe /c build_local.bat
cmd.exe /c "bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk"
git add source/error.cpp tests/test_eval.ahk
git commit -m "_Eval: surface SyntaxError with Column info on parse failure"
```

---

## Task 11: Reentrancy

No engine work expected — Task 5 designed for it. This task only confirms.

**Files:**
- Modify: `tests/test_eval.ahk` (add Section H)

- [ ] **Step 1: Extend the test**

```ahk
; --- Section H: reentrancy ---
Assert(_Eval("_Eval('1 + 1') + _Eval('2 + 2')") = 6, "H.1 nested _Eval")
Assert(_Eval("_Eval('_Eval(\"3 * 3\")')") = 9,       "H.2 deeply nested")
```

- [ ] **Step 2: Run, commit**

```bash
cmd.exe /c "bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk"
git add tests/test_eval.ahk
git commit -m "_Eval test: reentrancy (nested _Eval calls)"
```

If H.1 fails, something is stashed in a static instead of per-call heap state — recheck the scratch `Line` allocation in Task 5.

---

## Task 12: Regression sweep + mingw parity

Run the Alpha22 → Alpha29 examples plus the new tests through both builds to confirm `_Eval` didn't disturb anything.

**Files:** none

- [ ] **Step 1: MSVC regression**

```bash
cmd.exe /c "taskkill /IM AutoHotkey64.exe /F" 2>/dev/null
cmd.exe /c build_local.bat
for /l %i in (22,1,29) do cmd.exe /c "bin\AutoHotkey64.exe Alpha%i_Example.ahk"
cmd.exe /c "bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk"
cmd.exe /c "bin\AutoHotkey64.exe test tests\test_eval_gated.ahk"
```

Expected: every Alpha example exits 0 with the expected output; both test scripts exit 0.

- [ ] **Step 2: mingw regression**

```bash
cd /mnt/c/Users/uphol/Documents/Design/Coding/AutoHotkey/build_mingw
cmd.exe /c rebuild.bat
cd /mnt/c/Users/uphol/Documents/Design/Coding/AutoHotkey
cmd.exe /c "bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk"
cmd.exe /c "bin\AutoHotkey64.exe test tests\test_eval_gated.ahk"
```

Expected: mingw build still succeeds; same test outputs as MSVC.

- [ ] **Step 3: Commit a tag-style summary if anything moved**

If any regression surfaced and was fixed, commit those fixes. Otherwise no commit needed.

```bash
git tag eval-v1-complete   # local tag; remove if you don't want it
```

---

## Done condition

All twelve tasks complete, both builds (MSVC + mingw) green, both test scripts pass, all Alpha22-29 examples still run. The README/CLAUDE.md don't need updating in v1 — that's a follow-up doc task once the API has bedded in.
