# `_Eval` Built-In — Design

**Status:** approved, ready for implementation planning
**Date:** 2026-05-12
**Target:** AHK v2.1-alpha.29+Console fork (this repo)
**Scope:** new engine-level built-in function. C++ work in `source/`. Ships with `bin/AutoHotkey64.exe`.

## Goal

Add a runtime expression evaluator so AHK scripts (and the MCP debugger) can evaluate AHK expression strings against the caller's live scope. Concretely:

```ahk
x := 10
y := 20
result := _Eval("x + y")        ; -> 30
_Eval("x := x + 1")             ; mutates caller's x
_Eval("(missing? > 0) ?? 'fb'") ; alpha.29 maybe-operator semantics
```

This is the fork's first proper "REPL primitive." Once it exists, the MCP server's `evaluate` tool can drop its DBGp-eval limitations and pipe arbitrary AHK through it; CI tests can assert against live state; users can write self-inspecting debug helpers.

Out of scope for v1:
- Multi-statement evaluation (`if`, `loop`, function defs). Single expression only — assignments are expressions, so `:=` works.
- Explicit-scope argument (`_Eval(expr, Map(...))`). Always caller's scope in v1; reserved as a future overload.
- Postfix cache. Re-parse every call. Add later if profiles say so.
- MCP wiring. Built-in lands first; debugger integration is a follow-up spec.

## Public API

```ahk
result := _Eval(Expression)
```

| Parameter | Type | Notes |
|---|---|---|
| `Expression` | `String` | A single AHK expression. Must parse as the right-hand side of `x := <here>`. |

**Returns:** the value the expression evaluated to. May be `unset` (e.g., `_Eval("[1,,3].RemoveAt(2)")` in v2.1 mode) — assignments to the call site obey the alpha.29 unset-propagation rules.

**Throws:**

| When | Class | Message |
|---|---|---|
| `/Eval` flag not set | `ValueError` | `"_Eval is disabled (pass /Eval to enable)"` |
| Expression doesn't parse | `SyntaxError` | parser's existing diagnostic + `Column` property pointing at the offending token |
| Identifier not visible in caller scope | `UnsetError` | same as inline code referencing an unset var |
| Anything raised by the evaluated expression | unchanged | propagated as-is (existing try/catch path) |

`SyntaxError` is a new exception class — see "Error class" below.

## Gating

`_Eval` is off by default. A new CLI flag `/Eval` enables it for the process:

```
bin\AutoHotkey64.exe /Eval script.ahk
```

Without `/Eval`, `_Eval` is still a known identifier (no `UnknownFunctionError`) but calling it throws the `ValueError` above. This is intentional — scripts can `try _Eval(...)` to feature-detect.

No script directive, no compile-time switch, no runtime API in v1. We can add `#EnableEval`, `AHK_ENABLE_EVAL`, or `_EvalEnable()` later without breaking the CLI flag.

## Architecture

### Data flow

```
script.ahk                                              bin/AutoHotkey64.exe
─────────                                               ─────────────────────
_Eval("x + 1")
        │
        ▼
[BIF_Eval]  in script_object_bif.cpp
        │
        │ 1. check g_AllowEval                  (gate)
        │ 2. ParamIndexToString(0) → "x + 1"
        │ 3. caller = g->CurrentFunc            (snapshot caller frame)
        │ 4. snapshot g_script.mVarCount        (rollback marker)
        │
        ▼
[Script::ParseExprToPostfix]  new entry point in script.cpp
        │
        │ • runs the existing tokenizer/postfix conversion against `caller`'s mVar
        │ • returns (Line *scratch, ResultType ok|fail)
        │ • on fail: rewinds mVarCount, sets a parse-error message
        │
        ▼
[Line::ExpandExpression]  existing function (the one we patched for goto-init)
        │
        │ • stack-based postfix evaluator
        │ • runs in caller's frame; reads/writes its locals
        │ • returns a ResultToken
        │
        ▼
[BIF_Eval cleanup]
        │ • delete scratch Line + postfix
        │ • on parse failure → _f_throw_value(SyntaxError, …)
        │ • else copy ResultToken into aResultToken; preserves unset
        ▼
back to script
```

### New entry points

1. **`BIF_Eval(ResultToken &aResultToken, ExprTokenType **aParam, int aParamCount)`**
   File: `source/script_object_bif.cpp`.
   Registered in the BIF table (same table as `_ScriptGetLines`).
   Visible regardless of `#Requires` mode.

2. **`ResultType Script::ParseExprToPostfix(LPTSTR aExpr, UserFunc *aResolveScope, Line *&aOutLine, LPTSTR &aErrMsg, int &aErrColumn)`**
   File: `source/script.cpp`.
   Wraps the existing expression-parsing pipeline (tokenizer → `ExpressionToPostfix`) but configures it to:
   - Resolve identifiers against `aResolveScope->mVar` first, then globals.
   - Allocate the returned `Line` on the heap, **not** link it into `mLineList`.
   - Snapshot/rollback `mVarCount` so failed parses leak no phantom Vars.
   - Set `aErrMsg`/`aErrColumn` on parse failure.

