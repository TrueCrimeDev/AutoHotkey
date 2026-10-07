# Claude Code hooks for this repository

Four bash hooks give Claude the right context about this AutoHotkey fork and catch
syntax errors right after an `.ahk` edit. They are registered in the committed
`.claude/settings.json`, so every clone gets them; nothing has to be added to
`.claude/settings.local.json`. Do not register them again there or in user settings.
Claude Code drops an exact duplicate (same command text, `shell`, `args` and `if`), but
a copy written differently, such as an older path or a `bash .claude/hooks/...` form,
runs a second time. `test-hooks.sh` flags any hook reference in the local file.

Commit `de57096c` stopped tracking `.claude/settings.local.json`, so pulling it deletes a
local copy that git was tracking. If the copy had uncommitted changes, git refuses the
pull instead. If yours vanished, put only personal settings (permissions, MCP approvals)
back there. The hooks come from `.claude/settings.json`.

Requirements:

- On Windows, Claude Code runs hook commands with Git for Windows bash. The hooks use
  bash 4+, coreutils and `cygpath`. They do not need python, jq or WSL.
- The syntax gate needs a fork engine. The engines in `bin/` (`bin/*.exe`) are not in git
  (only `bin/tree-sitter-ahk.dll` is), so a fresh clone has no engine until you build one
  (see `BUILD.md`). Without one the gate is off, and the SessionStart context says so.

## Registered hooks

Each command has the form `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<script>"`.

Keep this shell form, a single command string that starts with `bash`. Do not convert
the entries to exec form (`"command": "bash"` with `args`). On Windows, exec form looks
up `bash.exe` on the Windows PATH, where the first match is the WSL launcher
`C:\Windows\System32\bash.exe`, not Git Bash. Every hook would then run under WSL or
fail.

| Event | Matcher | Script | Timeout |
| --- | --- | --- | --- |
| `SessionStart` | `""` (every start, resume, clear and compact) | `ahk-debug-context.sh` | 10 s |
| `PreToolUse` | `mcp__ahk__AHK_Debug_DBGp` | `check-ahk-connection.sh` | 5 s |
| `PostToolUse` | `mcp__ahk__AHK_Debug_DBGp` | `post-capture-guidance.sh` | 5 s |
| `PostToolUse` | `Edit\|Write\|MultiEdit\|mcp__ahk__AHK_File_Edit\|mcp__ahk__AHK_File_Create` | `ahk-post-edit.sh` | 30 s |
| `PostToolUseFailure` | `mcp__ahk__AHK_Debug_DBGp` | `post-capture-guidance.sh` | 5 s |

### Contract shared by all hooks

- **Input.** Claude Code writes one JSON object to stdin. It holds `session_id`, `cwd`,
  `hook_event_name`, `tool_name`, `tool_input` and `tool_use_id`. `PostToolUse` adds
  `tool_response`. `PostToolUseFailure` adds `error` and `is_interrupt` instead.
  - The edited path is `tool_input.file_path` for Edit, Write and MultiEdit,
    `notebook_path` for NotebookEdit, and `filePath` for `AHK_File_Edit` and
    `AHK_File_Create`.
  - On Windows paths arrive as JSON-escaped `C:\\...` strings.
- **Parsing.** The hooks read fields with bash regexes over the raw payload. A payload
  that is empty, malformed or unrelated produces no output and exit 0.
- **Output.** Output is ASCII only.
  - Context for Claude goes in `{"hookSpecificOutput":{"hookEventName":"<incoming event>","additionalContext":"..."}}`
    on stdout with exit 0. A top-level `additionalContext` is ignored by Claude Code,
    so no hook emits one.
- **Exit codes.**
  - Exit 2 from a `PostToolUse` hook shows its stderr to Claude.
  - Exit 2 from a `PreToolUse` hook would block the tool, so these hooks never do that.
  - Any other non-zero exit is reported as a non-blocking hook error.

### `ahk-debug-context.sh` (SessionStart)

Prints a context block of about 34 lines on stdout, which Claude Code adds to Claude's
context. It runs in about 0.3 s. These facts are detected at run time:

