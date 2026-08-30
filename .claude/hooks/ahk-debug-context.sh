#!/bin/bash
# Injects the AHK fork tooling map into Claude Code sessions.
# Fired on SessionStart (startup, resume, compact).
# Keep this in sync with what is ACTUALLY connected — a tool list that
# doesn't exist in the session is worse than no context at all.

cat <<'CONTEXT'
## AutoHotkey Fork — Tooling Map

### Engine CLI (`bin\AutoHotkey64.exe`, 2.1-alpha.30+Console)
- Run headless: `bin\AutoHotkey64.exe /ErrorStdOut script.ahk` (stdout works, exit codes propagate)
- `check script.ahk` — syntax validation (exit 13 = fail; add `/Diag=json` for structured output)
- `test script.ahk` — test runner (exit 14 = fail)
- Regression suite: `bin\AutoHotkey64.exe /ErrorStdOut qa\run.ahk` (exit = fails + crashes)
- Exit codes: 0=ok, 10=runtime, 11=internal, 12=parse/load, 13=check fail, 14=test fail, 64=CLI error
- `/Debug` — connect out to a DBGp listener on port 9000 (single listener only)
- `/Headless` — suppress all dialogs
- Fork BIFs: `Print()`, `Eval()` (needs `#EnableEval` or `/Eval`), `TSParse()`, `_ScriptGetLines()`

### MCP servers
**`ahk` (global — the main toolbox):**
- `AHK_Run` / `AHK_Lint` / `AHK_Diagnostics` — run and validate scripts
- `AHK_Debug_DBGp` — the COMPLETE DBGp debug loop in one tool. Actions:
  start/stop/status, run, step_into/over/out, capture_error, analyze_error,
  apply_fix, breakpoint_set/remove/list, variables_get, evaluate, stack_trace.
- `uia_windows` → `uia_tree` → `uia_find` → `uia_element` → `uia_highlight` —
  UI-automation funnel (read-only; act by running the returned snippet via
  AHK_Run). Invoke the `/uia` skill before UI-automation work.

**`ahk-mcp` (project — mcp.ahk running INSIDE the fork engine):**
- `ast_outline`, `get_source_context`, `workspace_symbols`, `server_status`
- Same tools from the shell: `debugger-tool\mcp-ahk\ahkmcp list` / `ahkmcp ast_outline file.ahk`
- If its tools are missing, check `/mcp` — the server must start via the WSL
  path to the exe (see .mcp.json).

### Debug workflow (AHK_Debug_DBGp)
1. `action: "start"` — listener must be up BEFORE the script runs
2. User runs: `bin\AutoHotkey64.exe /Debug script.ahk`
3. `capture_error` (blocking; call `run` first if paused) → analyze → `apply_fix` → re-run
4. Only ONE DBGp listener on port 9000: the MCP listener and VS Code F5
   debugging are mutually exclusive.

### AHK v2 syntax reminders
- Always `:=` for assignment; arrays are 1-indexed; `ComObject()` not
  `ComObjCreate()`; ByRef is `&var`; `Gui()` object syntax.
- Parentheses on EVERY function call: `Print("x")`, never `Print "x"`.
CONTEXT
