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
  `tests/test_powershell_cli.py` (committed in `7614a4f4`) now expect alpha.31.

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

### Session 7 (2026-09-11) — `bin/` engine rebuilt to alpha.31

- The only holder of the `bin/AutoHotkey64.exe` lock was this session's own
  `.mcp.json` server (`AutoHotkey64.exe mcp`, PID matched by command line),
  not `_.ahk`; stopped that one PID only.
- Built the canonical engine the CI way (CMake + Ninja, VS18 BuildTools,
  `-DAHK_OUTPUT_DIR=bin_review` in `build_console_review/`), which embeds the
  git revision. `--version`: `v2.1-alpha.31+Console revision=ef2047d49c32
  compiler=MSVC 195035719`. The msbuild `build_local.bat` route was tried
  first and produces `revision=unknown` (the vcxproj never defines
  `AHK_BUILD_REVISION`) — use the CMake route for `bin/`.
- Gate `tests/run_console_gate.py` 9/9 against `bin_review/` and again
  against the copied `bin/AutoHotkey64.exe`. Previous alpha.30 exe kept at
  `tests/tmp/AutoHotkey64.exe.bak` (gitignored scratch).


### Session 8 (2026-09-15) — `/Coverage=` LCOV, single-process test runner, CI shape

- **Engine:** `source/coverage.{h,cpp}` + `/Coverage=<path>` (`--coverage=`).
  Lines found = every `Line` in every module chain minus structural types
  (`BLOCK_BEGIN/END`, `ELSE`, `CATCH`, `FINALLY`, `CASE`, `END_MODULE`) and
  line 0; lines hit = counted next to `Debugger::PreExecLine` (ExecUntil top,
  `PerformLoopWhile` per iteration, `EvaluateLoopUntil`). Report rewritten
  open-write-flush-close from `Script::ExitApp`, the SEH filter and the console
  ctrl handler. `Script::LastModule()` accessor added (mLastModule is private).
  Verified on mingw harness and MSVC (`bin_review`): gate 11/11 green.
- **Runner:** `tests/Test.ahk` (`Test.Case`, `Assert.*`, `::error` annotations,
  JUnit via `AHK_TEST_JUNIT`) + `tests/run.ahk` (explicit `#Include` list with a
  completeness check) + `check/framework/json.test.ahk`. Registered in the gate.
- **qa:** `AHK_QA_COVERAGE_DIR` makes every child write its own `.lcov`;
  `tools/lcov_summary.py` merges → table, merged tracefile, shields badge JSON.
  Baseline for `qa/Assert.ahk` + `qa/Harness.ahk` + `tests/Test.ahk`: 64.2%.
- **CI:** `build.yml` gains `check` (vendored engine, `tools/check_all.py`,
  80/80 files parse after fixing one continuation-section bug in
  `debugger-tool/ahk-error-agent/include/error-to-stderr.ahk`), `test`
  (artifact engine, coverage, badge force-pushed to `badges` branch on alpha
  pushes) and tag-only published releases (`v*`) instead of per-push drafts.
- Not done: `bin/AutoHotkey64.exe` still lacks `/Coverage` (locked; rebuild via
  the `bin_review` route when convenient). No `#Coverage` directive by design.

### Session 9 (2026-09-16) — Inspect(), ProcessPipe, /Trace=json, native mcp check/run/test

- **Inspect(Value, Depth, MaxItems)** in `json.cpp` (shares JsonBuf/WriteQuoted):
  own values serialized, getters/setters/methods/typed fields listed by name
  (own + base chain, stopping at Object/Class/Any prototypes), Array items,
  Map and JSON.Object entries, Func signature, `truncated`/`circular` flags.
  Needed a new `Object::OwnFieldAt` (mFields is private). The BIF entry in
  `lib/functions.h` MUST be in sorted position: the table is binary-searched,
  and an out-of-order entry makes the function silently "undefined".
  REPL prints object results through it (depth 1, 50 items).
