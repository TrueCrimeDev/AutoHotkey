# Check(Source) BIF — in-process trustworthy AHK validity

- **Date:** 2026-06-14
- **Status:** Approved design, pending implementation plan
- **Branch:** `feat/check-bif-validity`
- **Area:** engine BIF (`source/`), MSVC-only — built/verified via CI

## Problem

The fork has two ways to look at AHK source, and they disagree on validity:

- **`TSParse(Source)`** (tree-sitter) returns a structure tree with a `HasError`
  flag. The vendored grammar is **incomplete for this fork**, so `HasError` is
  `1` on *valid* code (typed `Struct`s, fat-arrow methods, hotkeys like `^j::`).
  Good for structure, **wrong for validity**.
- **`check` mode** (`AutoHotkey64.exe check file.ahk`, also `/Check` /
  `--check`) runs the engine's *own* parser and is correct by construction —
  but it is **process-only**: it needs a file on disk and a separate process,
  and there is no way to validate an in-memory string from a running script.

So a tool or script that already has source in memory (the `ast_outline` MCP
tool, a linter, validating input before `Eval`) cannot get a trustworthy
yes/no without shelling out and writing a temp file — and if it reaches for
`TSParse.HasError` instead, it gets wrong answers.

### Evidence (same fork-valid file through both oracles)

Input: `#Requires v2.1-alpha.30`, a typed `Struct`, a `f() => 42` method, and `^j::MsgBox("hi")`.

| Source | `check` (engine parser) | `TSParse.HasError` |
|---|---|---|
| valid script | `{"kind":"check","status":"pass"}` exit 0 | — |
| broken (`x :=` / `if (`) | `{"kind":"diagnostic","schema":2,"message":"Missing \")\"","line":2,"column":0,...}` exit 13 | — |
| **fork-valid** | **`status:pass`** ✓ | **`HasError=1`** ✗ |

The correct oracle already exists. The work is to **bring it in-process** and
to **stop `TSParse.HasError` from being mistaken for validity**.

## Goal

A native BIF that answers "is this AHK source syntactically valid?" correctly,
in-process, from a string — reusing the engine's own parser (the same path
behind `check` mode), with no temp file and no subprocess.

### Non-goals

- **Not** fixing the tree-sitter grammar (separate effort; needs the grammar
  source, which is not vendored).
- **Not** semantic/type analysis — syntactic validity only, exactly what `check`
  reports today.
- **Not** multi-error reporting in v1. The engine parser stops at the first
  syntax error; v1 surfaces that one. The return shape leaves room for more
  later.
- **Not** changing what `TSParse` returns (the tree shape stays; only its docs
  get an honesty note).

## The contract

```autohotkey
result := Check(Source)          ; Source is the whole AHK script text (a String)
result.Ok                        ; 1 = syntactically valid, 0 = has errors
result.Diagnostics               ; Array; empty when Ok = 1
  ; each diagnostic: { Severity, Type, Code, Message, Extra, Line, Column, File }
```

- The diagnostic object fields mirror the existing `/Diag=json` `schema 2`
  payload, so `Check` and the CLI report the *same* shape for the same input.
- `status:pass` from the validate path ⇒ `Ok = 1`, `Diagnostics = []`.
  A diagnostic ⇒ `Ok = 0`, `Diagnostics = [ <that diagnostic> ]` (length 1 in v1).
- `File` defaults to `""` (string input has no path). An options object may be
  added later to set a reported filename; not required for v1.
- Errors in *using* `Check` (e.g. non-string argument) throw normally; a parse
  failure of `Source` is **not** an exception — it is reported via `Ok`/`Diagnostics`.

## Mechanism

Reuse the validate path behind `check` mode, driven from a string instead of a
file. The pieces already exist in the engine:

- In-memory script source loading: `LoadIncludedFile()` already accepts a
  synthetic in-memory source (the `*REPL` path, `AutoHotkey.cpp` ~line 332).
