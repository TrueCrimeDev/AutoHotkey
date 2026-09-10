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
  build, stdout works headless, exit codes propagate. Source is at
  `2.1-alpha.31+Console`; `bin\` is still the alpha.30 build until rebuilt
  (`bin_harness\AutoHotkey64Harness.exe` carries alpha.31).
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

### Session 5 (2026-09-08) — upstream v2.1-alpha.31 merge

- Merged upstream tag `v2.1-alpha.31` into `alpha` as `c73ae823` (23 upstream
  commits, range `34b17011..v2.1-alpha.31`, incl. the v2.0.27 merge). Single
  conflict in `source/script.cpp`: the fork had hoisted a `class_export_type`
  declaration above a `goto`; upstream removed the `export` parsing that fed
  it, so both the declaration and its assignment were dropped. Version bump in
  `cec42523` (`source/ahkversion.h`, `build_local.bat`); the engine now
  identifies as `2.1-alpha.31+Console` (`A_AhkVersion` probed).
- Verified with a mingw harness build to `bin_harness/AutoHotkey64Harness.exe`
  and `qa\run.ahk` on it: **615 passed, 29 failed, 0 crashed across 10 files**.
  All 29 failures are `test_json_regressions.ahk`, which pins JSON code parked
  in the user's stash (pre-existing, not merge-related); every committed suite
  is green. `tests/test_console_cli.py::test_numeric_file_version_matches_alpha31`
  passes against the harness (file version `2.1.0.31`).
- `bin/AutoHotkey64.exe` is **still the alpha.30 build** — locked by the
  running app, not rebuilt; only `bin_harness/` carries alpha.31.
- Stale `export` examples (upstream removed the keyword; names defined inside a
  `#Module` are exported implicitly, `#Import Export Name` re-exports an
  import): `examples/alpha21/02_module_basics.ahk`, `04_import_selective.ahk`,
  `05_lazy_module_init.ahk`, `06_module_file_scoping.ahk` (+ its
  `lib/StringUtils.ahk` / `lib/Collections.ahk`) exit 12 — `export Foo(x)` with
  a `{` block on the next line now parses as a call to `export`, so the body's
  `return` is "outside a function"; `examples/alpha22/05_export_function_call.ahk`
  loads with a warning and exits 10 ("This global variable has not been assigned
  a value. Specifically: export"); it ran clean (exit 0) on the alpha.30
  `bin/` engine. Logged as a CLAUDE.md open item; example files untouched.
- New this session (sibling agents): `docs/alpha/v2.1-alpha.31.md` (with a
  **Next** link added to `docs/alpha/v2.1-alpha.30.md` and its "latest release"
  blurb removed), `examples/Alpha31_Example.ahk`, `qa/tests/test_alpha31.ahk`
  (59 asserts, counted in the suite total above).
- Identity bump alpha.30 → alpha.31 in README.md, CLAUDE.md, updates.md,
  qa/README.md, debugger-tool/mcp-ahk/README.md, its `conformance_native.py`,
  and `tests/test_console_cli.py`. Historical "verified on alpha.30" statements,
  `@since` tags, `docs/alpha/*`, and existing `#Requires v2.1-alpha.30` lines
  left as-is (still satisfied by alpha.31).
- Review pass: the CLAUDE.md engine bullet and the mcp-ahk README requirement
  no longer claim `bin/` is alpha.31 (it is alpha.30 until rebuilt);
  updates.md `Eval` blurb and crash-log sample bumped alpha.29 → alpha.31
  (log line shape verified on the harness: `ahk=2.1-alpha.31+Console`).
- After restoring the parked console-review work on top of the five commits:
  harness rebuilt (`revision=d466022e-dirty`), full gate
  `tests/run_console_gate.py` **9/9 suites**, `qa: 645 passed, 0 failed,
  0 crashed across 10 file(s)` (`test_json_regressions.ahk` green again once
  its JSON code was back). `tests/test_console_cli.py` and
  `tests/test_powershell_cli.py` (both still uncommitted) now expect alpha.31.

### Session 6 (2026-09-10) — stale example repair for alpha.31

- Struct type strings: 14 files under `examples/` switched from `i32`/`u8`/…
  to the primitive classes (`Int32`, `UInt8`, `UInt16`, `UInt32`, `Int64`,
  `Float32`, `Float64`, `IntPtr`). Probed on the harness: **no `UInt64` or
  `UIntPtr` class exists**, so `u64` → `Int64` (bit-masking code in
  `alpha_tricks.ahk` still works under arithmetic shift) and `uptr` → `IntPtr`.
  `v2.1-alpha-features.ahk` also lost its bare `reserved: 32` field
  (alpha.30 removed untyped sizes) → `UInt8[32]`.
- `examples/struct_at_showcase.ahk` had a clobbered header since the alpha.29
  checkpoint (`afeedbeb`): the `Struct POINT` definition was missing and a
  stray `}` remained. Restored.
- `export` removal: keyword stripped from the alpha.21 module examples and
  libs; `05_export_function_call.ahk` rewritten to explain the alpha.22 →
  alpha.31 history. The examples had also used `#Import {X} from M` and bare
  `#Import "file.ahk"` expecting names to bind — both fail on this engine
  ("Invalid import" / names unset). Rewritten as `#Import M {X}`,
  `#Import M {X as Y}`, `#Import "file.ahk" {*}`,
  `#Import "file.ahk:Mod" {Name}`. `lib/StringUtils.ahk` dropped its
  `#Module` line so it is a true default-module file.
- Struct prototypes are type `Prototype` on alpha.31 and do not inherit
  `Object` methods (`HasOwnProp`, `GetOwnPropDesc`…). `Alpha24_Example.ahk`
  now borrows `Object.Prototype.GetOwnPropDesc.Call(...)`; the descriptor's
  `Type` is the class object, printed via `.Prototype.__Class`.
- `Map.Get(key, unset)` throws for a missing key (explicit unset = omitted);
  `v2.1-alpha-features.ahk` now resolves `default ?? 0` first.
- Observed: a `#Module` nothing imports **does run**, before `__Main`, on
  alpha.31 — contradicts the alpha.21 lazy-init note. Logged as an open item.
- Observed: `/Headless` does not suppress `MsgBox`; headless runs of the
  MsgBox examples blocked on real dialogs. Verification switched to scratch
  copies with `MsgBox` → `Print`. Logged as an open item.
- Result: `check` passes for every file under `examples/` (0 failures) on the
  alpha.31 harness; all touched examples run to exit 0 (GUI-only ones via
  `check`).