- **ProcessPipe** (`child_process.{h,cpp}` Win32 layer + `process_pipe.{h,cpp}`
  script class). Durability findings fixed during the adversarial pass:
  `EOF` is a CRT macro (property renamed `AtEOF`); 4 KB pipes + 5 ms polling
  made a 5 MB producer take 18 s (now 1 MB buffers, drain without sleeping);
  a plain WriteFile to stdin deadlocks against a child busy writing (now an
  overlapped named-pipe write that pumps stdout/stderr while pending, with
  `Send(text, timeout)` → TimeoutError). Verified: 2 MB each way concurrently,
  200 KB single line across chunk boundaries, 1 MB stderr flood during a
  stdout ReadLine, reentrant reads from a timer, 40 spawns without handle
  growth, kill-on-release. Child-side `File.AtEOF` is unreliable on pipes.
- **/Trace=json** — statement events with file/line/function/thread/text;
  JSON escaping done in-place with a bounded buffer.
- **mcp verb**: `check`, `run`, `test` tools spawn the engine via
  `RunChildCapture` (job-killed at `timeout_ms`), return exit code, both
  streams, and parsed schema-2 diagnostics. Probed with unicode/space paths,
  missing file (13 + diagnostic), bad cwd (-32603), 5 MB stdout, bad args.
- New qa suites: `test_inspect.ahk` (58), `test_processpipe.ahk`; Python:
  trace JSON cases, MCP tool cases.


### Session 10 (2026-09-22) — PR #31: console cleanup landed as five commits

- Committed the 2026-09-19 cleanup tree (engine, tests, debugger-tool, ci,
  docs) on `feat/console-cleanup-20260919` → PR #31 against `alpha`. Gate
  14/14 against the MSVC x64 (Ninja) build of the exact tree before pushing.
- **CI MSVC arm failed (RC2135)**: the manifest path reached rc.exe through
  `$<$<COMPILE_LANGUAGE:RC>:AHK_MANIFEST_PATH=…>`, which the Visual Studio
  generator (`-A x64`/`-A Win32`) evaluates to nothing, so rc.exe fell back to
  the MSBuild-only `temp\AutoHotkey.exe.manifest`. Local Ninja+MSVC builds
  never showed it, and a stale `temp/` manifest masked it on this machine.
  Fix: define `AHK_MANIFEST_PATH` target-wide (forward slashes, C++ ignores
  it) and add `OBJECT_DEPENDS` on the generated manifest. Reproduced with
  `-G "Visual Studio 18 2026" -A x64` (BuildTools-bundled CMake; the system
  CMake 4.0.3 predates that generator) with `temp/` renamed away: build
  green, `generated/AutoHotkey.exe.manifest` embedded.
- Local VS-generator gotcha: the WSL-inherited `%PATH%` breaks tool lookup
  inside MSBuild (`cscript.exe` "not recognized", ml64 exit 1). Use a minimal
  `set PATH=C:\WINDOWS\system32;C:\WINDOWS;C:\Program Files\Git\cmd` before
  `vcvarsall`.
- Copilot review on #31, all four applied: badge push moved to its own
  `badge` job so the `test` job token is read-only; `Coverage::AppendUtf8`
  converts by explicit length (no terminator written past `size()`);
  `JsonObject::~JsonObject` detaches storage before releasing values, like
  `ClearItems`; README no longer claims `/Headless` keeps script `MsgBox`
  dialogs from blocking.
