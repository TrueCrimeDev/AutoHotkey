# AutoHotkey Fork — Autonomous Loop WORKLOG

**Goal:** grow this fork's verification layer — a real interpreter
regression suite, empirically verified alpha docs, and runnable examples —
so interpreter work (local and upstream merges) lands on proof instead of
hope.

**Loop rules recap:** no git commits/pushes/branch switches ever; additive
work preferred; source/ edits require a failing-first regression test and a
green `build.bat` rebuild; leave the tree green.

**How to run things:**
- Interpreter: `bin\AutoHotkey64.exe /ErrorStdOut <script>` — console
  build, stdout works headless, exit codes propagate. Currently
  `2.1-alpha.30+Console`.
- Build (only after source/ changes): `build.bat` from repo root
  (mingw-w64 GCC via `C:\msys64`, ~static binary to `bin\`).
- Test suite: NONE YET (see Next). `tests/` holds 36 ad-hoc scripts,
  mostly manual crashlog/debugger experiments — do not treat them as a
  suite; many require interaction or intentionally crash.

**Known alpha facts (verified 2026-07-08 on 2.1-alpha.30+Console):**
- `Struct Name { x: Int32 }`: field types are class references
  (Int8/16/32/64, UInt8/16/32, Float32/64, IntPtr; no UInt64). The
  `i32`-style string shorthand is REMOVED (parses as undefined var, fatal
  at class init). Typeless size-only fields REMOVED. `StructFromPtr`
  REMOVED (auto `.Ptr` subclasses replace it, semantics undocumented).
- Instances expose `.Size` and `.Ptr`; DllCall takes struct instances
  directly for "ptr" args including output args; nested struct fields
  commit to the parent memory block.
- `Int32[4]` / array fields: `Struct.Array` types — 1-based, bounds-checked
  (0 and n+1 throw "Invalid index"), `.Length`, `.Ptr`, NOT enumerable.
- Fork-specific: variadic `Print(Fmt, Values*)` BIF to stdout; `"Void"`
  DllCall/ComCall/CallbackCreate return type.
- Type table source of truth: `source/script_object.cpp` (~line 4400).
- Reference material: `docs/alpha/v2.1-alpha.{20..30}.md`,
  `examples/Alpha30_Example.ahk` (current state), `examples/alpha22/`
  (numbered per-feature style), `updates.md`.
- A downstream consumer to keep green: the Win32Struct catalog at
  `..\NewLoop` (its `tests\run.ahk` exercises the Struct system end to
  end — 30 assertions; useful as an integration canary after rebuilds).

---

## Backlog

1. ~~**Unified regression runner**~~ **DONE (session 1)**: `qa/run.ahk` +
   `qa/Assert.ahk` — subprocess-per-test model (each spawned in its own
   process; FAIL vs CRASH distinguished; suite exit code = fails+crashes).
   `qa/README.md` documents usage. Kept out of `tests/`.
2. **Struct system regression tests**: sizes/alignment, nested commit
   semantics, array bounds/1-basing, `.Ptr` subclass behavior (probe +
   pin), DllCall output-arg `__Value` error propagation (alpha.30 fix).
3. **Language-change tests**: `(a?)()` / `(a?)[]` replacements, removed
   `a?.()` raising load-time errors, `!a ?? b` ambiguity rejection,
   `StrGet(x, 0)` returning String, unset-through-VarRef.
4. **`Print` BIF contract tests**: format dispatch on 2+ args, literal
   braces on single arg, `{1}` reuse.
5. **Verify docs/alpha claims**: one doc per session against the binary;
   annotate discrepancies; write missing notes for post-alpha.30 merges.
6. **Examples for alpha.23–.30 features** in the numbered alpha22/ style.
7. **Module system (`Import`)**: empirical tests for search-path rules
   (alpha.20 notes mention fixes); document what actually resolves.
8. **Crashlog/stderr-file directives**: turn the manual
   `tests/test_crashlog_*.ahk` experiments into asserted subprocess tests.
9. **Upstream tracking**: identify upstream (lexikos) remote/commit the
   fork last merged (updates.md mentions 34b17011); log a merge-delta
   checklist — investigation only, no fetch/pull.

## Sessions

### Session 1 (2026-07-09) — regression runner + first seed tests
- Built `qa/` verification layer (additive; no source/ changes):
  - `qa/Assert.ahk` — eq/truthy/falsy/throws(+msg substring)/noThrow;
    `Summary()` prints a parseable `qa: P passed, F failed` line and exits
    with code = failures (green standalone).
  - `qa/run.ahk` — **subprocess-per-test** runner. Globs `qa/tests/test_*.ahk`,
    runs each in its own process via `cmd /c … /ErrorStdOut … > tmp`, parses
    the summary line, and reports PASS / FAIL / CRASH. Chosen over NewLoop's
    single-process `#Include` model precisely so a test that dies at load time
    (parse error) is assertable, not fatal to the suite. Suite exit = fails +
    crashes.
  - `qa/README.md` — run + authoring docs.
- Seed tests, all facts empirically probed against `2.1-alpha.30+Console`
  first, then baked as asserts:
  - `qa/tests/test_struct.ahk` (16 asserts) — Struct sizes (PT=8, NEST=12,
    AR=16), field↔raw-memory backing, nested `pt.y` commits to parent at
    offset 8, `Struct.Array` 1-based + `.Length` + index 0/n+1 throw
    "Invalid index".
  - `qa/tests/test_language.ahk` (8 asserts) — `StrGet(ptr,0)`→empty `String`;
    `Format` `{}`/`{1}` reuse/`{2},{1}` order/single-arg-literal; `(fn?)()`
    invokes when set, `(unsetFn?)()` no-ops when unset.
- Verified the runner's three report paths with throwaway fail/crash tests
  (correct tallies, exit 2), then removed them. Final: **24 passed, exit 0**.
- Probed-and-rejected (don't re-add): `Struct` single-line
  `{ x: Int32, y: Int32 }` won't parse (fields need own lines); maybe-index
  `(arr?)[2]` and `arr?[2]` both parse-error; fat-arrow bodies can't write an
  outer/global var (use an object accumulator).
- Engine invocation gotcha: from the Bash tool, MSYS mangles leading-slash
  flags — prefix `MSYS2_ARG_CONV_EXCL='*'` so `/ErrorStdOut` survives.

**Next:** extend seeds — `Print` BIF stdout contract (needs a stdout-capture
harness, backlog #4), removed-syntax load-error asserts (spawn bad snippet as
child, assert nonzero exit — backlog #3), `.Ptr` subclass probes (#2).

### Session 2 (2026-07-09) — child-process harness + Print/removed-syntax seeds
- Added `qa/Harness.ahk` — `RunSnippet(src)` writes a snippet to a temp `.ahk`,
  runs it as its own process (same `A_ComSpec … /ErrorStdOut … >tmp 2>&1` form
  as `run.ahk`), returns `{ code, out }`; `SnippetOut(src)` is the stdout-only
  shortcut. This is the missing primitive for asserting on things the parent
  can't see: exact `Print` bytes, and load-time exit codes of bad snippets.
- `qa/tests/test_print.ahk` (9 asserts, backlog #4) — `Print` stdout contract,
  all probed against `2.1-alpha.30+Console` first:
  - line terminator is a **single LF** (no CR) even on Windows; `Print()` emits
    a lone LF; successive `Print`s concatenate.
  - **single-arg form bypasses Format**: `Print("{}")`→`{}`, `Print("{1}")`→`{1}`,
    literal braces survive.
  - 2+ args → first arg is a `Format` template: `{}` sequential, `{1}` reuse,
    `{2},{1}` reorder.
- `qa/tests/test_removed_syntax.ahk` (10 asserts, backlog #3) — load-time
  rejection of removed operators + survival of replacements:
  - removed `f?.()` → exit 12, "does not contain a recognized action".
  - removed `a?[i]` → exit 12, `Unexpected "?"`.
  - `!a ?? b` ambiguity → exit 12, `Unexpected "?"`.
  - replacements parse+run clean: `(f?)()` invokes when set (out `called`),
    `(g?)()` no-ops when unset and execution continues (out `after`).
- Full suite now **43 passed, exit 0** across 4 files.

**Next:** `.Ptr` subclass probes + DllCall output-arg `__Value` error
propagation (#2); crashlog/stderr-file directives as asserted subprocess tests
(#8); verify one `docs/alpha/*` doc against the binary (#5).

### Session 3 (2026-07-09) — `.Ptr` pointer-view subclass (backlog #2)
- Reverse-engineered the alpha.30 `.Ptr` mechanism (the StructFromPtr
  replacement) from `source/script_object.cpp` (`StructClass_Ptr` /
  `CreatePtrClass`, ~L1715–1796) + live probing, since it's undocumented:
  - `PT.Ptr` (property/getter) is an auto-generated **Class**; `PT.Ptr()` builds
    an instance that is just **8 bytes of pointer storage** (`.Size == 8`).
  - Overlay onto foreign memory by writing the target address into the view's
    own `.Ptr` storage: `NumPut("ptr", target, v.Ptr)`. Then `v.__Value`
    dereferences to a **live `PT` view**; writes through it commit to the
    pointed-to memory (verified via `NumGet` on the target).
- `qa/tests/test_struct_ptr.ahk` (12 asserts) pins that mechanism plus two
  alpha.30 fixes from `docs/alpha/v2.1-alpha.30.md`:
  - **`Struct.Ptr()` on the base class no longer crashes** — returns a
    `Struct.Ptr` instance.
  - **`view.__Value := unset` is now permitted** (no throw); read-back yields
    unset (default with `??`).
- **Probed-and-rejected (don't chase):** the DllCall output-arg `__Value`
  exception-propagation fix (alpha.30) could NOT be reproduced from AHK: a plain
  `"Ptr"` DllCall arg passes the struct's address and never triggers the
  `__Value` commit-back path, so no user-constructible snippet exercises it.
  Left unpinned rather than faking a green assert. Backlog #2's DllCall
  sub-item stays open.
- Full suite now **55 passed, exit 0** across 5 files.

**Next:** crashlog/stderr-file directives as asserted subprocess tests (#8);
verify one `docs/alpha/*` doc against the binary (#5); `Import`/module
search-path empirical tests (#7).

### Session 4 (2026-08-26) — WSL-launch robustness (interactive session)

(`qa/tests/test_crashlog.ahk` — 17 asserts, backlog #8 — landed in an
unlogged loop session between 3 and now.)

- `qa/run.ahk` + `qa/Harness.ahk`: **`A_ComSpec` is EMPTY when the engine is
  launched from WSL** (ComSpec isn't in the translated environment), so
  `RunWait` got a bare `/c …` and threw. Both now fall back to
  `A_WinDir "\System32\cmd.exe"`. (Children spawned *through* cmd.exe get
  ComSpec back — cmd sets it — which is why only the first hop broke.)
- Engine quirk found: **`FileRead` on a zero-byte file returns no value** on
  `2.1-alpha.30+Console` — a bare ternary over it dies with "No value was
  returned". Harness/runner now wrap the read in `try`. Backlog candidate:
  pin intended behavior with a qa test (upstream v2 documents "" for an
  empty file); check whether this is an alpha change or a fork regression.
- Suite green from WSL: **72 passed, 0 failed, 0 crashed** across 6 files.
