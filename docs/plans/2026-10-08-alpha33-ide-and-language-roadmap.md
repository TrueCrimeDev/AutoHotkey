# Roadmap: VS Code observation and modern language features on 2.1-alpha.33+Console

Date: 2026-10-08. Baseline: `feat/console-cleanup-20260919` at upstream `v2.1-alpha.33`
plus alpha commits through `47eabd41`. Engine identifies as `2.1-alpha.33+Console`.

This plan has three tracks. Track A makes a running or crashing script easier to see
from VS Code. Track B adds language features. Track C is the engine groundwork and
bug fixes that the other two depend on. Milestones at the end sequence them.

## Ground rules

- **Keep upstream merges cheap.** Lexikos still ships an alpha every few weeks. A
  feature is a new BIF, class, directive, CLI verb or a parse-time desugaring that
  lands in a self-contained file. Nothing rewrites expression evaluation or the
  object model. Every merge conflict so far has been in `script_object.*`; keep new
  code out of there.
- **Two waves of syntax.** thqby's language server and the bundled tree-sitter
  grammar parse the source themselves. New syntax shows as red squiggles in VS Code
  until both learn it. Wave 1 adds only features that are already syntactically
  valid AHK (functions, classes, directives). Wave 2 adds real syntax, shipped
  together with a patched `vscode-autohotkey2-lsp` and grammar update, so the IDE
  never lags the engine.
- **Definition of done for every feature.** A `qa/` or `tests/` suite in the Console
  gate; a declaration in `fork.d.ahk`; a `features` flag in `--capabilities`; a
  section in `docs/alpha/` or `updates.md`; and a line in the harness rule
  `.claude/rules/ahk-fork-features.md`. A feature that an agent cannot discover
  from `--capabilities` does not exist.

## What exists today

| Area | Already in the fork |
| --- | --- |
| CLI verbs | `run`, `check`, `test`, `repl`, `mcp`; `/Headless`, `/Diag=json`, `/Trace[=json]`, `/Coverage=` (LCOV), `/CrashLog=`, `/StdErrFile=`, `/Debug[=stdio]`, `--capabilities` |
| BIFs | `Print`, `Eval`, `Check`, `Inspect`, `TSParse`, `ProcessPipe`, `JSON`, `SyntaxError`, `_ScriptGetLines` |
| Exit codes | 0, 10 runtime, 11 critical, 12 parse, 13 check, 14 test, 64 usage, 130 interrupted |
| Agent surface | native MCP over stdio (`ast_outline`, `source_outline`, `workspace_symbols`, `get_source_context`, `check`, `run`, `test`, `server_status`) |
| Observation | AHKMON text snapshot over `WM_COPYDATA`; **Observatory** (AHKOBS v1 JSON snapshot: overview, lines, hotkeys, variables, keys, timers) with a native viewer and the `ahk-observatory` VS Code extension 0.9 (watch list, freeze on change, execution markers, source navigation, export). Observatory is still in the `Agent/Observatory/integration-alpha33` worktree, not on the feature branch. |
| Debugger | upstream DBGp (`Debugger.cpp`): run/step/break, stack, context, property get/set, breakpoints without conditions, no `eval` |