- Home.vue was a 0-byte file in the working tree; restored from HEAD.
- #16 closed as superseded by the workflow in #31. #17 rebased onto the #31
  branch (its base until #31 merges): `DBGpClient` keeps the stdio transport
  model plus #31's lifecycle guarantees; the shared `DBGpFramer` gained an
  opt-in `divertRaw` mode so raw `Print()` bytes on a stdio pipe are captured
  instead of duplicating framing; `fake-ahk.sh` committed executable (the
  launcher tests failed with EACCES on Linux without it). Client suites 4/4,
  23/23 (+2 skipped), 3/3; CI green on both branches.
- Privacy sweep: 15 tracked files still carried the home-directory path or
  the old repo id (hooks, `.mcp.json`, test_repl.sh, examples, plan docs).
  Scripts now derive locations from their own path with `AHK_*` overrides;
  `.mcp.json` uses `./bin/AutoHotkey64.exe` (verified to answer `initialize`
  from the repo root); `.claude/settings.local.json` untracked and ignored.

### Session 11 (2026-10-06) — Claude Code agent setup audit and repair
- Audited the agent setup (hooks, SessionStart context, `.mcp.json`, local
  settings, `uia` skill, CLAUDE.md, `.vscode/`) with parallel fact-gatherers,
  per-area auditors and adversarial verifiers: 89 findings, all confirmed.
- Root causes: every hook parsed JSON with `python3`, which is the Microsoft
  Store stub on this host, so the post-edit syntax gate never ran; Git Bash
  rewrites a bare `/Diag=json` into a path, so even a working parser checked
  `C:\Program Files\Git\Diag=json` (exit 13). The SessionStart context taught
  alpha.30, a WSL path, hidden or legacy `ahk` tools, and "`/Headless`
  suppresses all dialogs". `.mcp.json` launched the stale GUI build
  `bin/AutoHotkey64.exe` (ef2047d4, pre-a551fcd4): 5 MCP tools, no
  check/run/test, no Inspect/ProcessPipe//Coverage.
- Hooks rebuilt on the contract read from the installed Claude Code 2.1.287
  binary (PostToolUse carries `tool_response`; exit 2 + stderr reaches
  Claude; context goes in `hookSpecificOutput`). They are bash-only (no
  python/jq), ASCII, and resolve the engine as `AHK_CUSTOM_EXE`, then
  `bin/AutoHotkey64Console.exe`, then `bin/AutoHotkey64.exe`. An exe without
  the fork's marker text is refused: stock AutoHotkey pops modal #Warn
  dialogs, because upstream `/ErrorStdOut` does not cover warnings.
  Registration moved to the committed `.claude/settings.json`;
  `.mcp.json` now starts `./bin/AutoHotkey64Console.exe mcp` (8 tools).
- `bash .claude/hooks/test-hooks.sh`: 147 passed, 0 failed, 0 skipped.
  SessionStart: 35 ASCII lines in ~0.4 s.
- Found outside this repo, not changed: the user-wide `ahk` server's
  `AHK_PATH` is stock alpha.32, so `AHK_Eval` and `uia_*` fail; its
  `capture_error` can never capture (`queueError` has no live caller);
  `--coverage=` into a missing directory writes nothing and exits 0. No
  build toolchain is installed on this machine, so no task was build-tested.

### Session 12 (2026-10-07) — DBGp guidance synced with the ahk-mcp capture fix
- The ahk-mcp capture fix makes the `ahk` server's `capture_error` and
  `evaluate` work; a running server loads it only after a restart. It is on
  ahk-mcp's local branch `fix/dbgp-capture-error` (not pushed or merged;
  `dist/` rebuilt), so a checkout elsewhere gets `master`, which lacks it.
  Driven in-process
  from that `dist/` against `bin/AutoHotkey64Console.exe` (43776299d43a-dirty)
  with `/Debug=localhost:9437 /Headless`:
  - `capture_error` before `start`: `not_listening` in 1 ms. `start` with
    `port:9437` bound 9437 (with no `port` it moves past the held 9000).
  - Without `run`, `capture_error` started a script paused at line 1 and
    returned its ZeroDivisionError (line 5) in 2 ms; the engine exited 10. A
    second call after that exit timed out (2016 ms): the run's error was
    already returned, so the call waits for the next launch.
  - A step that reached a throw answered `break (error: ...)`. `capture_error`
    returned the queued error in 2 ms and the script was still paused 1.5 s
    later (`engine_state` `break`) until `run` (exit 10).
  - At a breakpoint, `evaluate` read `a`, `obj.name`, `obj.list[2]`, `m["k"]`
    and `obj.list.Length` in 0-1 ms and rejected `a + b` at once; a
    `breakpoint_set` `condition` was rejected at once (DBGp error 3). ahk-mcp
    `master`'s client (bundled with esbuild) failed both with
    `Command timeout` after 10020 and 10000 ms; `context_get` worked.
  - `throw ValueError("named what", "Inner", "some extra")` inside `Inner()`:
    `line` 5 (`Error.Line`), `stack_trace[0]` line 9, captured once
    (`list_errors` count 0 after exit 10). A thrown string has `extra` but
    no `what` or `ahk_stack`.
  - A second script (`#SingleInstance Off`) launched while a `Sleep(5000)`
    script was attached: `capture_error` timed out with
    `waiting_connections:1` and a `note`; the next call returned the first
    script's `session_ended` `{stopped, ok}` with `waiting_connections:1`,
    and the next the second script's ValueError (session 2). A relaunch of
    the same script does not wait like this: see Session 13.
  - An error queued after `run` with nobody waiting came back first after a
    relaunch, which was started at once (exit 10 within 1.5 s). A script that
    ended while nobody waited was reported once, as `session_ended` after the
    0.5 s grace (501 ms); the call after that timed out.
