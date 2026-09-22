**AHK Console custom-code review — 2026-09-19**

The first priority is to fix correctness at feature boundaries: subprocess lifetime, output routing, debugger framing, and evaluation. Structural cleanup should follow those fixes, with regression tests preserving the behavior. Several reproducible defects are absent from the current passing gate.

This is a review of the current working tree, including existing uncommitted changes, against upstream `v2.1-alpha.31`. No production source was changed during this review. Source locations below refer to that working tree and will move after edits.

| Review boundary | Coverage |
| --- | --- |
| Native custom delta | 53 tracked source paths; 8,497 added and 306 removed lines relative to upstream |
| New native files | Six untracked files: `child_process`, `process_pipe`, and `coverage`, each with a source/header pair |
| Major features | CLI/headless behavior, diagnostics, Print, Check, Eval, REPL, JSON/Inspect, native MCP, child processes, DBGp transports, crash logs, and coverage |
| Supporting code | Build/release workflow, test gate and QA, shell wrapper, legacy TypeScript debugger clients, script MCP conformance harness, and documentation consistency |
| Runtime target | Fresh MSVC x64 Release Console executable built from the reviewed working tree |
| Limits | No fresh x86 or GCC build, remote CI execution, exhaustive fuzzing, or complete review of unchanged upstream engine internals |

The fresh executable is `bin_review_20260919/AutoHotkey64Console.exe`. It reports `AutoHotkey v2.1-alpha.31+Console`, revision `d4f28347a3cc-dirty`, MSVC `195035719`, x64. SHA-256: `1A1CDA5B162C59E92D9D4CB7F59FFE1C975F2E273EFF4466A3D59FF1E57F9F40`. Because this is a dirty tree, the commit ID alone does not reproduce the binary.

Validation completed: fresh build succeeded; `tests/run_console_gate.py` passed **11/11 suites**, including QA **749 passed, 0 failed, 0 crashed** across 12 files and **14/14** framework cases. `tools/check_all.py` accepted **108/108** files. The failures below came from additional focused probes or direct source inspection; a passing gate does not cover them.

**Findings, ordered by repair priority**

**R01 — P1: Clean-checkout syntax CI requires an executable it never obtains.** Source-verified; remote CI was not run. `.github/workflows/build.yml:23–24` invokes `tools/check_all.py bin/AutoHotkey64.exe` directly after checkout and Python setup. The only tracked file under `bin` is `tree-sitter-ahk.dll`. This job has neither a build nor an executable download. Run this check after building the intended engine, or fetch an explicitly identified bootstrap artifact. Do not rely on a developer's local `bin` directory. The checker itself is also currently untracked and must be included when this work is committed.

**R02 — P1: Print corrupts the stdio debugger protocol.** Reproduced on the fresh binary. `source/error.cpp:2436–2445` writes directly to stdout, bypassing `g_Debugger.OutputStdOut`. With `/Debug=stdio`, `Print("hello")` inserts literal `hello\n` between DBGp length-prefixed XML packets. The equivalent `FileAppend` uses a proper `<stream>` packet. A script using the primary Console output function can therefore break its debugger connection. Route ordinary script output through the debugger hook; keep a separate raw writer for protocol-owned packets. Console-view mirroring uses the same affected path.

**R03 — P1: Pipe pumping can prevent timeout checks and monopolize execution.** Finite reproduction plus source-inspected consequences. `source/child_process.cpp:185–209` drains a pipe until it becomes empty, appending all output without a byte budget, deadline, or yield. Callers check deadlines only after pumping (`source/process_pipe.cpp:144–157`, `source/child_process.cpp:308–320`). A bounded 32 MiB producer made `Wait(0.001)` return successful completion after 62 ms while collecting 33,554,432 bytes. A continuously producing child was not tested; source inspection shows it can keep the drain loop occupied, delaying timeout handling and the other stream. Use bounded pumping slices, alternate stdout/stderr, check deadlines between slices, and impose a documented MCP output-capture limit.

**R04 — P2: Long crash-log fields become unterminated strings.** Reproduced on the fresh binary. `source/crashlog.cpp:58–62` ignores a failed `WideCharToMultiByte` conversion. Fixed buffers in `LogError` are subsequently formatted as null-terminated strings. A normal Error containing 3,000 ASCII characters produced 2,048 characters followed by adjacent stack-buffer text in the Message field. Guarantee termination on every path and handle truncation at a valid UTF-8 boundary, or use explicitly sized converted text. This is an out-of-bounds string read, not simply intentional truncation.