- Validate-then-exit semantics: `mCheckMode` / `mValidateThenExit`
  (`AutoHotkey.cpp`, `script.cpp`, `error.cpp`).
- Structured diagnostics: the `mDiagJson` emission path in `error.cpp`
  (`schema 2`). `Check` captures these into an AHK object instead of printing.

## The hard part: isolation (go/no-go gate)

The engine's line/class parser builds into the **global `g_script`** singleton.
`Check` is called from a *running* script, so it must parse the candidate
source in an **isolated context** without disturbing the live script's lines,
variables, functions, or classes.

`Eval` isolates a single *expression* (deref-buffer privatization +
`SyntaxError`), but a full-script `Check` needs the statement/declaration parser,
which is tied to `g_script`. Resolving that isolation is the central risk.

**The implementation plan's first task is a feasibility spike** that picks the
isolation mechanism and proves it before any production coding:

1. **Preferred:** parse into a throwaway secondary parse context / `Script`
   instance, collect `SyntaxError`s, discard it.
2. **Fallback:** save and restore `g_script`'s mutable parse state around a
   validate pass.

**Go/no-go:** if neither is tractable purely in-process, the only correct
remaining option is a subprocess — which is explicitly **out of scope** for this
design. In that case the spike fails and we stop and re-decide, rather than
shipping a subprocess behind an in-process-looking BIF. The contract above is
designed to be stable regardless of which isolation mechanism wins.

## Paired change: stop `TSParse.HasError` from lying

Keep `HasError` (don't break the documented tree shape), but make its meaning
explicit in the docs: it flags **tree-sitter error/missing nodes**, which on
this fork's incomplete grammar includes valid code — it is **structure-only**.
Add a cross-reference everywhere `TSParse` is documented:
**structure → `TSParse`, validity → `Check`** (`docs/TREE_SITTER.md`,
`CLAUDE.md`). No rename in v1.

## Testing

The CLI `check` is the **oracle**. The test feeds identical sources to both
`Check(src)` (in-process) and `AutoHotkey64.exe check <file>` (CLI) and asserts
they agree on `Ok` and on the diagnostic fields.

Cases:
- **valid** trivial script → `Ok = 1`.
- **broken** script (unbalanced paren) → `Ok = 0`, diagnostic `Line`/`Column`/
  `Message` match the CLI JSON.
- **fork-valid** trio (typed `Struct` + `=>` method + `^j::` hotkey) →
  `Ok = 1`. Headline regression proof: the same source has
  `TSParse(src).HasError == 1`.
- **isolation:** after `Check(badSrc)`, the calling script's own state is intact
  (a sentinel variable/function defined before the call still works, and the
  script continues running normally).

Test file: `tests/test_check_bif.ahk`, run with the rebuilt engine; assert
`PASS` and exit 0.

## Build & verification

The engine is MSVC-only; it cannot be built in WSL. Use the established CI build
loop: push the branch → GitHub Actions compiles (x64 + Win32) → `gh run download`
the artifact → install over `bin/AutoHotkey64.exe` → runtime-test locally.

## Files expected to change

- `source/error.cpp` — `Check` BIF implementation (next to `TSParse` / `Eval`).
- `source/lib/functions.h` — register the BIF (mirrors the `TSParse` row).
- `source/` validate path — whatever the spike needs to run the parse on a
  string in isolation and return diagnostics instead of printing/exiting
  (touch points: `AutoHotkey.cpp`, `script.cpp`, `error.cpp`).
- `docs/TREE_SITTER.md`, `CLAUDE.md` — `Check` docs + `TSParse.HasError` honesty
  note.
- `tests/test_check_bif.ahk` — new test.

## Open questions (resolve during the plan)

- Which isolation mechanism survives the spike (secondary context vs.
  save/restore)?
- Does any existing global parser state (e.g. `#Requires`, `#SingleInstance`,
  directives in `Source`) leak side effects even in "validate only" mode, and
  how is that contained?
- Final BIF name: `Check` vs. something namespaced — `Check` is assumed here.
