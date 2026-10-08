# VS Code Setup - Quick Reference

The workspace configuration lives in `.vscode/tasks.json`, `.vscode/launch.json`,
`.vscode/settings.json` and `.vscode/extensions.json`. Engine tasks use the
fork's console build, `bin\AutoHotkey64Console.exe`. The engines in `bin\`
(`bin\*.exe`) are gitignored (only `bin\tree-sitter-ahk.dll` is tracked), so a
fresh clone has no engine until you build one (see `BUILD.md`).

## Extensions

`.vscode/extensions.json` recommends these, so VS Code offers to install them
when the folder is opened (or search `@recommended` in the Extensions view).

| Extension | Needed for |
|-----------|------------|
| `thqby.vscode-autohotkey2-lsp` | AHK v2 language server. `.ahk` files are associated with its `ahk2` language, and `AutoHotkey2.InterpreterPath` is set for this workspace in `.vscode/settings.json` |
| `zero-plusplus.vscode-autohotkey-debug` | The `autohotkey` debug type used by the "Debug AHK script" launch configuration. The thqby extension has no debugger of its own and asks for one |
| `ms-vscode.cpptools` | The `cppvsdbg` engine-debugging launch configurations, and the `$gcc` problem matcher of the `build.bat` task |
| `ms-vscode.cmake-tools` | The optional CMake Tools integration configured by the `cmake.*` keys in `.vscode/settings.json` (`configureOnOpen` is off). The build tasks call `cmake` directly and do not need it |

`AutoHotkey2.InterpreterPath` points at `bin\AutoHotkey64.exe`, the GUI build,
so the language server can start it without opening a console window. It can
lag `bin\AutoHotkey64Console.exe` when only one of them is rebuilt, so compare
their `--version` and `--capabilities` (since 2026-10-08 both are the CI build of
`f14d7427`, `2.1-alpha.33+Console` revision `f14d74270a2b`). The extension's own Run command uses it and shows output in the
OUTPUT panel without ANSI colour; use the `Run AHK (fork, color)` task for the
console engine.

## Tasks

Run them with `Ctrl+Shift+P` -> "Tasks: Run Task". `Ctrl+Shift+B` runs the
default build task.