**R05 — P2: Exit code 259 is mistaken for a running process.** Reproduced on the fresh binary. `source/child_process.cpp:237–241` uses `GetExitCodeProcess(...) == STILL_ACTIVE` as its liveness test, but 259 can also be an actual exit code. After `ExitApp(259)`, the PID no longer existed, while `Running` remained true, `ExitCode` was -1, and bounded `Wait()` timed out. MCP reported a timeout and exit code 0 for the already-completed script. Test process-handle signaled state with `WaitForSingleObject(..., 0)`, then read the actual exit code.

**R06 — P2: Kill does not stop descendants after their launcher exits.** Reproduced on the fresh binary. `source/child_process.cpp:247–250` returns when the original process has exited, before terminating its job. A child launcher exited successfully; its grandchild survived `p.Kill()` and terminated only when `p` was released. Terminate an owned job regardless of root-process state. Reserve the root liveness check for the fallback path without a job.

**R07 — P2: MCP check can succeed without checking the requested file.** Reproduced on the fresh binary. `source/mcp_server.cpp:1242–1244` quotes the filename but does not terminate CLI option parsing. `check({"file":"--version"})` returned `ok:true`, exit code 0, and engine-version output. Add `--` before the filename; the CLI already supports it at `source/AutoHotkey.cpp:340–345`. Test option-shaped filenames as well as spaces and quotes.

**R08 — P2: Stdio debugger commands cannot wake an idle persistent script.** Reproduced on the fresh binary, with a bounded 800 ms observation. `StdioTransport` in `source/DebugTransport.h:75–86` inherits the no-op `ExitSyncMode` at line 52. The socket transport has a notification mechanism; stdio does not. Command availability is checked during statement execution at `source/Debugger.cpp:226`. After running an idle `Persistent()` script, a `status -i 2` command received no response while the process stayed alive. Add a cancellable reader/watcher which notifies the main thread, including disconnect handling.

**R09 — P2: Valid large Eval input terminates the host despite try/catch.** Reproduced on the fresh binary. `source/error.cpp:2272–2274` and `source/script.cpp:5523–5525` both copy the complete expression using unbounded `_alloca`. An expression consisting of 350,000 spaces followed by `1+2` exited 11 with a recursion-limit diagnostic; neither the catch block nor the next statement ran. Use bounded input validation that produces a catchable error, or heap-backed scratch buffers, and remove the duplicate copy. Changing these two copies alone does not establish that every downstream parser stack allocation is bounded.

**R10 — P2: JSON.Parse and JSON.Validate disagree about forbidden top-level scalars.** Reproduced on the fresh binary. `source/json.cpp:1567–1572` classifies scalars by the runtime token being non-object. Native true, false, and null are represented by object singletons, so they bypass `AllowTopLevelScalar:false`. Validate uses the JSON syntactic kind at `source/json.cpp:1873–1887` and rejects them. With `{AllowTopLevelScalar:false, Booleans:"native", Null:"native"}`, Parse accepted all three while Validate rejected them; numeric/container controls behaved consistently. Use a shared JSON value-kind decision, independent of runtime representation.

**R11 — P2: Eval-generated functions produce nonexistent source lines in coverage.** Reproduced on the fresh binary. `source/coverage.cpp:113–119` treats nonzero parser line numbers as real source lines. A four-line script creating and calling `Eval("()=>42")` emitted `DA:5,1` in LCOV. Assign synthetic source identity to dynamically generated code or exclude it from ordinary file coverage; do not inherit a stale loader line number.