- the engine path and the first line of its `--version` (see
  [Engine resolution](#engine-resolution-and-ahk_custom_exe)), and any `bin/` exe that was
  skipped because it is not a fork engine
- whether the build has `Inspect`, `ProcessPipe` and MCP `check`/`run`/`test` (from
  `--capabilities`)
- whether the engine is a GUI build (from its PE header). PowerShell neither waits for
  a GUI exe nor sets `$LASTEXITCODE` unless its output is piped, so for a GUI build the
  PowerShell form becomes `& .\bin\AutoHotkey64.exe check /Diag=json file.ahk 2>&1 | Out-String`,
  then `$LASTEXITCODE`
- whether `.mcp.json` points at an existing fork engine

The rest is static reference material:

- the engine CLI in Git Bash and PowerShell form, and the `//Flag` rule
- the exit-code contract, including the "13 also means a missing file" and "test exits
  14 only for ..." caveats
- the `/Headless` limits
- the fork BIFs
- both MCP servers
- a three-line DBGp summary: the launch commands, which server build captures errors,
  and a pointer to `CLAUDE.md` (DBGp Protocol) for the loop. The DBGp hooks below carry
  the details, and they fire only once the debug toolset is in use.
- the hooks
- AHK v2 syntax reminders

Without a usable engine the block says why (none built, `AHK_CUSTOM_EXE` missing, or not
a fork engine), says the post-edit gate is disabled and points at `BUILD.md` or at
`AHK_CUSTOM_EXE`.

### `ahk-post-edit.sh` (PostToolUse syntax gate)

1. **Path.** It reads `file_path`, `filePath` or `notebook_path`. `AHK_File_Edit` without
   `filePath` edits the ahk server's active file, and `AHK_File_Create` may receive a
   relative path. In both cases the hook takes the absolute path from the tool's result
   text.
2. **Skips.** Each of these ends with exit 0 and no output:
   - any event other than PostToolUse
   - an `AHK_File_*` `dryRun` preview
   - a file that is not `*.ahk` (case-insensitive)
   - the intentional parse-error fixtures `test_crashlog_parse*.ahk` and `test_parse_error*.ahk`
   - a file outside the project directory (paths are compared case-insensitively after
     `cygpath -m`)
   - a file that does not exist
   - no usable fork engine

   Only project files are checked because `check` is not a sandbox: loading a script
   runs its `#DllLoad`.
3. **Check.** It runs `"<engine>" check "<C:\path\file.ahk>"` with a 25 s limit and
   captures stdout and stderr.
4. **Verdict.**
   - Engine exit 0 gives hook exit 0 with no output. Warnings never block.
   - Engine exit 12 or 13, unless the output is "Script file not found", gives hook
     exit 2. Stderr then holds `AHK syntax check failed (exit N) for <path relative to
     the project>:`, the engine output (at most 40 lines) and a hint to fix the file and
     re-check.
   - Anything else (the engine reporting "Script file not found" for a file removed
     after the hook's own existence test, a timeout or a crash) gives hook exit 1 with a
     one-line `ahk-post-edit: no check verdict ...` note. It does not block.

### `check-ahk-connection.sh` (PreToolUse on `AHK_Debug_DBGp`)

For these actions it adds a reminder through `hookSpecificOutput`:

- `capture_error`, `run`, `step_into`, `step_over`, `step_out`
- `variables_get`, `evaluate`, `stack_trace`
- `breakpoint_*`

The reminder starts with a lead line:

- for `capture_error`: it waits up to its timeout (default 30000 ms) for the next
  uncaught runtime error, and it captures only on a server with the capture fix (see
  [Debugging](#debugging-with-ahk_debug_dbgp)), which `status` shows by listing
  `error_capture`. There it returns the oldest queued error at once, even one from an
  earlier run (`clear_errors` drops those), and resumes a script paused at a breakpoint
  or throw only when nothing is queued, so after a step stops at a throw, send `run`. It
  returns early with `session_ended` or `not_listening`. A run whose end is already known
  (its error was returned, or a `run` reply said `Status: stopped`) is not reported
  again, nor is one that ended before `clear_errors` (which drops queued errors and a
  remembered end; a script that ends after it is still reported once), so the call
  waits for a relaunch and times out without one. The relaunch must wait until the old
  run has exited, since `#SingleInstance` refuses a second instance of the same script.
  An older build (`status` lists only `connected`, `port` and `errors_queued`)
  always times out with `captured:false`: run the script with `mcp__ahk-mcp__run` or
  `mcp__ahk-mcp__test` instead, or use `breakpoint_set`, `run` and `stack_trace`.
- for `evaluate`: it needs a connected, paused script. AutoHotkey's debugger has no eval
  command: a fixed server reads a variable or property path (`x`, `obj.prop`, `arr[1]`)
  and rejects operators, and an older server's `evaluate` always fails with
  `Command timeout` after 10 s. `variables_get` works on either.
- for `breakpoint_set`: it needs a connected script; pass `file` and `line` only, since
  AutoHotkey has no conditional breakpoints (a fixed server rejects a `condition` at
  once, an older one fails with `Command timeout` after 10 s).
- for every other listed action: the action needs a script connected to the DBGp
  listener.

Then it says:

- The listener (`action: start`) must already be running before the user launches the
  script with `/Debug=localhost:<port>`, the port `start` or `status` reports.
- The launch commands, `& .\bin\AutoHotkey64Console.exe /Debug=localhost:<port> /Headless script.ahk`
  (PowerShell) and `./bin/AutoHotkey64Console.exe //Debug=localhost:<port> --headless script.ahk`
  (Git Bash), with the engine the other hooks use. When there is no usable engine they
  name `./bin/AutoHotkey64Console.exe` and add why: `AHK_CUSTOM_EXE` does not exist or is
  not this fork's engine ("fix or unset AHK_CUSTOM_EXE"), or no fork engine was found
  ("build one per BUILD.md").
- With no listener on that port the engine shows a modal "continue without the
  debugger?" box, even headless. `/Headless` turns the engine's other prompts into
  stderr text. A relaunch of a script whose previous run is still alive (attached,
  paused or running) meets the default `#SingleInstance` prompt: headless, it prints
  `Another instance is already running` and exits 64 without connecting, so send `run`
  (or `stop`) and let the old run exit first.
- Once connected, the script is paused at its first line until you send `run` or a step
  (on a fixed build, `capture_error` also starts it).
- A bare `/Debug` always connects to localhost:9000. The listener uses 9000 by default
  and moves to 9001+ when 9000 is busy; only a fixed build honors `start`'s `port`
  argument.
- A VS Code AutoHotkey debug session runs its own separate listener on its own port.

Every other action gets no output. The hook never blocks.

### `post-capture-guidance.sh` (PostToolUse and PostToolUseFailure on `AHK_Debug_DBGp`)

| Result | Guidance added |
| --- | --- |
| `capture_error` returns `{"captured":false,"reason":"timeout"}` (or no `reason`) | If `status` lacks `error_capture`, the server predates the capture fix (or was not restarted after the rebuild) and never queues an error, so retrying or a longer timeout does not help. With the fix, the usual causes: how the last run ended was already known (the previous `capture_error` returned its error, a `run` reply said `Status: stopped`, or `clear_errors` ran after the script ended), so the call waited for a launch that has not happened (relaunch first); the relaunch was refused because the old run of the same script was still alive (`#SingleInstance`: under `/Headless` it prints `Another instance is already running` and exits 64 without connecting), so send `run` (or `stop`) and let the old run exit first; no uncaught error was thrown in time; or the script never connected. Check `status` (`connected`, `engine_state`, `session`, `port`) and that the script was launched with `/Debug=localhost:<port>`, the port `start` or `status` reports. Either way, run the script with `mcp__ahk-mcp__run` or `mcp__ahk-mcp__test` (or the engine CLI), or use `breakpoint_set`, `run`, `stack_trace` and `variables_get`. |
| the timeout result also has `waiting_connections` | Adds: another script (or a copy of one with `#SingleInstance Off`) connected while a script is still attached, and waits, paused at its first line, until that script ends. End the attached script, or call `stop` (which detaches every script). A relaunch of the same script is never counted here: `#SingleInstance` refuses it while the old run is alive. |
| the timeout result also has `unconfirmed_reports` | Adds: the engine printed an error report but the script kept running; it becomes a capture if the script exits with an error and is dropped on a normal exit (OutputDebug text looks the same). |
| `capture_error` returns `"reason":"session_ended"` | The script ended or detached with no further error to return; `exit` holds its final status and reason (`ok`: no unhandled error; `error`: it ended on one, usually the error already returned), and a script that ended while nobody waited is reported this way once, unless a `run` reply already said it stopped, one of its errors was returned, or `clear_errors` ran after it ended (a script that ends after `clear_errors` is still reported once). If an error was expected, run it with `mcp__ahk-mcp__run`, or set a breakpoint; to retry, have the user relaunch with `/Debug=localhost:<port>` and call `capture_error`, which waits for the new run. With `waiting_connections`, it adds that the next script is attached now, paused at its first line: call `capture_error` or `run`. |
| `capture_error` returns `"reason":"not_listening"` | Call `start`, have the user launch with `/Debug=localhost:<port>`, then call `capture_error` again. |
| `capture_error` returns `{"captured":true,...}` | Call `analyze_error` with `error` set to the captured object. It returns a Markdown prompt for Claude to analyze; there is no confidence score. `error.session` older than `status`'s `session` marks a leftover (`clear_errors` drops those). `error.line` is AutoHotkey's `Error.Line`, and `stack_trace[0]` is where the throw ran (the line this fork's own error report names); `detected_by:"stderr"` has no stack or variables, `unconfirmed:true` can be OutputDebug text, and `unverified_fields` names fields the engine may have garbled. A script that a step stopped at the throw is still paused: send `run` and let it exit before the relaunch (`#SingleInstance` refuses a relaunch of the same script while it is alive). Show the diagnosis, then call `apply_fix` with `file`, `line`, the exact current line as `original`, and `replacement`. |
| `apply_fix` returns `Fix applied at F:L` | Ask the user to re-run with `/Debug=localhost:<port>` while the listener still runs (with none on that port the engine shows a modal "continue without the debugger?" box), then call `capture_error`. The relaunched script waits paused until `run` or `capture_error`, and a fixed server reports a clean finish as `session_ended` with `exit.reason` `ok`. The old run must have exited first: while it is alive (paused, running or persistent), `#SingleInstance` refuses the relaunch (headless: `Another instance is already running...`, exit 64, never connects), and `capture_error` then times out or returns the old run's `session_ended`. So send `run` (or `stop`, then `start` again) and let it exit. Errors still queued come first (`clear_errors` drops them). `apply_fix` rewrites the whole file with LF line endings. |
| `apply_fix` fails | Re-read the line with `get_source` or the Read tool, then retry with the exact text. The failure arrives as PostToolUseFailure, or as an `Error: ...` result. |
| `evaluate`, or `breakpoint_set` with a `condition`, fails with `Command timeout` | An older server sends an `eval` command, or the condition, which AutoHotkey's debugger does not have, and never matches the reply. Read values with `variables_get`; set the breakpoint with `file` and `line` only. A fixed server reads variable and property paths and rejects a condition at once. |
| `start` replies with the old `/Debug your_script.ahk` hint, or `status` has `errors_queued` but no `error_capture` | The server predates the capture fix: `capture_error` never captures, `evaluate` (and a conditional `breakpoint_set`) fails with `Command timeout`, and `start` ignores `port`. Use `variables_get`, breakpoints and stepping or `mcp__ahk-mcp__run`, and launch with the port `start` reported. |

Everything else gets no output. MCP results flagged `isError` (`Line mismatch`,
`Not connected ...`) reach Claude Code as **PostToolUseFailure**, not PostToolUse. That
is why the hook is registered for both events.

## Engine resolution and `AHK_CUSTOM_EXE`

`ahk-post-edit.sh`, `ahk-debug-context.sh` and `check-ahk-connection.sh` (for its launch
commands) pick the engine the same way, and `test-hooks.sh` copies the rule:

1. If `AHK_CUSTOM_EXE` is set, they use only that file. If it does not exist or is not a
   fork engine, the engine counts as unavailable and the gate is off. They do not fall
   back to `bin/`.
2. Otherwise they use `bin/AutoHotkey64Console.exe`, the current console build with the
   full tool set, if it is a fork engine.
3. Otherwise they use `bin/AutoHotkey64.exe`, if it is a fork engine. This GUI build may
   be older. `check` works, but it can lack `Inspect`, `ProcessPipe`, `--coverage` and
   the MCP `check`/`run`/`test` tools.

A `bin/` exe that is not a fork engine is skipped, and SessionStart names it: `Skipped:
./bin/AutoHotkey64Console.exe is not this fork's engine (...)` when the other one is
used, or `Engine: NOT FOUND. ./bin/... is not this fork's engine (...)` when neither is.

**What counts as a fork engine.** The hooks never run a stock AutoHotkey: it reads
`check` or `--version` as a script name and shows a modal "Script file not found"
dialog. A stock copy can live anywhere, so the test (`is_fork` in each hook) looks at
the file's content, not its path:

- A Windows exe (`MZ` header) counts only if it contains the UTF-16 text `CHECK PASS`,
  which the fork's `check` verb prints and stock builds lack. The scan takes about
  20 ms. A stock exe is therefore refused wherever it is: under `Program Files`, under
  `%LOCALAPPDATA%\Programs`, in a portable or scoop folder, or copied into `bin/` under
  the fork's file name. A fork build installed under `Program Files\AutoHotkey\` is
  accepted.
- A `#!` wrapper script cannot be inspected. It is trusted unless its path looks like a
  stock install folder, in any letter case: it contains `Program Files` with an
  `AutoHotkey\` folder somewhere below it, or `AppData\Local\Programs\AutoHotkey\`.
- Anything else is refused.

When `AHK_CUSTOM_EXE` is refused:

- The gate is off and silent.
- SessionStart says `Engine: AHK_CUSTOM_EXE=<path> does not exist, so the hooks treat the
  engine as unavailable. Fix or unset AHK_CUSTOM_EXE.`, or `Engine: AHK_CUSTOM_EXE=<path>
  is not this fork's engine (a Windows exe without the fork's check verb, such as a
  stock AutoHotkey), so the hooks never run it and the gate is disabled.`
- The PreToolUse launch commands name `./bin/AutoHotkey64Console.exe` and say that
  `AHK_CUSTOM_EXE` does not exist or is not this fork's engine: fix or unset it.

Set `AHK_CUSTOM_EXE` in the environment Claude Code is started from, because the hooks
inherit it.

## MCP servers the hooks refer to

- **`ahk-mcp`** (project, `.mcp.json`)
  - Runs `./bin/AutoHotkey64Console.exe mcp`, the engine's native MCP server over stdio.
  - A current build lists `ast_outline`, `source_outline`, `workspace_symbols`,
    `get_source_context`, `check`, `run`, `test` and `server_status`.
  - It has no DBGp tools. It needs the engine built first.
  - Prefer `mcp__ahk-mcp__check`, `mcp__ahk-mcp__run` and `mcp__ahk-mcp__test` for fork
    scripts.
- **`ahk`** (user-wide Node server, registered outside this repository)
  - Only its core toolset is listed by default.
  - `AHK_Debug_DBGp` is in the `debug` toolset and `uia_*` is in the `uia` toolset. Both
    are hidden until enabled, either by `mcp__ahk__AHK_Settings
    {"action":"enable_toolset","toolset":"debug"}` (persists machine-wide in
    `%APPDATA%\ahk-mcp\tool-settings.json`) or by `AHK_MCP_TOOLSETS` in that server's
    registration. A toolset list saved by `AHK_Settings` overrides `AHK_MCP_TOOLSETS`
    until `{"action":"reset_toolsets"}` clears it. Enable a toolset only when the
    user asks.
  - Until the debug toolset is enabled, the DBGp hooks never fire.
  - Its `capture_error` captures, and its `evaluate` works, only on a build with the
    capture fix (see [Debugging](#debugging-with-ahk_debug_dbgp)).
  - This server runs scripts with the engine its `AHK_PATH` names. That is a stock
    AutoHotkey unless pointed at this fork, and stock AutoHotkey has no fork BIFs.

`debugger-tool/mcp-server/` is an older TypeScript DBGp adapter. It is not registered,
and the hooks do not target it.

## Debugging with `AHK_Debug_DBGp`

### Which server build

Error capture depends on the ahk-mcp build the `ahk` server runs:

- **With the capture fix.** It is on ahk-mcp's local branch `fix/dbgp-capture-error`
  (not pushed, and not merged into `master`), so a checkout elsewhere does not have it.
  When a script connects, the server
  sets an exception breakpoint and copies the engine's stderr. On every uncaught error
  it records the context, queues it and resumes the script, and `capture_error` returns
  it. The engine's own report of that error is not queued again, whether it names
  `Error.Line` or, as this fork's console engine does, the line the throw ran.
  `evaluate` reads variable and property paths. A running server loads a rebuilt
  `dist/` only when it restarts.
- **Without it** (ahk-mcp `master` as of 2026-10, and any older build). `queueError` is
  called only from `captureErrorContext`, and nothing calls that, so `capture_error`
  always times out with `{"captured":false,"reason":"timeout"}` and `analyze_error` is
  unreachable. `evaluate` sends an `eval` command, which AutoHotkey's debugger does not
  have, and a `breakpoint_set` `condition` goes after `--`, where the engine stops
  reading options: both fail with `Command timeout` after 10 s. `start` ignores `port`.
  `variables_get` and `apply_fix` work on either build.

`status` tells them apart. A fixed build returns `connected`, `port`, `listening`,
`engine_state`, `session`, `waiting_connections`, `errors_queued`, `reports_unconfirmed`
and `error_capture`; an older one only `connected`, `port` and `errors_queued`. The older `start` reply
says `Run your script with: AutoHotkey64.exe /Debug your_script.ahk`. The fixed one
names `/Debug=localhost:<port>` and adds `Runtime errors are captured automatically`.

### Actions

| Action | Arguments | Result |
| --- | --- | --- |
| `start` | `port` (default 9000; an older build ignores it) | `DBGp listener started on port N`: the port asked for, or the next free one when it is busy |
| `status` / `stop` | none | the fields above / stops the listener (a fixed build detaches each script first, so it keeps running) |
| `run`, `step_into`, `step_over`, `step_out` | none | needs a connected script. On a fixed build `run` returns `running` if the script has not paused within about 2 s, or `error captured, script resumed (...)`; a step that reaches a throw stays paused there |
| `breakpoint_set` / `breakpoint_remove` / `breakpoint_list` | `file`, `line` / `breakpoint_id` / none | needs a connected script. AutoHotkey has no conditional breakpoints: a fixed build rejects `condition` at once, an older one fails with `Command timeout` after 10 s |
| `variables_get` | `context` (0 local, 1 global) | needs a connected script; an object variable carries `classname` and its members in `properties` on a fixed build |
| `evaluate` | `expression`, `context` | needs a paused script. Fixed build: reads a variable or property path (`x`, `obj.prop`, `arr[1]`, `m["key"]`; a call such as `obj.Method(1)` runs script code) and rejects operators such as `a + b`, since the engine has no eval command; `type` `undefined` means not set or not found. Older build: always `Command timeout` after 10 s |
| `stack_trace` | none | needs a connected script |
| `capture_error` | `timeout` (ms, default 30000) | fixed build: the oldest queued error at once as `{"captured":true,"error":{...}}` (a script paused at a breakpoint or throw stays paused; one at its first line is started); with nothing queued it resumes a paused script and waits, then returns `"reason":"session_ended"` with `exit` and `session` when the script ends first (or ended unreported before the call: not once its error was returned, a `run` reply said `stopped`, or `clear_errors` ran after it ended), or `"reason":"timeout"` (with `waiting_connections` and `note` when another script, or a copy of one with `#SingleInstance Off`, connected while one is attached, `unconfirmed_reports` for reports not yet confirmed). `"reason":"not_listening"` at once without `start`. Older build: always `"reason":"timeout"` |
| `analyze_error` | `error` (a captured error object) | a Markdown prompt for Claude to analyze |
| `apply_fix` | `file`, `line`, `original`, `replacement` | `Fix applied at F:L`. On failure, an `isError` result such as `Line mismatch at L` (the comparison trims whitespace). It only edits `.ahk` files. |
| `get_source` | `file`, `line`, `radius` (default 5) | source lines around `line` |
| `list_errors` / `clear_errors` | none | the queued errors with their `session` (always none on an older build; a fixed build adds `unconfirmed` reports) / drops the queued errors and a remembered end (a script that ends after `clear_errors` is still reported once as `session_ended`) |

A captured `error` has `error_type`, `message`, `file`, `line`, `source_context`,
`stack_trace` (local paths), `local_variables`, `global_variables` (script functions left
out; an object variable carries `classname` and its members in `properties`),
`timestamp`, `detected_by` and `session`, plus `what`, `extra` and `ahk_stack` when the
thrown value has them (a thrown string or number has neither `what` nor `ahk_stack`, and
`ahk_stack` is also left out when the engine may have garbled it). `line` is
AutoHotkey's `Error.Line` (the caller's line when `what` names a function);
`stack_trace[0]` is where the throw ran, which is also the line this fork's own error
report (stderr, `--diag=json`) names. `detected_by:"rethrow"` is a caught error rethrown
and left unhandled, with the context of its original throw; `detected_by:"stderr"`
comes from the engine's error report alone and has no stack or variables. A report
counts only once the script exits with an error: until then it is listed under
`unconfirmed_reports` in a timeout and `unconfirmed` in `list_errors`, because
OutputDebug text in AutoHotkey's report format looks the same. `unconfirmed:true` marks
one delivered after the connection was lost without an exit notice.
`unverified_fields` (rare) names fields the engine may have corrupted.

### Debug loop (fixed build)

1. Call `start` and note the port it reports (`status` shows it later).
2. The user launches the script on that port, with `/Headless` (Git Bash `--headless`)
   so the engine's own prompts become stderr text. The `#SingleInstance` prompt runs
   before the debugger connects: a relaunch while the script's previous run is still
   alive prints `Another instance is already running. Use #SingleInstance Force or
   /force.` and exits 64 without connecting. The console engine reports an uncaught
   error on stderr and exits 10 with or without `/Headless`.
   ```powershell
   & .\bin\AutoHotkey64Console.exe /Debug=localhost:9001 /Headless script.ahk  # PowerShell
   ```
   ```bash
   ./bin/AutoHotkey64Console.exe //Debug=localhost:9001 --headless script.ahk  # Git Bash: //Debug, never /Debug
   ```
   A bare `/Debug` always means localhost:9000, which another program may hold. With no
   listener on the port (never started, stopped, or the server restarted), the engine
   shows a modal `Failed to connect to an active debugger client. Continue running the
   script without the debugger?` box, even headless: check `status` before each launch.
3. Once connected, the engine is paused at the script's first line. Set breakpoints then
   with `breakpoint_set` (`file`, `line`, no `condition`); before the script connects
   the call fails with `Not connected`.
4. Call `run`, or let `capture_error` start the script. At a breakpoint, use
   `stack_trace`, `variables_get`, `evaluate` (a variable or property path) and
   `step_into`/`step_over`/`step_out`. A step that reaches a throw stays paused there.
5. Call `capture_error`. Each uncaught error is captured and the script resumed, so the
   console engine then prints the error on stderr and exits 10. A queued error
   comes back at once and leaves a script paused at a breakpoint or throw paused: after
   a step stopped at the throw, send `run` (or call `capture_error` again) so the script
   can finish.
6. Call `analyze_error` with that error, show the user your diagnosis, then call
   `apply_fix` with the exact current line as `original`.
7. Let the old run exit first: send `run` if it is still paused, or `stop` (which
   detaches it; call `start` again before the relaunch), and close a persistent script.
   While it is alive, `#SingleInstance` refuses the relaunch (exit 64, never connects),
   and `capture_error` times out or returns the old run's `session_ended`. Then the user
   relaunches with the same `/Debug=localhost:<port>`, and `capture_error` waits for that
   run: a clean finish returns `session_ended` with `exit.reason` `ok`. Call
   `clear_errors` before the relaunch if errors from the old run may still be queued,
   since `capture_error` returns those first. If a `run` reply already said
   `Status: stopped`, that run is over and is not reported again: relaunch before calling
   `capture_error`, or it waits out its timeout.

On an older build, skip steps 5 and 6, and read values with `variables_get` instead of
`evaluate`: for a runtime error's message, line and stack, run the script with
`mcp__ahk-mcp__run` or `mcp__ahk-mcp__test` (or the engine CLI) and read its
diagnostics, or break before the failing line.

Another script (or a copy of one with `#SingleInstance Off`) that connects while one is
attached waits, paused at its first line, until the first one ends (`status` shows
`waiting_connections`; so do a `capture_error` timeout and the first script's
`session_ended` result). A relaunch of the same script never gets that far while its
previous run is alive: `#SingleInstance` refuses it before it connects. On a fixed
build, `stop` and the server shutting down detach every script first, so it keeps
running without the engine's "continue without the debugger?" prompt; a server that is
killed cannot detach, and the script then shows that prompt. There are no watch
expressions.

## Running the tests

```bash
bash .claude/hooks/test-hooks.sh        # from Git Bash, in the repository root
```

```powershell
& "$env:ProgramFiles\Git\bin\bash.exe" .claude/hooks/test-hooks.sh
```

`test-hooks.sh` runs each hook the way Claude Code does: `bash <hook>`, a JSON payload on
stdin and `CLAUDE_PROJECT_DIR` exported. It asserts the exit code, stdout and stderr
separately.

What it covers:

- Registration: the entries in `settings.json` match the table above, and there are no
  stray or doubly registered scripts.
- Hook files: LF-only ASCII, with no python, jq or WSL calls.
- Payloads with `C:\`, `C:/` and `/c/` paths, from Edit, Write, MultiEdit, NotebookEdit,
  `AHK_File_Edit` and `AHK_File_Create`.
- Malformed input.
- Every skip rule.
- Engine selection, including a missing `AHK_CUSTOM_EXE`.
- Stock AutoHotkey refusal, both branches of the fork-engine test:
  - Fake `#!` engines in `Program Files\AutoHotkey\` and
    `AppData\Local\Programs\AutoHotkey\`, which log every call.
  - Non-executable `MZ` lookalikes of a stock exe (no UTF-16 marker), at a portable
    path, at a stock install path, and as `bin/AutoHotkey64Console.exe`. No hook may run
    them, fall back to `bin/` from a refused `AHK_CUSTOM_EXE`, or offer them as a command,
    and SessionStart and PreToolUse must name the cause.
  - Acceptance by content: a copy of the real fork engine under a
    `Program Files\AutoHotkey\v2\` path runs.
- The GUI-build PowerShell form (`2>&1 | Out-String`).
- Verdict mapping.
- Output caps.
- JSON shape, which is validated by a small bash parser.

Requirements and behavior:

- It needs no jq or python, and writes only to a private `mktemp -d` directory that it
  deletes. `TMPDIR` is honored; the output caps that could see a copied engine's path
  (the SessionStart DBGp section) count only the fixed text, so a long `TMPDIR` does not
  change the verdict.
- Most cases use throwaway fake engines. A few need the real fork engine, picked the way
  the hooks pick it, including the same fork-engine test. The harness never runs a file
  that fails that test. Those cases are skipped, with a loud warning, only when no fork
  engine is usable.
- The exit status is the number of failed cases. 255 means the harness could not start.
- Set `NO_COLOR=1` for plain output.

`test-hooks-gui.ahk` runs the same harness through Git for Windows bash and lists the
results. It is a GUI: start it yourself. An agent should run `test-hooks.sh` directly and
only `check` the GUI file.

## Troubleshooting

- **"python3 not found" or a Microsoft Store prompt.** These hooks do not use python. An
  error like that comes from some other hook, registered in another settings file.
- **`Script file not found` from engine commands in Git Bash.**
  - Git Bash rewrites a bare `/Flag` argument into a path: `/Diag=json` becomes
    `C:/Program Files/Git/Diag=json`.
  - Use the aliases `--diag=json`, `--headless`, `--coverage=`, `--trace`, `--eval`,
    `--crashlog=` and `--stderrfile=`.
  - `/Debug`, `/ErrorStdOut` and `/include` have no alias. Double the slash (`//Debug`,
    `//ErrorStdOut`, `//include`) or run them from PowerShell.
  - For example, from Git Bash:
    ```bash
    ./bin/AutoHotkey64Console.exe check --diag=json script.ahk   # 0 pass, 13 syntax error
    ```
    With `--diag=json`, diagnostics arrive as NDJSON (one object per line) on stderr,
    and the pass marker `{"kind":"check","status":"pass"}` goes to stdout. Read both
    streams.
  - `check` also exits 13 for a missing file, so read the message.
- **`$LASTEXITCODE` does not change after the GUI `AutoHotkey64.exe` in PowerShell.**
  PowerShell does not wait for a GUI exe unless its output is piped. Use the console
  exe, or pipe: `& .\bin\AutoHotkey64.exe check /Diag=json file.ahk 2>&1 | Out-String`.
- **The syntax gate never reports anything.**
  - The SessionStart context says whether the gate is enabled. Usual causes:
    - no fork engine in `bin/`
    - `AHK_CUSTOM_EXE` names a missing file, or an exe that is not a fork engine (a stock
      AutoHotkey anywhere)
    - the file is outside the project, not `.ahk`, or a fixture name
  - Run `bash .claude/hooks/test-hooks.sh` to see which rule applies.
- **`ahk-post-edit: no check verdict ...`.** The engine produced neither a pass nor a
  syntax verdict. It may have timed out, crashed, or not found the file. The edit stands.
- **`AHK_Debug_DBGp` is not available.** The `debug` toolset of the `ahk` server is hidden
  by default. Enable it only if the user asks (see above).
- **`Not connected to AutoHotkey debugger`.** Possible causes:
  - `start` was not called.
  - The script was not launched with `/Debug` (or, in Git Bash, `//Debug`).
  - The listener moved to another port. `status` shows the port; launch with
    `/Debug=localhost:<port>`.
  - `breakpoint_set` was called before the script connected.
- **The port moved to 9001+.** Another program was already listening on 9000, for
  example another DBGp client or an earlier listener that is still running.
- **`capture_error` always returns `captured:false`.** Check `status`. Without
  `error_capture`, the `ahk` server predates the capture fix or was not restarted after
  `dist/` was rebuilt, and it never queues errors (see
  [Which server build](#which-server-build)). Retrying or a longer timeout does not help:
  run the script with `mcp__ahk-mcp__run` / `mcp__ahk-mcp__test` and read its
  diagnostics, or use breakpoints and stepping. Restarting that server is the user's
  call. With `error_capture`, a timeout means this run's error was already returned and
  the script exited (relaunch first), the relaunch was refused by `#SingleInstance`
  because the old run was still alive (`Another instance is already running`, exit 64:
  let the old run exit, then relaunch), another script is waiting behind an attached one
  (`waiting_connections`), no uncaught error was thrown in time, or the script never
  connected (wrong port).
- **`evaluate` or a conditional `breakpoint_set` fails with `Command timeout`.** The
  server predates the capture fix. Use `variables_get`, and set breakpoints without a
  `condition`.
- **`apply_fix` reports `Line mismatch`.** Re-read the line with `get_source` or Read, and
  pass it exactly as `original`.
- **A hook runs twice.** A differently written copy of it (another path, or a
  `bash .claude/hooks/...` form) is registered in `.claude/settings.local.json` or in user
  settings. Claude Code drops only exact duplicates. Remove the copy.
- **`.claude/settings.local.json` disappeared after a pull.** Commit `de57096c` untracked it
  (see the top of this file). Do not copy the hooks back into it.
- **Every hook fails, or runs WSL bash.** Someone converted a registration to exec form.
  Restore the shell form `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<script>"`.
- **CRLF in hook scripts.** `.gitattributes` checks `*.sh` out with LF, and the test
  harness fails on CR bytes.