| Label | What it does |
|-------|--------------|
| `Run AHK (fork, color)` | Runs the active file with the console engine in a dedicated terminal, so `Print` output and ANSI colour show |
| `Check AHK (fork)` | `check` on the active file. Exit 0 = `CHECK PASS` (warnings do not fail it); 13 = syntax error or missing file. Errors and warnings go to Problems |
| `Test AHK (fork)` | `test` on the active file. Exit 0 = pass; 10 = uncaught runtime error; 12 = parse error; 14 = explicit `ExitApp(14)`, a persistent script, or an exec failure |
| `QA suite (fork)` | `qa/run.ahk` with `/Headless /ErrorStdOut` (default test task). Exit code = failing assertions + crashes |
| `Console gate (choose engine)` | `python tests/run_console_gate.py <engine>` against an engine you pick; needs Python on PATH |
| `build (CMake, MSVC x64 -> out/msvc/x64)` | Supported route from `BUILD.md` (default build task); builds GUI and Console into `out\msvc\x64` and does not touch `bin\` |
| `build-debug (CMake, MSVC x64 -> out/msvc/x64_debug)` | Debug console engine for the C++ launch configuration (CMake appends `_debug` to the output directory) |
| `build (CMake, MSVC Win32 -> out/msvc/Win32)` | 32-bit variant of the supported route |
| `build (build.bat, mingw -> bin, overwrites bin)` | Convenience route; overwrites both `bin\` engines (stop the ahk-mcp server and any running `bin\` engine first). Needs MSYS2 at `%MSYS2_ROOT%` (default `C:\msys64`) |
| `build (msbuild .sln, GUI only -> bin)`, `rebuild (msbuild .sln, GUI only -> bin)`, `build-debug (msbuild .sln, GUI only, x64 -> bin_debug)` | Legacy Visual Studio solution route; GUI executable only |

The MSVC tasks run through `vsc-build-env.cmd`, which finds Visual Studio with
`vswhere`. They need Visual Studio 2022 or Build Tools 18 with the C++ desktop
workload, plus CMake and Ninja for the CMake tasks (MSYS2 for `build.bat`). The
build tasks mirror `BUILD.md` but have not been run end to end from VS Code.

`/Headless` only redirects error and warning dialogs to stderr. `MsgBox`,
`InputBox` and GUI windows still block a task until you close them.

## Launch configurations (F5)

| Name | What it does |
|------|--------------|
| `Debug engine (C++, CMake MSVC x64 Debug console)` | Builds and debugs `out\msvc\x64_debug\AutoHotkey64Console.exe` on the active `.ahk` file |
| `Debug engine (C++, msbuild .sln GUI Debug x64)` | Legacy route: builds and debugs `bin_debug\AutoHotkey64.exe` on the active `.ahk` file |
| `Debug AHK script (DBGp, fork console engine)` | Debugs the active script over DBGp with `bin\AutoHotkey64Console.exe`; needs `zero-plusplus.vscode-autohotkey-debug` |

Focus the `.ahk` file before pressing F5: every configuration passes `${file}`.
If a pre-launch build fails, do not choose "Debug Anyway".

The DBGp configuration has not been tried here, because the debug extension is
not installed on the machine where it was written. If each launch opens an
extra console window, set its `runtime` to `${workspaceFolder}/bin/AutoHotkey64.exe`
(the GUI build; see the caveat under Extensions). Neither exe prompts when the
adapter is not listening or goes away: the script runs on without the debugger
and only stderr says so (`Debugger error: ... continuing without the
debugger.`), which the GUI exe has nowhere to show.

Port notes: the zero-plusplus adapter listens on 9002 by default, and thqby
merges its `AutoHotkey2.DebugConfiguration` port range (`9002-9100`) into the
launch. The user-wide `ahk` MCP server's DBGp listener (`AHK_Debug_DBGp`, in
the debug toolset that is hidden by default) starts at 9000 and moves to 9001+
when busy, so the two normally coexist. The project's `ahk-mcp` server (the
engine's native `mcp` verb) has no DBGp tool.

## Keyboard shortcuts (optional, user-level)

The repository ships no shortcuts: VS Code reads keybindings only from your
**user** `keybindings.json`, not from the workspace. To add some, run
"Preferences: Open Keyboard Shortcuts (JSON)" and add entries that use the
current task labels (pick keys that are free in your setup):

```json
[
  {
    "key": "ctrl+f13",
    "command": "workbench.action.tasks.runTask",
    "args": "Run AHK (fork, color)",
    "when": "editorLangId == ahk2"
  },
  {
    "key": "alt+f13",
    "command": "workbench.action.tasks.runTask",
    "args": "Check AHK (fork)",
    "when": "editorLangId == ahk2"
  }
]
```

## Troubleshooting

- **"Configured debug type 'autohotkey' is not supported"**: install
  `zero-plusplus.vscode-autohotkey-debug`.
- **An engine task fails to start because the executable does not exist**:
  build the engine (`BUILD.md`), then check that `bin\AutoHotkey64Console.exe`
  exists.
- **An MSVC build task stops with "unable to locate build tools"**:
  `vsc-build-env.cmd` found no `vswhere.exe` or no Visual Studio installation
  with the C++ tools. If it gets past that and then fails to run `cmake` or
  `ninja`, they are not on PATH. See `BUILD.md` for the required toolchain.
- **Problems panel stays empty after Check**: the matcher reads
  `file (line) : ==> [Warning: ]message` lines from stderr. A passing check
  with no warnings prints only `CHECK PASS`.