**R12 — P2: Drive-root normalization changes the requested workspace.** Reproduced on the fresh binary. `source/mcp_server.cpp:1161–1164` trims `C:\` to `C:`, changing an absolute drive root into that drive's current directory. With a controlled working-directory fixture, requesting `C:\` scanned the fixture while the response still echoed the requested root. Preserve drive/UNC roots during normalization and test root paths explicitly.

**R13 — P2: The legacy TypeScript DBGp client corrupts fragmented Unicode and emits length headers as messages.** Reproduced by directly importing the current TypeScript source and feeding synthetic protocol packets. `debugger-tool/mcp-server/src/dbgp-client.ts:96–115` decodes each network chunk independently, then splits on NUL without honoring byte lengths. A packet containing `café`, split within the UTF-8 character, produced two messages: `"60"` and XML containing `caf��`. The length-prefix regex cannot match because its NUL has already been removed. Keep a byte buffer, parse the ASCII byte count, wait for the complete frame, and decode only its payload. The separate parser in `debugger-tool/ahk-error-agent/src/index.ts:102–135` also mixes byte lengths and JavaScript string lengths; that related path was source-inspected, not dynamically verified.

**R14 — P2: The legacy error queue duplicates delivery and retains timed-out waiters.** Reproduced against the current TypeScript source. `debugger-tool/mcp-server/src/dbgp-client.ts:357–368` enqueues an error and also delivers it to a waiting consumer, leaving the same error available for the next wait. At lines 383–391, timeout cleanup searches for `resolve` although the stored callback is a wrapper, so it is never removed. The probe observed one waiter after timeout and the same error delivered twice. Deliver directly to a waiter or enqueue, and retain/remove the same callback identity. Also remove `sendCommand` message listeners on timeout/disconnection; its current timeout path at lines 130–143 only rejects the promise.

**R15 — P2: CI and releases omit the actual Console executable.** Source-verified; no release was performed. `CMakeLists.txt:251` marks Console `EXCLUDE_FROM_ALL`. The workflow performs default builds at lines 58 and 110, gates the GUI executable at lines 61 and 113, and publishes GUI executables at lines 235–237. That does not validate or deliver the distinct shell-facing Console target. Explicitly build, gate, and publish Console for the supported architectures. Keep GUI/Harness roles documented, and add PowerShell wrapper tests against the exact produced Console artifact.

Two smaller native MCP defects were also reproduced: **R16, P3**, context-radius arithmetic at `source/mcp_server.cpp:858–859` overflows for `line:1, radius:9223372036854775807`, yielding empty context for a nonempty file; integer conversion at lines 592–609 also needs range handling. **R17, P3**, an accepted JSON-RPC string ID containing `\ud800` is returned as `\ufffd` through serialization at lines 334–335. Reject invalid scalar sequences consistently or preserve accepted IDs with escapes rather than silently changing correlation IDs.

**Additional ownership and concurrency work — inspected, not reproduced as current-build failures**

- `JsonObject::ClearItems`, `source/json.cpp:615–623`, frees keys/values before resetting the count and index. Releasing a script object can invoke user code. Compare upstream Map cleanup at `source/script_object.cpp:706–725`, which explicitly updates state before callback-capable releases. Audit clear/delete/destruction reentrancy and detach storage before releasing its contents. No dynamic lifetime/reentrancy stress was performed for this review.
- Eval uses process-lifetime `SimpleHeap` allocations for arguments, text, and token data at `source/script.cpp:5542–5572`. The older `a72a652123b7-dirty` build grew private memory from 2,998,272 to 24,039,424 bytes across 100,000 identical Eval calls. That measurement was not repeated on the fresh build, although the allocation strategy remains. Introduce owned evaluation storage while preserving returned closures and references into compiled expressions.
- The console-control handler calls `Coverage::Flush()` at `source/crashlog.cpp:315–325`, while normal execution mutates coverage vectors. There is no corresponding synchronization in `Coverage::Hit`/`Flush`. Coordinate a snapshot or main-thread flush; keep failure-path work bounded. No concurrent shutdown stress was run.
- File and tree-sitter resources in `source/mcp_server.cpp:489–504` and `793–820` depend on manual cleanup. A throwing allocation can skip handle/parser/tree release even though the RPC layer catches the exception. Use scoped owners. Delete copying on `ChildProcess`, which owns raw handles.
- `source/child_process.cpp:57–83` does not enforce job-configuration/assignment success, so documented tree-cleanup guarantees can silently weaken. Define explicit fallback/error behavior. Use an explicit inherited-handle list rather than inheriting every inheritable handle in the host.
- AHKMON's repeated views can consume its fixed output buffer and omit the end sentinel. Its handler at `source/script2.cpp:270` precedes the `g_AllowMainWindow` guard at line 927. Define the access policy and cap/deduplicate requested views. The earlier suspicion of a buffer overrun was not supported: `sntprintf` clamps its returned written length. No IPC stress was performed.

**Cleanup plan**

| Order | Change | Reason and completion boundary |
| --- | --- | --- |
| 1 | Repair CI and binary identity | Build the real Console target, run the gate against its exact path, include shell/protocol tests, publish that same binary and its hash. A clean checkout must work without local artifacts. |
| 2 | Fix R02–R14 with focused regressions | Preserve finite, bounded reproductions for framing, lifecycle, options, paths, JSON policy, crash logging, Eval, and coverage. Confirm fixes on supported compiler/architecture targets. |
| 3 | Extract Console feature modules | Move Eval, REPL, Check/subprocess validation, tree-sitter access, and output routing out of `error.cpp`; move Inspect out of `json.cpp`. Keep existing API registration and narrow engine integration points. |
| 4 | Centralize resource ownership | Share child-process lifetime and scoped native handles across ProcessPipe, MCP, and Check. Give dynamic evaluation an explicit ownership model. Keep protocol bytes separate from script-output routing. |
| 5 | Consolidate protocol contracts | Share DBGp byte framing across TypeScript consumers; centralize waiter/cancellation cleanup. Share JSON edge-case vectors without blindly combining runtime JSON and the standalone MCP parser, which preserves numeric ID lexemes and runs without script initialization. |
| 6 | Simplify builds and documentation | Use build-local generated files and explicit output directories; document GUI/Console/Harness responsibilities. Generate feature/tool lists from capabilities/registries, keep portability changes separate, and retire superseded adapters only after migration checks. |

The largest concentration is `error.cpp`, with 1,789 fork-added lines covering multiple unrelated subsystems. `json.cpp` is 2,439 lines including Inspect; `mcp_server.cpp` is 1,724 lines including framing, JSON, AST operations, directory walking, and process execution. Splitting these by ownership and runtime dependencies will make upstream merges and testing easier. Avoid file moves mixed with semantic fixes: first establish tests and repair behavior, then extract modules in reviewable changes.

There are three executable targets compiling substantially the same source set. A shared object/static-library arrangement can reduce build duplication where compile definitions genuinely match; isolate entrypoint differences instead of assuming all objects are interchangeable. Move the generated manifest from `${CMAKE_SOURCE_DIR}/temp` (`CMakeLists.txt:172–185`) into the build tree so concurrent configurations do not share a generated output. Prefer `out/<compiler>/<architecture>/<configuration>` or a similarly explicit convention over accumulating ambiguous `bin_*` and `build_*` folders. Inventory retained artifacts before deleting anything.

Documentation and compatibility cleanup should include these concrete items:

- The legacy native/script MCP conformance harness expects exactly five tools at `debugger-tool/mcp-ahk/tests/conformance_native.py:142–143,188`; the current native registry has eight. Split shared compatibility expectations from native-only capabilities and make the runner work directly on Windows. The current native `server_status` count is already derived from the registry; the historical five-versus-eight server-status defect is not a current finding.
- Help promises test exit codes 0/14, but an uncaught Error currently exits 10. Choose and document the contract; runtime-error code 10 may be correct, so do not blindly remap it.
- The canonical local `bin/AutoHotkey64Console.exe` still reports alpha.30, while the reviewed fresh binary is alpha.31. `tools/ahk.ps1` points at the canonical `bin` location. Installation/wrapper verification must be a separate step from passing tests against `bin_review_20260919`.
- Refresh legacy architecture guidance, old binary-version references, the MCP comment claiming no native JSON parser, and BUILD.md's draft-release description against the current workflow (`draft: false`). Keep GCC-specific exception behavior and portability changes explicit rather than presenting compiler targets as behaviorally identical without tests.

**Retained evidence**

Scratch probes and local logs are under `temp/review-20260919` (ignored by Git). The report is durable; the scratch directory is not a committed regression suite.

| Evidence | Contents |
| --- | --- |
| `build-current.cmd`, `build-current.log` | Isolated current-tree MSVC x64 Console build |
| `fresh-console-gate.log` | Complete fresh-binary 11/11 aggregate gate output |
| `runtime/fresh-probes.json` | Print/FileAppend DBGp comparison, idle debugger, large Eval, and dynamic-coverage probes |
| `runtime/verdict-probes.json`, `runtime/long-crash.log` | Test exit contract and long crash-log field reproduction |
| `runtime/fresh_coverage_expr.lcov` | Nonexistent line 5 attributed to a four-line file |
| `mcp/results-fresh.json` | Exit 259, descendant lifetime, CLI option filename, drive root, numeric radius, and request-ID results |
| `mcp/fairness.ahk`, `mcp/flood.ahk` | Bounded 32 MiB output/timeout reproduction |
| `json_options.ahk`, `json-options-results.txt` | Parse/Validate option disagreement with scalar/container controls |
| `legacy_dbgp_review.mjs`, `legacy-dbgp-results.txt` | Direct current-source tests for fragmented UTF-8, timeout cleanup, and duplicate error delivery |

Recommended first implementation batch: R01/R15 to make fresh Console verification reliable, then R02/R03/R04/R05/R06/R07 before structural extraction. This review did not change production behavior, delete old implementations, commit changes, or publish a release.