- Engine bug (this fork only): the uncaught-error report (stderr text and
  `--diag=json`) names the line the throw ran, not `Error.Line`, when they
  differ. `source/error.cpp:1797` passes `TokenToString(t)` to `GetLine` as the
  file name, and `t` last held `Extra` (else `Message`), so the lookup fails
  and the throw line stays; it should pass `file`. Repro: the same throw with
  an OnError callback added above it (prints `Error.Line`, returns 0) printed
  `Error.Line=6`, and the report said `what_line.ahk (10) : ==> named what`
  (`"line":10` with `--diag=json`), exit 10. Upstream
  v2.1-alpha.31 and .32 look the line up by file index; the call came with
  d8217d1a (`_ScriptGetLines`, the linecontext merge). By reading only: when
  neither `Message` nor `Extra` is an own property, `t` is read uninitialized.
- `JSON.Array` keyword tags, run on the same engine: `Push`, `InsertAt`,
  `RemoveAt`, `Pop`, `Length` and `Clone` keep each remaining item's tag
  (`[true,null,false,1]` grown to 6 gave `[true,null,false,1,null,null]`), and
  assigning an element drops only its tag (`h[2] := 0` gave
  `[true,0,false,1]`). CLAUDE.md said a length change drops all tags.
- CLAUDE.md (DBGp Protocol, the `ahk` bullet, the JSON bullet), the three DBGp
  hooks, `test-hooks.sh` and the hooks README now say this. `capture_error`
  resumes a paused script only when nothing is queued; its timeout guidance
  names the "error already returned" cause, the port `start` or `status`
  reports, and adds notes for `waiting_connections` and
  `unconfirmed_reports`. `evaluate` and conditional breakpoints are described
  per build, with PostToolUse guidance when an older build times out.