Fixed this week on `fix/engine-bugs` (merged at `4e9349b5`): the modal box on a
failed or lost DBGp connection, `Check()` picking a warning over the error,
`--coverage=` into a missing directory, and `JSON()` being constructible. Still
open, from the fork `CLAUDE.md` bug list: DBGp `WritePropertyData` corrupts long
values and miscounts surrogate pairs, `breakpoint_set` rejects conditions, there
is no DBGp `eval` (so the legacy MCP server's `evaluate` tool fails with error 4),
the error report names the throw line instead of `Error.Line` and crashes on
`throw {File, Line}`, the headless JSON error report is silently truncated, an
`Eval` `SyntaxError` lacks `What`/`Extra`/`Stack`, and `&Module.Var` crashes at
exit (missing `AddRef` in `script_module.cpp:42`, upstream's bug).

VS Code side: the fork's `.vscode/extensions.json` recommends
`zero-plusplus.vscode-autohotkey-debug` and its `launch.json` carries a working
DBGp config for the console engine, but the extension is not installed on this
machine, so the `autohotkey` debugger type has no provider and F5 does nothing in
either workspace. The harness `tasks.json` still points at `C:\Users\uphol\...`.
The language server's `InterpreterPath` is the fork engine; `fork.d.ahk` is loaded
only where a script has a `;@include` line for it, so most files get no
completions or hover for fork BIFs. No LSP or DAP has been built in this repo; a
DAP adapter was considered and dropped in `docs/plans/2026-06-09-stdio-supervisor.md`
because zero-plusplus covers IDE use.

## Track A: observation from VS Code

### A1. DBGp completion: `eval`, conditional breakpoints, logpoints, data breakpoints

Make the existing protocol good enough that any DBGp client (thqby, zero-plusplus,
the MCP server) gets a modern debugging experience.

- `eval` command backed by `ConsoleEval::Evaluate` in the paused thread's scope.
  Returns a `property` element like `property_get`, so clients need no new parsing.
  This also unblocks the MCP server's `evaluate` tool (`updates.md` §14 lists it).
- `breakpoint_set -c <expr>`: store the expression, evaluate it with the same
  evaluator when the line is reached, stop only when truthy. Evaluation errors
  count as true and are reported once on the debugger's stderr stream.
- Logpoints: DBGp has no logpoint, so accept a `-- <base64 template>` body on a
  `line` breakpoint with `-t log`. When hit, format `{expr}` placeholders through
  the evaluator, emit a `stream type="stdout"` notification, do not stop.
- Data breakpoints: `breakpoint_set -t watch -- <name>` captures the variable's
  value; each line boundary compares while any watch breakpoint exists. Cost is
  only paid in a debug session with a watch set.

Files: `source/Debugger.cpp` (command table at line 47, `breakpoint_set` near 771,
`PreExecLine`), `source/console_eval.cpp`. Tests: a `tests/test_dbgp_eval.py`
stdio session that evaluates an expression, sets a conditional breakpoint and a
logpoint, and reads a 100 KB string back intact. Effort: about one week. Risk to
upstream merges: low; `Debugger.cpp` changes are additive.

Why engine-side when zero-plusplus already fakes conditions and logpoints in the
adapter: every other client (the legacy MCP server, `ahk-error-agent`, a future
native DAP, the "break, eval, run" pattern in the stdio-supervisor plan) gets them
for free, and an expression evaluated by the engine sees the same scope rules as
the script instead of an approximation built from `property_get`.

### A2. Native DAP server (`dap` verb)

VS Code speaks the Debug Adapter Protocol. The June decision to rely on
zero-plusplus for IDE debugging still holds as the first step: install it (A8) and
use the config the fork already ships. Revisit this item when one of these bites:
zero-plusplus renders `Struct`, `JSON.Object` or typed properties wrongly, it
cannot show the `/Trace` stream or Observatory data in the Debug Console, or its
maintenance stalls on an alpha syntax change. A native adapter inside the engine
removes the middleman and renders values the way `Inspect` does.

- `AutoHotkey64Console.exe dap` serves DAP over stdio. `launch` spawns a child engine
  with `/Debug=stdio` and bridges it, so the existing debugger code is reused
  unchanged and a crash in the debuggee never takes the adapter down. `attach`
  connects to a script started with `/Debug=localhost:<port>`.
- Requests to cover first: initialize, launch, attach, setBreakpoints (with
  condition, hitCondition, logMessage from A1), setExceptionBreakpoints,
  configurationDone, threads, stackTrace, scopes, variables (lazy children,
  `Inspect`-style summaries), evaluate (watch and hover contexts), continue,
  next, stepIn, stepOut, pause, disconnect, terminate. Output events carry the
  debuggee's stdout, stderr and `/Trace` lines with a `category` so the Debug
  Console can filter them.
- A 30-line extension contribution registers debugger type `ahk-console` with
  `program: ${file}` and `engine` settings. It can live inside the Observatory
  extension so there is one install.

Files: new `source/dap_server.cpp` beside `source/mcp_server.cpp`, which already
has the stdio JSON framing. Effort: two to three weeks after A1. Risk: low, new
file only.

### A3. Land Observatory on the feature branch and release it

The worktree has `source/observatory_data.cpp`, the native viewer and extension
0.9, with 28/28 gate suites and 174 Node tests. Finish it before building more
observation features on top of it.

- Rebase the worktree's uncommitted changes onto the current branch head, run the
  gate on MSVC and GCC, merge.
- Add the extension's `npm test` and packaging to `build.yml`; attach the VSIX to
  tag releases next to the engine zips.
- Then AHKOBS v2 sections, each bounded like the existing ones: `errors` (ring of
  the last 50 thrown errors with file, line, message, caught or not), `threads`
  (the pseudo-thread stack: hotkey, timer, callback, with age), `guis` (windows
  and controls created by the script with hwnd, type, text summary and the source
  line that created them; this is the unbuilt "Phase 2: GUI bridge" from the
  stdio-supervisor plan, delivered as a passive section instead of a driver),
  `modules` (loaded modules with file and import graph), `log` (see B2).
  Producers stay passive: no getters, no callbacks.

Effort: one week to land, one week per two v2 sections.

### A4. Editor integration of Observatory data

Extension-only work on top of A3.

- **Inline values**: an `InlineValuesProvider` that shows the captured value of a
  global or static beside its assignment line while the Observatory panel targets
  that script. Locals are available only when paused under A2.
- **Hover**: hovering a global shows its captured value, type and length, with a
  "watch" action.
- **Gui tree**: a tree view from the `guis` section, double-click highlights the
  control (reuses `uia_highlight` from the MCP server).
- **Error lens**: the `errors` section decorates the throwing line with the
  message, like the Error Lens extension does for diagnostics.

### A5. Test Explorer, coverage and problems

- **Problem matcher**: a `$ahk-diag` matcher for `check --diag=json` and `run
  --diag=json` lines, so `Ctrl+Shift+B` fills the Problems pane. The record is one
  JSON object per line with `file`, `line`, `column`, `severity`, `message`; a
  regex matcher handles it without code.
- **Test Explorer**: a `TestController` that discovers `tests/*.test.ahk`, `qa/tests/`
  and the harness's `Tests/*.test.ahk`, runs `engine test` per file with
  `AHK_TEST_JUNIT` set, and maps the JUnit XML that `tests/Test.ahk` already writes
  onto per-case results. Run with `--coverage=` and feed the LCOV file to VS Code's
  native coverage API (`TestRun.addCoverage`), which gives gutters and the Test
  Coverage view with no extra extension. The installed `ahkunit` targets stock
  AHK and cannot do this.
- **Tasks**: ship a `tasks.json` template with run, check, test, trace and coverage
  tasks that use `${env:USERPROFILE}` and the problem matcher. The fork's own
  `.vscode/tasks.json` already has the twelve engine-side tasks to copy from.

Effort: one week. Engine change: none for `Test.ahk` suites; the `qa/` runner
needs the same JUnit option (`AHK_QA_JUNIT`) so both frameworks report alike.

### A6. Crash log and trace as first-class artifacts

- `/CrashLog=<path>.json` writes the crash log as JSON lines (listed as not in v1).
  An "Open last crash log" command renders it with clickable frames.
- `/Trace=json` already streams statement events. A "Replay trace" command loads a
  trace file and steps through it with the same execution markers Observatory
  uses, so a run that happened on another machine can be walked in the editor.

### A7. Hot reload

`Reload` restarts the process, which drops Observatory watches and the debug
session. A `--watch` flag on `run` reloads on source change and keeps the same
console, and the Observatory extension re-resolves watches by name and scope after
the restart (its "Not in this capture" state already models the gap). Engine work
is small: a directory watcher thread that posts the existing reload message.

### A8. Harness and workspace fixes (do first, one hour)

- Install `zero-plusplus.vscode-autohotkey-debug`; the fork's `launch.json` config
  then works as committed, and the harness `launch.json` gets a copy of it.
- Harness `tasks.json`: replace the `uphol` path with `${env:USERPROFILE}`, add
  check/test tasks.
- Workspace-wide fork declarations: set `AutoHotkey2.Syntaxes` to a folder holding
  `fork.d.ahk` (or a generated `ahk2.d.ahk` built from it) so `Print`, `JSON`,
  `Check`, `Inspect`, `ProcessPipe`, `TSParse` and `Eval` get completion and hover
  in every file, not only those with a `;@include` line.
- Branch housekeeping in the fork: decide merge or delete for `feat/native-mcp-verb`,
  `feat/mcp-ahk-in-process-server`, `docs/console-clautohotkey-site` and
  `fix/console-review-20260905`; retire the stale "Future Enhancements" list in
  `debugger-tool/mcp-server/README.md` and point the root README's AI-debugging
  section at the native `mcp` verb instead of the legacy server.

### A9. Profiler (`/Profile=<path>.cpuprofile`)

Nothing in the fork measures time. An instrumented profiler is cheap to add
because every user function call passes through one place (`Func::Call`), and
every statement through the same hook `/Trace` uses.

- `/Profile=<path>` records, per function, call count, inclusive and exclusive
  time, and the caller edge; per line, hit count and time, reusing the coverage
  line table.
- Output is Chrome's `.cpuprofile` JSON. VS Code opens that format with its
  built-in profile viewer (table, flame chart, click-through to source), so no
  extension work is required. A second flag, `/Profile=<path>.json`, writes the
  flat table for scripts and agents.
- Overhead target: under 15 percent on the `qa/` suite with `/Profile` on, measured
  by a gate test.

Files: new `source/profiler.cpp`, one hook each in `Func::Call` and the
statement-trace path. Effort: one week. Merge risk: low.

## Track B: modern language features

Each entry gives the surface, how it desugars or where it lives, the LSP impact
and the upstream-merge risk.

### Wave 1: no new syntax

**B1. Embedded standard library (`#Import Std.*`).** Alpha.17 added importing a
module from a resource. Ship curated `.ahk` modules inside the exe so `#Import
Std.Task` works on any machine with the engine and nothing else. This is the
delivery vehicle for most of wave 1 and costs the parser nothing. Candidates:
`Std.Task`, `Std.Log`, `Std.Test`, `Std.Path`, `Std.Set`, `Std.Str`. A
`--capabilities` `stdlib` array lists them. LSP impact: none once `fork.d.ahk`
declares them. Merge risk: none.

**B2. Structured logging.** `Log.Info("msg", Map("k", v))` and the other levels
write one JSON object per line to stderr by default, with timestamp, level,
message, fields, file, line and pseudo-thread. `Log.AddOutput(path | "stderr" |
"stdout")`, `Log.Level := "Warn"`. The `/Diag=json` stream and the crash log use the
same record shape, so one parser reads everything the engine emits. Observatory
gets a `log` section from a bounded ring. Native implementation in
`source/lib/log.cpp` so the hot path does no script dispatch. Merge risk: none.

**B3. Richer errors.** Three additive properties on `Error`: `Cause` (set with
`Error("msg", , , cause)` or `err.Cause := inner`, printed as a chain by the
uncaught-error report), `Frames` (the stack as an Array of `{File, Line, Function}`
objects instead of only the `Stack` string), and `Data` (a Map for arbitrary
context, serialized by `--diag=json`). Also fix the fork's report-line bug
(`error.cpp:1797`) and the truncated JSON report in the same change. Merge risk:
low; `Error` construction is in `script_object.cpp`, so keep the additions in a
separate function.

**B4. Tasks on the pseudo-thread model.** Honest async: `Task.Create(producer)`,
`task.Then(onOk, onErr)`, `Task.All`, `Task.Race`, `Task.Delay(ms)`, and
`Await(task, timeout?)`, which pumps messages like `Sleep` and is therefore an
interruption point. `ProcessPipe.ReadLineAsync`, `Download` and an `HttpRequest`
wrapper return tasks. This is exactly Keysharp's `Await` without the OS threads,
and it turns callback pyramids in GUI and pipe code into straight-line code.
Pure-AHK implementation in `Std.Task` first (`SetTimer` based), moved native only
if profiling says so. Merge risk: none.

**B5. Collections.** `Set` (membership, union, intersection), `Deque`, and a
documented statement that `Map` enumerates sorted while `JSON.Object` keeps insertion
order. Pure `Std.*` modules. Merge risk: none.

**B6. Primitive extension methods.** `Std.Str` installs `String.Prototype` methods
(`Upper`, `Trim`, `Split`, `StartsWith`, `Format`) so `name.Upper()` works. This is
supported by the engine today; the module just does it in one place. Merge risk:
none.

### Wave 2: syntax, shipped with LSP and grammar updates

**B7. Destructuring assignment.** `[a, b, rest*] := expr` and `{x, y} := obj`.
Parse-time desugar: evaluate the right side into a hidden local, then emit one
assignment per target (`a := __t[1]`, `rest := __t.Slice(3)`, `x := __t.x`).
Nested patterns recurse. Lives in a new `source/desugar.cpp` called from
`ParseAndAddLine` before expression parsing. Effort: one week. Merge risk: medium,
one hook in `script.cpp`.

**B8. Interpolated strings.** `$"Hello {name}, total {price * qty:0.2f}"`. The
`$` prefix keeps backtick escapes unchanged and avoids JS template literal
clashes. Lexer splits the literal into parts and emits the equivalent `Format`
call with the expressions as arguments. Effort: three days. Merge risk: low, one
branch in the string-literal lexer.

**B9. `switch` as an expression.** `x := switch v { 1: "one"; 2: "two"; default:
"many" }`, with `case` guards reusing the statement's comparison rules. Desugar
to a function-definition expression containing the statement form, which alpha.3
already supports. Effort: three days. Merge risk: low.

**B10. `enum`.** `enum Color { Red := 0xFF0000, Green, Blue }` desugars to a class
with static read-only members plus `Color.Names`, `Color.Values`, `Color.Parse`
and `Color.Has`. Auto-numbering continues from the previous value. Effort: three
days. Merge risk: low, it is a class declaration with a different keyword.

**B11. Parameter type annotations.** `Area(r: Number) => ...` and `Open(path:
String, mode := "r") -> File`. The parser records the type class on the
parameter; on entry the engine applies the same check typed properties already
use and throws `TypeError` with the parameter name. Return annotations are
recorded for tooling and enforced only under `#Warn TypeCheck`. This is the
feature that makes hover and completion materially better once the LSP reads it.
Effort: two weeks. Merge risk: medium; touches `FuncParam` and call setup.

**Not planned, and why.** Named arguments (`f(x := 1)` already means assignment).
Pipeline operator (low value for the cost). Real OS threads (the interpreter's
globals and `g_script` are not thread-safe; a second process plus `ProcessPipe`
covers it). Async as a keyword (B4 gives the same ergonomics without a syntax
change).

## Track C: engine groundwork

Small fixes that the tracks above assume. Each is a day or less and has a line in
the fork `CLAUDE.md` bug list. The four fixed on `fix/engine-bugs` this week are
not repeated here.

1. `&Module.Var` heap corruption: add the missing `AddRef` in `script_module.cpp:42`,
   pin it in `qa/tests/test_alpha33.ahk`, and report it upstream with the repro.
2. `WritePropertyData` buffer overlap and surrogate-pair counting (`Debugger.cpp:1476`, `:1508`).
   A1 depends on this: an `eval` that returns corrupted strings is worse than none.
3. Uncaught-error report uses `Error.Line` and `Error.File` (`error.cpp:1797`), and the
   uninitialized token at `:1778` that crashes on `throw {File, Line}`.
4. `DIAG_JSON_BUF_SIZE` becomes a growable buffer so long messages survive.
5. `Eval` `SyntaxError` gets `What`, `Extra`, `Stack` so generic catch handlers work.
6. `--help` lists `/Debug` and every `--` alias; `--capabilities` grows a `stdlib`
   array (B1) and a `profiler` flag (A9) as those land.
7. The `qa/` runner gains JUnit output to match `tests/Test.ahk` (A5).
8. `source_outline` and `workspace_symbols` learn fat-arrow functions and
   parenthesized default parameters, since A4 and A5 navigate by them.

## Milestones

| Milestone | Scope | Estimate |
| --- | --- | --- |
| M1 Foundations | A8 workspace fixes and housekeeping, Track C, A1 DBGp completion, A5 problem matcher | 2 weeks |
| M2 See the script | A3 Observatory landed and released, A5 Test Explorer and coverage, B1 stdlib vehicle, B2 Log, B3 errors | 3 weeks |
| M3 Measure and debug | A9 profiler, A4 inline values and hover, A6 crash log JSON and trace replay, B4 Task/Await, A2 only if zero-plusplus has proven limiting | 4 weeks |
| M4 Syntax wave | B7 to B10 with LSP fork and tree-sitter grammar update, then B11 | 5 weeks |
| Later | A7 hot reload, AHKOBS v2 `guis`/`modules` sections, B5/B6 collections and string methods | as time allows |

Order inside a milestone is as listed. Nothing in M2 depends on M3, so Observatory
and the stdlib can proceed while the profiler is written.

## Open decisions

- Whether to build a DAP adapter at all (A2), and if so whether it lives in the
  engine (`dap` verb) or in the Observatory extension as TypeScript over
  `/Debug=stdio`. The June decision was to rely on zero-plusplus; this plan keeps
  that until it fails a concrete test.
- The interpolated-string prefix: `$"..."` (proposed) versus a new quote character.
- Whether `Std.*` modules are compiled into the exe as resources or installed beside
  it as `Lib\Std\*.ahk`. Resources keep the single-file promise; files are easier
  to patch.
