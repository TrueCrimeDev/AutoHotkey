# Feature verification — September 17, 2026

The current working source passes the complete native regression gate on five freshly built executable variants. Additional feature checks found and fixed one native MCP status bug. The default installed `ahk` executable remains outdated, and `/Headless` still permits script-created message boxes.

All results below were executed locally on Windows. The source revision is `a72a652123b7-dirty`; this includes the pre-existing uncommitted feature work, plus the small MCP fix and regression described below. No remote release or CI run is implied.

## Final build and test matrix

| Fresh executable | Compiler / architecture | Aggregate gate | QA assertions | Python test cases | Single-process cases |
|---|---|---|---|---|---|
| `bin_review/AutoHotkey64Console.exe` | MSVC / x64 | 11/11 | 749 passed | 54 passed | 14 passed |
| `bin_review/AutoHotkey64.exe` | MSVC / x64 | 11/11 | 749 passed | 54 passed | 14 passed |
| `bin_review/AutoHotkey32Console.exe` | MSVC / x86 | 11/11 | 749 passed | 54 passed | 14 passed |
| `bin_review/AutoHotkey32.exe` | MSVC / x86 | 11/11 | 749 passed | 54 passed | 14 passed |
| `temp/feature-verification-20260917/gcc/AutoHotkey64.exe` | GCC 15.2 / x64 | 11/11 | 749 passed | 54 passed | 14 passed |

Each gate also passes the three Eval enablement/gating scripts. All final gate processes exited 0, with zero QA failures or crashes. Counts repeat the same scenarios across builds; they are not counts of distinct features or a percentage of engine coverage. Builds succeeded with compiler warnings, including existing macro redefinitions and GCC volatile warnings.

The main runtime coverage includes:

- Alpha.31 language features, typed Structs and pointer access, removed syntax, Print, and Eval opt-in behavior.
- Native JSON parsing, serialization, mutation, error cases, and JSONTestSuite fixtures.
- Inspect primitives, containers, classes, native controls, cycles, limits, and property inspection without invoking getters.
- ProcessPipe UTF-8 streams, argument quoting, exit codes, timeouts, cleanup, large output, and simultaneous input/output pressure.
- CLI identity/capabilities, diagnostics, exit codes, REPL persistence and recovery, trace output, and LCOV behavior.
- Native MCP protocol validation and check/run/test execution, including bounded timeouts.
- QA-runner failure detection and descendant cleanup; single-process test framework and Check behavior.

## Additional checks

| Check | Result |
|---|---|
| Repository syntax checker | 82/82 selected AHK files parse |
| Native MCP file tools and status, MSVC x64 | 7/7 after fix |
| Native MCP file tools and status, GCC x64 | 7/7 after fix |
| Script MCP JSON tests | 38/38 |
| Script MCP tool tests | 16/16 |
| Script MCP protocol tests | 27/27 |
| Tree-sitter DLL and TSParse builtin smoke tests | Both pass on x64 |
| Check builtin, engine CLI parity, and host-state preservation | Pass |
| DBGp stdio regression | Pass; init, output stream framing, asynchronous break, stop; zero raw stdout contamination |
| PowerShell 5.1 and 7 with a temporary alias wrapper pointing to the fresh console executable | 10 test methods pass across both shells |
| JUnit output | XML parsed; 14 testcase records, zero failures/errors |
| QA with per-child LCOV enabled | 749 passed, zero failures/crashes |
| LCOV merge and badge generation | Pass; 156/218 lines (71.6%) for the selected AHK test harness files only |
| Legacy Node MCP server TypeScript | `tsc --noEmit` passes |
| Error-agent TypeScript | `tsc --noEmit` passes using the already-installed sibling project's Node type definitions |
| Whitespace check | `git diff --check` passes |

The syntax checker intentionally excludes scratch/history/build paths and deliberately invalid manual fixtures. The coverage percentage above describes `qa/Assert.ahk`, `qa/Harness.ahk`, and `tests/Test.ahk`; it does not measure C++ interpreter coverage.

## Bug found and fixed

Native `tools/list` advertised eight tools, while `server_status.toolsRegistered` reported five. Additional black-box checks reproduced the mismatch on both MSVC and GCC builds.

`source/mcp_server.cpp` now derives the status count from the actual tool registry instead of a hardcoded value. `tests/test_mcp_protocol.py` adds `test_server_status_tool_count_matches_discovery`, which queries both endpoints in one server session. It failed with `5 != 8` before the fix and passes afterward as part of all five final gates. The independent seven-case file-tool checks also pass on both x64 compiler builds after the fix.

These were the only engine/test source edits made during this verification. Existing uncommitted work was preserved.

## Remaining issues and limits

1. **The normal `ahk` command still launches an old executable.** `bin/AutoHotkey64Console.exe` reports alpha.30, revision `ed3ce0a8e580-dirty`, and passed only 5/11 suites against the current pre-fix tests. Its newer MCP execution tools, JSON trace mode, coverage flag, and alpha.31 requirements fail the current checks. Both installed PowerShell profiles and the repository alias wrapper confirm the same outdated executable. The fresh wrapper passes. Both x86 installed launchers are also alpha.30; the installed x64 GUI executable is alpha.31 from `ef2047d49c32`, before the current feature additions. The four installed executable hashes were verified unchanged; fresh MSVC builds are available in `bin_review/`.

2. **`/Headless` does not suppress an explicit script `MsgBox`.** A bounded probe using `MsgBox(..., "T1")` under `/Headless` returned `Timeout` after 1.14 seconds. This confirms the limitation already noted in the project worklog; README wording promising suppression of every interactive prompt is too broad. This behavior was recorded, not changed.

3. **This is not a complete desktop or external-service certification.** GUI-subsystem gates exercise the engine's automated behavior, not visual rendering, physical keyboard/mouse input, DPI/multiple monitors, elevated applications, or arbitrary third-party applications. Live LLM/provider requests and remote deployment were not tested. The bundled tree-sitter DLL is x64-only, so grammar tests were limited to x64. Legacy WSL differential conformance was not used; the Windows-native supplemental file-tool checks cover its core file-tool parity scenarios, not all its encoding/junction cases.

## Reproduce and inspect evidence

From the repository root:

```powershell
python tests/run_console_gate.py bin_review/AutoHotkey64Console.exe
python tools/check_all.py bin_review/AutoHotkey64Console.exe
python tests/test_mcp_protocol.py bin_review/AutoHotkey64Console.exe McpProtocolTests.test_server_status_tool_count_matches_discovery
python temp/feature-verification-20260917/test_native_file_tools.py bin_review/AutoHotkey64Console.exe
python tests/test_powershell_cli.py --wrapper temp/feature-verification-20260917/fresh-ahk.ps1
```

Local evidence is in `temp/feature-verification-20260917/` (ignored by Git):

- `final-matrix.json`: exact commands, exit codes, durations, versions, and SHA-256 hashes for the five final executables.
- `final-*.log`: complete post-fix aggregate output for each build.
- `binaries-before.json` and `installed-binaries-preserved.json`: installed/review binary inventory and unchanged installed-binary verification.
- `mcp-tool-count-red.log`, `native-file-tools-*-green.log`: reproduction and passing supplemental checks.
- `supplemental-results.json`, `supplemental.log`, and per-check logs: additional test commands/results, including expected failures from the outdated installed executable.
- `junit.xml` and `coverage/`: actual JUnit and LCOV artifacts.
- `headless-msgbox.json`: bounded headless-dialog observation.
- `mcp_server.before.cpp` and `test_mcp_protocol.before.py`: snapshots of the pre-existing working files before the small fix/regression.