- Corrections after review (same engine and `dist/`; the DBGp run on port 9447):
  - The docs said `/Headless` was needed or an uncaught error would open a
    modal error box. Not on the console engine: without `/Headless` or a
    debugger a divide by zero printed its report on stderr and exited 10 in
    77 ms (`SetErrorStdOut(nullptr)` at console start, `error.cpp:1165`). The
    real modal prompt is the debugger's: with no listener on the port,
    `Debugger.cpp:2725`/`2751` call `FatalError`, which shows a "Failed to
    connect to an active debugger client. Continue running the script
    without the debugger?" MessageBox, with or without `/Headless` (only
    `/Debug=stdio` prints it instead); a connection lost mid-run shows the
    same kind of box. `/Headless` under `/Debug` only turns prompts such as
    `#SingleInstance` into stderr text (a refused relaunch then exits 64;
    see Session 13). Read from source, not run, to keep a dialog off the
    desktop.
  - A `run` that answered `Status: stopped` (clean script, exit 0) made the
    next `capture_error` wait out its timeout (3001 ms, `reason:"timeout"`);
    without that `run`, `capture_error` returned `session_ended`
    `{stopped, ok}` in 1 ms. The docs said only "returns session_ended when
    the script ends first".
  - The hooks no longer name the branch; they test for `error_capture` in
    `status` and point at CLAUDE.md. The SessionStart DBGp section is three
    lines (896 bytes, from 2103), since the debug toolset is hidden by default
    and the DBGp hooks carry the details; `test-hooks.sh` caps it.
- `bash .claude/hooks/test-hooks.sh`: 170 passed, 0 failed, 0 skipped. Seven
  mutations that restore an old claim (on a scratch copy of the hooks) each
  fail 1 to 11 cases. SessionStart: 34 ASCII lines, 5231 bytes.

### Session 13 (2026-10-07) — relaunch semantics, BIF corrections, open engine bugs
- A relaunch does not wait behind an attached run of the same script.
  `#SingleInstance` (default `Prompt`, `globaldata.cpp:78`) is checked before
  the debugger connects (`AutoHotkey.cpp:234`, connect at `:637`); under
  `/Headless` it prints `Another instance is already running. Use
  #SingleInstance Force or /force.` and exits 64 (`AutoHotkey.cpp:556`).
  Driven from ahk-mcp's `dist/` (local branch `fix/dbgp-capture-error`)
  against `bin/AutoHotkey64Console.exe` (43776299d43a-dirty) with
  `/Debug=localhost:9611 /Headless` (9612 for the waiting cases):
  - The same script relaunched while its first run was paused at a throw
    after a step, or still running: exit 64 with that text, never connected,
    `status` `waiting_connections:0`. A `capture_error` sent then returned
    the old run's `session_ended` `{stopped, ok}` when it ended.
  - `run` on the paused run (it exited 10), `clear_errors`, then the same
    relaunch: it connected as session 2 and `capture_error` returned its
    ValueError.
  - A different script, or a second copy of a `#SingleInstance Off` script,
    launched while a `Sleep(6000)` script ran: `status` and a timeout showed
    `waiting_connections:1` with the `note`; the next call returned the first
    script's `session_ended` with `waiting_connections:1`, the next the
    second's.
  - `clear_errors` while a script ran, then the script ended: the next
    `capture_error` still returned `session_ended` (509 ms) and the one after
    timed out. A script that ended unobserved, then `clear_errors`:
    `capture_error` timed out (1521 ms). `clear_errors` drops queued errors
    and a remembered end, not the end of a run still going.
- CLAUDE.md (DBGp Protocol), the three DBGp hooks and the hooks README now say
  this: let the old run exit (`run`, or `stop` then `start`) before a
  relaunch; the timeout guidance names the refused relaunch;
  `waiting_connections` means another script (or a `#SingleInstance Off`
  copy) is waiting; `clear_errors` acts on a run only after it ended. The
  ahk-mcp fix is described as a local branch (not pushed or merged).
- CLAUDE.md BIF bullets, each rechecked on the same engine:
  - An `Eval` `SyntaxError` has own `Message`, `File` `_Eval`, `Line` 0,
    `Column` 0, and `What`/`Extra`/`Stack` throw `PropertyError`;
    `SyntaxError("m", "w", "ex")` has `What`, `Extra`, `File`, `Line`,
    `Stack` and no `Column`.
  - `JSON.Array` tags: `Push`, `InsertAt`, `RemoveAt`, `Pop`, `Length`,
    `Capacity` and `Clone` keep the remaining tags, new items have none
    (`Push(true)` emits `1`), and assigning (even `h[1] := h[1]`) or `Delete`
    drops that element's keyword.
  - `Check` on a source with a VarUnset warning on line 1 and a `Goto` to a
    missing label on line 3 gives `Ok=0` and one diagnostic, the line-1
    warning; a warning-only source gives `Ok=1` and no diagnostics; a
    nonzero exit with no record gets a synthetic `Check:` diagnostic
    (`console_check.cpp:264`, from source).