3. **`Var *Script::FindVarInScope(LPCTSTR aName, UserFunc *aFunc)`**
   File: `source/script.cpp`.
   Helper that mirrors normal load-time `Var::Find()` but with `aFunc` as the override for "current function" so caller-locals win the resolution lookup.

### Why a scratch `Line`?

`Line::ExpandExpression` takes a `Line*` and reads `mArg`, `mArgc`, `mActionType` for diagnostics. The cheapest way to leave the evaluator unmodified is to hand it a one-arg `Line` with `mActionType = ACT_EXPRESSION` and the postfix attached to `mArg[0].postfix`. The Line is heap-allocated inside `BIF_Eval`, owned for the call, freed before return (or before throw).

The scratch Line is **not** linked into `g_script.mLineList`, so:
- it doesn't show up in stack traces
- it can't be hit by breakpoints
- `_ScriptGetLines` won't see it

### Error class: `SyntaxError`

New exception class hanging off `Error`:

```
Error
└── SyntaxError    (new)
    .Message       (parser diagnostic text)
    .File          ("_Eval")
    .Line          (0)
    .Column        (new — 1-based offset into the source string)
```

Registered alongside the existing error prototypes (`UnsetError`, `ValueError`, `TypeError`). Single new prototype object; tiny payload.

## Identifier resolution

At parse-runtime, a bare name `foo` in the input string resolves like this:

1. Look up in `aResolveScope->mVar` — caller's locals/params. If found, bind.
2. Else look up in `g_script.mGlobalVars`. If found, bind.
3. Else the parser would normally create a new local. **We disable that path** for `_Eval` and treat unknown names as dynamic refs (`Var::IsUninitialized()` style), which raises `UnsetError` at evaluation if the name is genuinely missing.

This matches inline-code semantics for declared functions in v2.1 — you can't accidentally create a new local from `_Eval`.

## Lifecycle / safety

- **No global side-effects on failure.** Snapshot `mVarCount` before parsing; rewind on failure. Free the scratch Line. The parse leaves the script's symbol table identical to its pre-call state.
- **Reentrancy.** Every call gets its own heap-allocated scratch Line; nothing stashed in statics. `_Eval("_Eval('1+1')")` is well-defined.
- **Thread/interrupt safety.** Evaluation participates in the existing thread queue. `OnMessage`, hotkeys, and the debugger can pre-empt `_Eval` exactly like they pre-empt inline code. No new locks.
- **Lifetime of the result.** The returned `ResultToken` is copied into the caller's `aResultToken` slot using the existing assignment path; if the expression yielded an object, refcount is bumped normally.

## CLI flag

`source/AutoHotkey.cpp` argument parser gains:

```c++
else if (!_tcsicmp(arg, _T("/Eval")) || !_tcsicmp(arg, _T("--eval")))
    g_AllowEval = true;
```

`g_AllowEval` is a new global `bool` in `globaldata.cpp` / `globaldata.h`, defaulting to `false`.

## Testing plan

### Positive path — `tests/test_eval.ahk`

Runs under `bin\AutoHotkey64.exe /Eval test tests\test_eval.ahk`. Exits 0 on success.

Sections covered:

| ID | What it checks |
|---|---|
| A | basic arithmetic / string / method call expressions |
| B | reads caller locals and globals (`x + y`, `A_AhkVersion`) |
| C | writes caller locals (`_Eval("x := 99")` mutates `x`) |
| D | alpha.29 features pass through unchanged (maybe operator, unset propagation) |
| E | `SyntaxError` thrown on bad input and carries `.Column` |
| F | reentrancy (`_Eval` inside `_Eval`) |

### Negative path — `tests/test_eval_gated.ahk`

Runs under `bin\AutoHotkey64.exe test tests\test_eval_gated.ahk` (no `/Eval`). Must throw `ValueError("_Eval is disabled (pass /Eval to enable)")` and exit 14.

### Sanity / regression

- `bin\AutoHotkey64.exe check tests\test_eval.ahk` must exit 0 (script is syntactically valid even when `_Eval` is disabled at runtime).
- `Alpha22_Example.ahk` through `Alpha29_Example.ahk` must still run cleanly — confirms the expression evaluator we just patched for mingw isn't disturbed by the new entry points.

## Build impact

The new code lives in files already in both builds: `script_object_bif.cpp`, `script.cpp`, `AutoHotkey.cpp`, `globaldata.cpp`/`.h`, plus the new `SyntaxError` prototype hooked into the existing error-class table. No new source files. No edits to `CMakeLists.txt` or `AutoHotkeyx.vcxproj` required.

Binary size impact: ~3–5 KB of new code; negligible.

## Open questions

None blocking. Anything that comes up during implementation goes into the implementation plan rather than amending this spec.

## Out of v1 — future work

- `_Eval(expr, scopeMap)` overload for explicit-scope evaluation
- `_ParseExpr(expr) -> AST` to expose the postfix to scripts
- `_Exec(stmts)` for multi-statement / control-flow evaluation
- Postfix cache (`StringHash → Line*`) for hot eval paths
- MCP `evaluate` tool wired to `_Eval` instead of DBGp eval
- Script directive `#EnableEval` for per-script opt-in
- Compile-time `AHK_DISABLE_EVAL` for locked-down builds
