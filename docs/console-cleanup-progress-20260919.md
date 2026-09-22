**Implementation ledger — plan: docs/console-code-review-20260919.md**

The user approved proceeding on 2026-09-19. Existing working-tree changes are preserved; a baseline copy and patch are retained under `temp/cleanup-20260919`. The earlier review document remains a record of the pre-fix findings.

Ruling: implement in the current working tree because the reviewed features include substantial uncommitted and untracked user work. A clean HEAD worktree would omit the code being repaired. No automatic commits, publication, installed-binary replacement, or deletion of old artifacts.

Ruling: use bounded regression cases from the review before module extraction. Keep compiler-specific and unverified ownership concerns distinguishable from fixed reproductions. Preserve the public APIs unless the previous behavior is the reviewed defect.

Work allocation:

- Process/MCP: R03, R05, R06, R07, R12, R16, R17; process and native resource ownership.
- Runtime: R02, R04, R08, R09, R11; debugger, evaluation, and coverage interactions.
- Build: R01, R15; fresh Console CI/artifacts, build-local manifest, entrypoint compilation, wrapper configuration, documentation.
- Integration: R10, R13, R14; JSON policy, shared TypeScript framing/cleanup, module extraction, aggregate gates, cross-build validation.

Pre-flight shared interfaces: child-process capture limits affect MCP results and Check integration; runtime output changes must survive module extraction; new source modules require both CMake and VCX project registration. The parent coordinates builds after edits are ready.

Baseline executable: `bin_review_20260919/AutoHotkey64Console.exe`; its identity and failing observations are in the review report. Final binaries are isolated under `out/cleanup/{msvc/x64,msvc/x86,mingw/x64}/bin`.

Implemented changes:

| Review items | Implementation |
| --- | --- |
| R01, R15 | CI builds and checks fresh Console executables, packages GUI/Console, verifies artifact hashes, generates capabilities/tool manifests, and gates both debugger clients. No vendored executable assumption. |
| R02, R08 | Debugger-aware Print; separate raw protocol output; cancellable idle stdio watcher and prompt EOF diagnostics, including explicit GCC stderr flush. |
| R03, R05, R06 | Bounded alternating pipe reads; message-loop yielding; handle-based process liveness; exit code 259 preserved; job termination after launcher exit; mandatory job assignment and explicit inherited-handle list. |
| R04 | Terminated, codepoint-aware crash-log conversion with bounded truncation. |
| R07, R12, R16, R17 | CLI option terminator; root-preserving path normalization; numeric bounds; unmatched-surrogate request IDs escaped without changing their value. |
| R09, R11 | One owned Eval input buffer; catchable limit at 16,384 UTF-16 code units; synthetic source line 0; synchronized coverage with cached loaded-source metadata. |
| R10 | Parse and ParseAt enforce scalar policy using JSON provenance, independent of native singleton representation. |
| R13, R14 | Shared byte-framed DBGp decoder; direct waiter delivery or queueing; timeout/disconnect cleanup; old-socket event isolation; packaged shared dependency. |

Structural cleanup:

- Extracted `console_eval.cpp`, `console_repl.cpp`, `console_output.cpp`, `console_check.cpp`, and `ts_api.cpp`; `error.cpp` decreased from 3,151 to 1,958 lines relative to the saved baseline.
- Extracted `inspect.cpp` with its own public header and shared internal JSON formatting; `json.cpp` decreased from 2,439 to 1,991 lines. Both Inspect callers now use one rendering entry point.
- Check uses the same process ownership/capture runner as MCP, with a 30-second deadline and 8 MiB capture cap. It preserves `{Ok, Diagnostics, Raw}` and reports timeout/output-limit failures explicitly. Raw combines stderr then stdout.
- Native file/tree/process resources have scoped cleanup; ChildProcess copying is disabled. JSON.Object Clear/Delete detach storage before releasing callback-capable values; Delete also releases copied string storage.
- CMake compiles the common engine once, with distinct entrypoints for GUI/Console/Harness. Generated manifests are build-local; Console is built by default. Visual Studio sources/headers/filters match the extracted modules.
- The Windows/WSL native/script MCP conformance runner discovers shared tools instead of requiring an obsolete total of five. The PowerShell wrapper accepts an explicit engine; tests exercise that exact executable.
- TypeScript clients share `@ahk/dbgp-protocol`. Their package allowlists include compiled modules, and bundled dependencies preserve standalone tarball use; dry-run pack listings were inspected.