- CLAUDE.md Open items now lists the engine bugs found this session, one line
  each with its source location; none is fixed.
- `test-hooks.sh`: the SessionStart DBGp-section cap counted the engine path,
  printed twice, so the copied-engine case failed with a long `TMPDIR` (1250
  bytes). It now measures the fixed text only (841 bytes, cap 1000). New
  assertions cover the refused relaunch and `clear_errors` wording; restoring
  the old `msg_fixed` and PreToolUse text on a scratch copy fails 14 cases.
- `tests/crashlog_check.ahk`, `test_ahkmon.ahk` and `test_check_bif.ahk` usage
  comments name `bin\AutoHotkey64Console.exe`. All three pass `check`;
  `test_check_bif.ahk` passes on the console engine, and `crashlog_check.ahk`
  exits 0, 14 and 64 as its comment says.
- `bash .claude/hooks/test-hooks.sh`: 170 passed, 0 failed, 0 skipped with the
  default `TMPDIR` and with a long scratch `TMPDIR`. SessionStart: 34 ASCII
  lines, 5231 bytes, 0.3 s.

### Session 14 (2026-10-08) — alpha.33 re-verification
(The 2026-10-08 workflow asked for "Session 13"; that number is already the
2026-10-07 entry above, so this one is 14.)
- Engine: `bin/AutoHotkey64Console.exe` and `bin/AutoHotkey64.exe` both report
  `2.1-alpha.33+Console`, revision `f7712ec15171` (MSVC, CI branch
  `ci/alpha33`) with `inspect`, `processPipe` and `coverage`;
  `bin/*.alpha31.bak` hold the previous alpha.31 engines. A session `ahk-mcp`
  server started before the rebuild still reported `2.1-alpha.31+Console` in
  `server_status`.
- Totals on alpha.33: qa 764 passed, 0 failed, 0 crashed across 13 files
  (762 + 2 new pins); console gate 14/14 suites; `test-hooks.sh` 170 passed,
  0 failed, 0 skipped; `check fork.d.ahk` CHECK PASS (exit 0, the usual
  `=> void` warnings); every tracked `examples/` file passes `check` (47/47).
  `tools/check_all.py` gives 227/229 and exit 1: both failures are stale
  copies under the orphaned `.kilo/worktrees/vanilla-toad` worktree, none in
  the repo itself.
- `qa/tests/test_alpha31.ahk` section 11: upstream alpha.32 `40a82a67` makes
  `a := src` (src a virtual reference) copy `__Value`. The note now says so and
  two asserts pin `Integer` 42; the alpha.31 backup engine fails exactly those
  two (`expected: Integer actual: QaCell`).
- Docs: README badge, intro and Eval line, updates.md base version, Eval
  line and crash-log sample now name alpha.33; `fork.d.ahk` `@since` for
  `Inspect` and `ProcessPipe` restored to `2.1-alpha.31+Console` (both came in
  `a551fcd4`, which reported alpha.31). The v2.1 no-value mode is described as
  coming from a top-level `#Requires` in the module's own file (upstream
  `47eabd41`, `08beacf1`): probes give v2.0 mode for one in an `#Include` or a
  function, v2.1 for one at the top level or in an included file that declares
  its own `#Module`. CLAUDE.md drops the `launch_script` advice (legacy,
  unregistered adapter) for `mcp__ahk-mcp__run`/`test` plus stdin forms checked
  in both shells (`'Print("hi")' | & $engine *`; Git Bash needs `'*'`, and the
  old `/ErrorStdOut *` line exits 12 there). `docs/AHK_V2_WORKFLOW_TECHNICAL.md`
  sections 6-8, `docs/VSCODE_SETUP.md`, and the function-named references in
  `docs/AHK_CONSOLE_STDOUT_PROCESS.md` follow suit.
