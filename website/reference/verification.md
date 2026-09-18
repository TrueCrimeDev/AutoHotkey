# Verification & sources

Documentation claims need a boundary. This site keeps runnable examples, observed demonstrations, and untested application behavior separate.

## Demonstration provenance

The September 17, 2026 Console executable was a local alpha.31 development build reporting `a72a652123b7-dirty`. The neutral-folder executable was verified byte-identical to that tested build. The demo used the actual ClautoHotkey plugin, real Claude Code tools, and native engine MCP calls.

The [gallery](/showcase) records 26 runtime assertions, 174 JSON trace rows, 77/84 covered lines, and the harness's partial-parse/raw-output limitations. These are fixture-specific results.

## Broader engine verification

The preceding local engine verification completed the aggregate gate on five fresh builds: MSVC x64/x86 GUI and Console targets plus MinGW x64. Each passed 11/11 suites, including the 749-assertion QA run, 54 Python tests, and 14 single-process test cases. A separate syntax sweep checked 82 scripts.

Those results belong to the tested development checkout. They do not certify a published release, hosted service, every operating environment, or every visual/desktop behavior. Documentation publication does not release that engine build.

## Source map

| Topic | Primary source |
| --- | --- |
| Engine interfaces | [Console README](https://github.com/TrueCrimeDev/AutoHotkey/blob/alpha/README.md), [fork reference](https://github.com/TrueCrimeDev/AutoHotkey/blob/alpha/updates.md) |
| Actual native tool definitions | [mcp_server.cpp](https://github.com/TrueCrimeDev/AutoHotkey/blob/alpha/source/mcp_server.cpp) |
| Builds and regression entry point | [BUILD.md](https://github.com/TrueCrimeDev/AutoHotkey/blob/alpha/BUILD.md), [console gate](https://github.com/TrueCrimeDev/AutoHotkey/blob/alpha/tests/run_console_gate.py) |
| Plugin setup and scope | [ClautoHotkey README](https://github.com/TrueCrimeDev/ClautoHotkey) |
| Hook wiring | [hooks.json](https://github.com/TrueCrimeDev/ClautoHotkey/blob/main/hooks/hooks.json) |
| Grading result schema | [CONTRACT.md](https://github.com/TrueCrimeDev/ClautoHotkey/blob/main/Tools/harness/CONTRACT.md) |
| Upstream language | [AutoHotkey v2 documentation](https://www.autohotkey.com/docs/v2/) |

Public branch links can lag the demonstrated working-tree additions; use the availability notes rather than assuming the branch contains every preview API.

## How to read a claim

- **Inspected:** reviewed source or configuration.
- **Static-validated:** executed the stated parse/lint checks, with confidence preserved.
- **Runtime-validated:** ran assertions or directly observed the stated outcome.
- **Dry-run-validated:** accepted tier-specific evidence with residual effects acknowledged.
- **Live-verified:** observed the actual target app/input result. This demo makes no blanket live claim.