Behavior contracts now documented in BUILD.md and CLAUDE.md: Eval input limit; Check deadline/capture limit; MCP default 30-second timeout, range 1–600,000 ms, 8 MiB combined raw capture; `outputLimitExceeded`/`captureLimitBytes`; ProcessPipe pumping and process-tree behavior. Help preserves runtime error codes for `test` rather than incorrectly promising only 0/14.

Validation record:

- Reproduced targeted failures against the saved baseline before changing behavior. JSON scalar policy, runtime boundaries, process/MCP boundaries, and TypeScript framing/queues had failing controls.
- Built GUI and Console with MSVC x64, MSVC x86, and GCC x64 after extraction. Final outputs were rebuilt after the GCC diagnostic flush.
- Syntax checker accepted 108/108 repository AHK files on the extracted x64 build.
- Clean `npm ci --ignore-scripts` and TypeScript builds passed for both clients. Final client tests pass 6/6 and 3/3; shared framing tests pass 3/3.
- The shared QA script is single-instance. Parallel local architecture gates collided and were discarded; final release gates run sequentially. Shell timeout failures from that parallel run were not hidden by increasing timeouts.
- GCC EOF detection itself worked, but its CRT buffered stderr until exit. A bounded timing/thread observation isolated the cause; explicit flushing fixed the unchanged 3-second regression.
- Independent integration review caught two suites relying on a pre-existing repository `temp/` directory after manifest generation moved into the build directory. They now use system temporary directories. The updated REPL suite (12/12) and shell suite (10/10, both available PowerShell versions) passed against the final MSVC x64 binary.

Final local verification:

| Build | GUI and Console compilation | Console gate | Native/script MCP conformance |
| --- | --- | --- | --- |
| MSVC x64 | Passed | 14/14 suites | 60/60 checks |
| MSVC x86 | Passed | 14/14 suites | Not run: matching grammar DLL unavailable |
| GCC/MinGW x64 | Passed | 14/14 suites | 60/60 checks |

Each Console gate includes QA (749 passed, 0 failed, 0 crashed), framework tests (16/16), runtime regressions (11/11), process/MCP regressions (10/10), and shell tests against the exact executable. These final gates ran sequentially. Logs are `temp/cleanup-20260919/release-gate-{msvc-x64,msvc-x86,mingw-x64}.log`; final conformance logs are `conformance-{msvc,mingw}-final.log`. The final post-review test-only reruns are `repl-final.log` and `shell-final.log` in that directory.

All three Console outputs report `2.1-alpha.31+Console`, revision `d4f28347a3cc-dirty`. Adjacent `*.capabilities.json` manifests record the compiler, architecture, hash, capabilities, and eight registered MCP tools. Hashes identify these local dirty-tree artifacts; the Git revision alone does not reproduce them.

| Console output under `out/cleanup/` | SHA-256 |
| --- | --- |
| `msvc/x64/bin/AutoHotkey64Console.exe` | `6148b4580862527548daa647b456dfa2c201a983ee6b29683845bc5ee30aa341` |
| `msvc/x86/bin/AutoHotkey32Console.exe` | `39ea21036eeb0cb47ad7273c5a37c000b375c1834491b35abc4fb946f9aab823` |
| `mingw/x64/bin/AutoHotkey64Console.exe` | `f58ee2af63f6f68c2a804388fc1c153e6264406b8b8d4782794d08a76467ef99` |

To use the verified MSVC x64 executable from a PowerShell session in the repository:

```powershell
. ./tools/ahk.ps1 -EnginePath ./out/cleanup/msvc/x64/bin/AutoHotkey64Console.exe
ahk --version
```

Final independent integration review found no further actionable issue after the temporary-directory correction. Package dry-run listings contain the compiled debugger clients and bundled shared framing dependency. Workflow YAML and Visual Studio project XML parse locally, and `git diff --check` reports no whitespace errors.

Retained follow-ups and evidence limits:

- Compiled Eval programs remain in process-lifetime storage. Temporary input ownership and input bounds are fixed, but safe reclamation requires an owned compiled-program arena retained by generated functions/closures. Resetting SimpleHeap or imposing a silent cumulative limit would change semantics. Dynamically compiling a closure that captures caller locals remains an existing unsupported case.
- This pass does not claim a complete callback/reentrancy audit of every JSON.Object mutation/destruction path or change AHKMON access policy. Clear/Delete were hardened; those broader inspected-only issues remain separate from R01–R17.
- x86 native/script AST conformance needs a matching 32-bit tree-sitter DLL, which this checkout does not provide. x64 conformance uses the tracked 64-bit DLL beside the tested engine.
- Remote GitHub CI/release execution and installed `bin` replacement are outside this local verification. The existing installed alpha.30 binary is not evidence for these changes; use the isolated output or explicit wrapper engine selection.