- Module init: every module runs at startup in reverse creation order
  (`script.cpp:1042`); a first reference only runs one early (`c0ab7108`,
  `var.cpp:1444`). Probes: `NeverUsed` body, then `Used`, then `__Main`;
  `Y body start`, `X body ran`, `Y reads XVal=1`, `__Main`. Upstream design,
  not a fork regression; `docs/alpha/v2.1-alpha.21.md` no longer calls it lazy.
- CLAUDE.md open items: every engine-bug entry rechecked on alpha.33 with
  current `file:line` (error.cpp moved +6: `:1784`, `:1803`); none fixed. New
  entries: the `source_outline`/`workspace_symbols` regex scan
  (`mcp_server.cpp:930`), `--help` omitting `/Debug` and the `--` aliases,
  and follow-ups outside this pass's scope (`test_alpha33.ahk`, hard-coded
  version pins, `check_all` walking `.kilo/`, upstream `.github` files,
  `.vscode/launch.json:54`).

### Session 15 (2026-10-08) — engine fixes via CI
- Five commits on `fix/engine-bugs`, merged into
  `feat/console-cleanup-20260919` at `4e9349b5`. No local C++ toolchain, so CI
  was the first compile of each:
  - `7b1a23b6` json: `JSON()` and subclass calls throw `TypeError`, the generic
    `(Object.Call)` paths `ValueError` "Invalid base.", and
    `JSON.True`/`False`/`Null` are getter-only. Test
    `qa/tests/test_json_class.ahk`.
  - `76973889` debugger: a lost DBGp connection is reported on stderr instead
    of the Yes/No prompt. Test `tests/test_debugger_fatal.py`, added to the
    console gate.
  - `ec684fd0` coverage: a missing report directory is created and a failed
    write prints one stderr line (a warning record under `/Diag=json`); the
    exit code is unchanged. Test `qa/tests/test_coverage_missing_dir.ahk`
    rewritten.
  - `47bc3fcb` check: `Check()` builds its diagnostic from the first error
    record. Test `qa/tests/test_check_severity.ahk`.
  - `f14d7427` debugger: no Abort/Retry/Ignore box on a refused connect; the
    notice names the client and goes through `PrintErrorStdOut`.
    `test_debugger_fatal.py` exits 77 without starting an engine that lacks
    the notice text; the gate counts that as a skip, or a failure under
    `CI=true`.
- CI (workflow_dispatch): run 37801628398 (head `47bc3fcb`) and run
  37807040408 (head `f14d7427`) both succeeded: build (x64), build (Win32),
  build-mingw, debugger-clients and test green, badge and release skipped,
  console gate 15/15 on all three compilers.
- `bin/` now holds run 37807040408's artifacts: the four `bin/` exes match the
  run's sha256 files, and `AutoHotkey64Console.exe --version` reports revision
  `f14d74270a2b`. The previous `f7712ec15171` engines and capabilities files
  are `bin/*.alpha33.bak`.
