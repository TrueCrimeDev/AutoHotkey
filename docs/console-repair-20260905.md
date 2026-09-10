# Local Alpha 30 Console repairs — September 5, 2026

The repaired x64 and x86 executables are installed in `bin/`. The previous x86
executable was alpha 18; both now report `2.1-alpha.30+Console`. The work remains
local on branch `fix/console-review-20260905`, with uncommitted source changes.
Nothing was published or deployed remotely.

## Changes users can use now

| Change | Result |
|---|---|
| REPL/Eval parser recovery | Unmatched delimiters produce `SyntaxError` before parsing; the next expression still runs. Failed assignments preserve existing variable lookup order. |
| Inline functions | Runtime-created fat-arrow bodies have their references resolved before execution. The formerly crashing maybe-operator example now matches normal script behavior. |
| JSON editing | Array assignment, insertion, removal, resizing, capacity changes, and cloning preserve current values and untouched boolean/null types. |
| JSON REPL results | Full strings, embedded NULs, Unicode, blank input, help, and exit use valid JSON result records. Normal script output, including startup output, uses stderr. |
| Input handling | Initial UTF-8 BOMs and CRLF work; invalid UTF-8 produces an error and the next input remains available. |
| Command discovery | `--help`, `--version`, and `--capabilities` work without loading a script. Global flags may precede commands; usage errors explain what to correct. |
| Native JSON errors | Unterminated comments fail consistently. NUL-containing keys raise `UnsupportedKey` instead of silently colliding. Failed nested parses release unfinished child values. |
| Local MCP compatibility | Request envelope and ID types are checked, notifications remain silent, and initialization negotiates supported protocol versions. |
| Test reliability | Empty suites and summary/exit mismatches fail. QA children have deadlines and job-based descendant cleanup. |

The local workflow definition also requires these tests before producing build
artifacts; that workflow was edited but was not run remotely.

## Verification

Both installed executables passed **8/8 aggregate suites**, each comprising:

- 586 AHK assertions across nine QA files, with zero failures or crashes.
- 35 process-level tests: CLI (7), REPL (12), MCP (9), QA runner (7).
- Three existing Eval scripts, covering the directive, default-disabled behavior,
  and the `/Eval` command-line flag.

The installed x64 executable also passed `test_tsparse_bif.ahk` and
`test_check_bif.ahk`. Reproductions were checked against the old build before the
fixes, including the REPL failures, JSON mutations, and runner false-pass path.
Independent source reviews covered JSON ownership/array mutation hooks and the
runtime parser/REPL changes. The final delimiter check also rejects incomplete
fat-arrow input before it can create function state.

Build: local MSVC 195035719, CMake/Ninja, Release, for x64 and x86. The embedded
source identity is `ed3ce0a8e580-dirty`. MinGW and remote CI were not run during
this local installation.

Run the same checks:

```powershell
python tests/run_console_gate.py bin/AutoHotkey64.exe
python tests/run_console_gate.py bin/AutoHotkey32.exe
```

Captured installation checks are in `temp/installed_console_gate_x64.log` and
`temp/installed_console_gate_x86.log`. `bin/console-build-20260905.json` records
the executable sizes, hashes, capabilities, grammar dependency, and changed-source
file hashes.

## Installed files and backups

| File | SHA-256 |
|---|---|
| `bin/AutoHotkey64.exe` | `fd48270e562ecc6f0f341b869ee9a92d23241f1fa88e93d67fe7405724a8df68` |
| `bin/AutoHotkey32.exe` | `5e84d7d7995d65af8d38bc5b55f407ef9130ef46eb8fd7ea4469ee5f72300296` |

Previous executables are preserved as `bin/AutoHotkey64.previous-20260905.exe`
and `bin/AutoHotkey32.previous-20260905.exe`. Installation preserved all four
pre-existing script processes. New launches use the repaired executables;
already-running scripts pick them up on their next restart.

## Remaining opportunities

The REPL still accepts single-line expressions. Multiline editing, saved command
history, session inspection, project watching, and cancellable source search are
future functionality, not part of these repairs. Long-session scratch allocation
and oversized-expression resource use need a separate review. The supplied
tree-sitter grammar DLL is x64 only and can still misclassify fork-specific syntax;
`Check()` uses the engine's own parser for authoritative syntax validation.

For explicit JSON boolean/null assignments, use `JSON.True`, `JSON.False`, and
`JSON.Null`. Assigning a number or string intentionally replaces the parsed type.
NUL characters remain supported in string values, while NUL-containing object
keys are unsupported. Explicit `ExitApp` or fatal process failure can end a REPL
session before its next result is emitted.
