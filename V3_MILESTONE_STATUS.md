# AHK v3 Milestones 1-3 Status

This file tracks the first three v3 milestones that were implemented as a practical baseline in this branch.

## Milestone 1 (`v3-alpha.1`) Complete

Scope:

- Stable process exit-code taxonomy
- Headless mode
- Structured JSON diagnostics
- Console-first automation behavior

Implemented:

1. Exit code mapping in `source/defines.h`:
   - `0` success
   - `10` runtime error
   - `11` critical/internal error
   - `12` parse/load error
   - `13` check/validate failure
   - `14` test failure
   - `64` CLI usage error
2. Headless mode via `/Headless` and `--headless` in `source/AutoHotkey.cpp`.
3. JSON diagnostics via `/Diag=json` and `--diag=json` in `source/AutoHotkey.cpp` and `source/error.cpp`.
4. Error/UI fallback suppression for headless paths in `source/AutoHotkey.cpp`.

## Milestone 2 (`v3-alpha.2`) Complete

Scope:

- Built-in check command
- Built-in test command
- Predictable automation outputs

Implemented:

1. Command modes:
   - `check script.ahk`
   - `/Check script.ahk`
   - `test script.ahk`
   - `/Test script.ahk`
2. Check mode wiring to validation in `source/AutoHotkey.cpp`.
3. Test mode pass/fail logic and exit behavior in `source/AutoHotkey.cpp`.
4. Optional machine-readable status lines with `/Diag=json`.

## Milestone 3 (`v3-alpha.3`) Complete

Scope:

- Advanced debugger protocol access
- Source introspection for AI tools

Implemented in MCP server:

1. Raw DBGp passthrough tool:
   - `debug_command`
   - Files: `debugger-tool/mcp-server/src/index.ts`, `debugger-tool/mcp-server/src/dbgp-client.ts`
2. Source introspection tools:
   - `source_outline`
   - `workspace_symbols`
   - File: `debugger-tool/mcp-server/src/index.ts`
3. Docs updated for new MCP tooling:
   - `debugger-tool/mcp-server/README.md`

## Quick Commands

```powershell
# Syntax check
bin\AutoHotkey64.exe check .\script.ahk

# Syntax check + JSON status/diagnostics
bin\AutoHotkey64.exe --check --diag=json .\script.ahk

# Single-script test mode
bin\AutoHotkey64.exe test .\script.ahk

# Headless runtime diagnostics (JSON)
bin\AutoHotkey64.exe --headless --diag=json .\script.ahk
```