- Local results on the new engines (the lead's run, on the merge `4e9349b5`):
  console gate 15/15 on the x64 and x86 Console exes and `test-hooks.sh` 170
  passed. After this docs pass, the same engine gives qa 862 passed, 0 failed,
  0 crashed across 15 files and `test-hooks.sh` 171 passed (the merge's
  `test_alpha31.ahk` pins and a new hooks README check).
- Docs pass, rechecked on `bin/AutoHotkey64Console.exe` (`f14d74270a2b`):
  `test_json_class` 48, `test_coverage_missing_dir` 41 and
  `test_check_severity` 22 passed, `test_debugger_fatal.py` 3/3 OK, and
  `check fork.d.ahk` passes. Probes on ports bound and then closed (never
  9000) gave `Debugger error: Could not connect to localhost:PORT; continuing
  without the debugger.` with no flags, `/Headless` and `/ErrorStdOut=UTF-16`,
  byte-identical in `/StdErrFile`; an RST after the init packet gave
  `Connection to localhost:PORT lost; ...`, stdin EOF under `/Debug=stdio`
  `Connection to stdio lost; ...`, and `--diag=json` one warning record
  (`what` "Debugger", `extra` the client); `detach` printed nothing, and every
  run printed its output and exited 0. Construction-only probes show `File`,
  `Func`, `BoundFunc`, `Closure`, `Enumerator` and `RegExMatchInfo` still
  build a plain Object on their native prototype from `X()` and
  `(Object.Call)(X)` (no method called).
- Docs updated: CLAUDE.md (Running and testing, `Check()` and `JSON`
  bullets, DBGp section, open items: five fixed, new ones added, the
  debugger-prompt trade-off recorded), `fork.d.ahk`, `updates.md` §17 and new
  §22, README, `docs/TREE_SITTER.md`, `docs/AHK_V2_WORKFLOW_TECHNICAL.md`,
  `tests/run.ahk`, the coverage test header, `.vscode/launch.json`,
  `examples/alpha21/README.md` and the example 05 comments (a Print copy runs
  `NeverUsed`, `Formatter`, `Logger`, then `__Main`). The coverage note in
  Session 11 and the debugger-dialog note in Session 12 describe engines
  before these fixes.
- Still open (CLAUDE.md): two notices when the init packet cannot be sent;
  an out-of-memory `ReceiveCommand` reported as a lost connection; the
  hand-copied JSON escapers in `Debugger.cpp` and `coverage.cpp`; the latent
  factory bug in `File`/`Func`/`RegExMatchInfo` and kin; a test guard that
  cannot see a reverted connect break; `Check()` field extraction reading past
  its record; and the earlier engine items (`&Module.Var`, JSON `MaxDepth`
  and `AllowTopLevelScalar` positions, `WritePropertyData`, the `error.cpp`
  `GetLine` and uninitialized-token pair, report truncation, crash-log
  `Stack`, Eval's `SyntaxError` and scope, `--help`, the outline regex, a qa
  pin for module order, zero-byte `FileRead`). By design, no build shows a
  debugger prompt now, because `mErrorStdOut` defaults to true (a GUI session
  continues silently).

### Session 16 (2026-10-08) — test runs on a hidden desktop

- `tools/run_hidden.py` runs a command on a hidden Win32 desktop
  (`CreateDesktop`, `STARTUPINFO.lpDesktop`) that every child inherits, in a
  kill-on-close job, sharing the caller's stdio and exit code. It reports each
  visible, non-minimized window its processes open, with the window's text.
  Verified with a probe: `MsgBox(..., "T3")` opened there (reported, not shown)
  and returned `Timeout`; a blocking `MsgBox` was killed at `--timeout` (exit
  124); `SendInput` from there returns 0 with error 5. AutoHotkey minimizes its
  hidden main window when there is no foreground window (`source/script.cpp:641`),
  which is always the case on that desktop, so minimized windows are not reported.
- `BitBlt` from the screen fails there (error 6), so `test_alpha31.ahk`'s five
  `PixelSearch` output pins crashed the file. They now run only when
  `ScreenCopyError()` can make the same 1x1 copy, and print a `SKIP` line
  otherwise; `qa/run.ahk` echoes `SKIP` lines as it does `FAIL` lines.
- Results under `run_hidden.py`: console gate 15/15 on the x64 and x86 Console
  exes (qa 857 passed, 0 failed, 0 crashed, plus the `SKIP` line), `check_all`
  103/103, native conformance 60/60, `test-hooks.sh` 171 passed. Run directly,
  `test_alpha31.ahk` still gives 61 passed (the pins ran).
