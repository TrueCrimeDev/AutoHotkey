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
| `thqby.vscode-autohotkey2-lsp` | AHK v2 language server. `.ahk` files are associated with its `ahk2` language, and `AutoHotkey2.InterpreterPath` is set for this workspace in `.vscode/settings.json`. Its `AutoHotkey2.Syntaxes` setting can point at a generated folder that teaches it the fork's built-ins in every file (see [Fork declarations for the LSP](#fork-declarations-for-the-lsp-autohotkey2syntaxes)) |
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

## Fork declarations for the LSP (`AutoHotkey2.Syntaxes`)

The language server knows the fork's built-ins (`Print`, `Eval`, `Check`,
`Inspect`, `TSParse`, `_ScriptGetLines`, `JSON`, `JSONError`, `ProcessPipe`,
`SyntaxError`) and directives (`#EnableEval`, `#CrashLog`) only when it is told
about them. `fork.d.ahk` at the repository root declares them, and a
`;@include` line loads it for one file at a time (its header explains the
forms). To get completion and hover in every file of every workspace instead,
point the extension's `AutoHotkey2.Syntaxes` setting at a folder built by
`tools/vscode/gen_syntaxes.py`:

```powershell
python tools\vscode\gen_syntaxes.py
```

It finds the newest `%USERPROFILE%\.vscode\extensions\thqby.vscode-autohotkey2-lsp-*`
(`--lsp-dir` overrides), copies that extension's `syntaxes` folder to
`%USERPROFILE%\Documents\Design\Coding\AutoHotkey\vscode-syntaxes` (`--out`
overrides), appends the declarations of `fork.d.ahk` (`--fork` overrides) to
every `ahk2.d.ahk` in the copy (the root one and `zh-cn\`), adds the fork's
directives to every `ahk2.json`, and prints the setting to apply:

```json
"AutoHotkey2.Syntaxes": "C:\\Users\\<you>\\Documents\\Design\\Coding\\AutoHotkey\\vscode-syntaxes"
```

Put it in the user `settings.json` (`%APPDATA%\Code\User\settings.json`, via
`Preferences: Open User Settings (JSON)`) so every workspace gets it, or in a
workspace `.vscode\settings.json`. The server expands `%USERPROFILE%` in the
value, so `"%USERPROFILE%\\Documents\\Design\\Coding\\AutoHotkey\\vscode-syntaxes"`
is a portable spelling. Then run `Developer: Reload Window`. The extension's
own "Select Language Definition Folder" status-bar item sets the same key.

What the server (3.0.10, `server/dist/server.js`) reads from that folder, and
why the generator starts from a copy of the extension's files:

| File in the folder | Effect |
|---|---|
| `ahk2.d.ahk` (or `<locale>\ahk2.d.ahk`) | Replaces the extension's built-in declaration file wholesale; the bundled one is read only when the folder has none |
| `ahk2.json` (or `<locale>\ahk2.json`) | Replaces the bundled directive, keyword, key, text and option list the same way |
| `*.snippet.json` (folder root) | Added to the set. The generator leaves such files alone, so your own additions survive a regeneration |
| `ahk2_h.d.ahk`, `ahk2_h.json`, `winapi.d.ahk`, `winapi.json` | Same replace rule, but read only when the interpreter is AutoHotkey_H (has `A_ThreadID`), which this fork is not |
| `ahk2_common.json`, `ahk2.tmLanguage.json` | Never read from the folder; the extension's own copies are always used |

`<locale>` is VS Code's display language in lower case (`en-us` tries `en-us\`,
then the folder root; `zh-tw` also tries `zh-cn\`). Because the replacement is
wholesale, the folder goes stale when the extension updates: **re-run the
generator after each `thqby.vscode-autohotkey2-lsp` update**. It records the
extension version in `fork-syntaxes.json` next to the files, rewrites the same
output on every run, and removes files an older extension version produced.
The server enforces `@since` tags in the file it treats as built in, so the
generator rewrites the fork's `@since 2.1-alpha.NN+Console` tags as plain
text. The server raises no diagnostic for an unknown `#` directive, so the
`ahk2.json` entries add completion and hover for `#EnableEval` and `#CrashLog`
and nothing else. `tests/test_vscode_matcher.py` (part of the console gate)
runs the generator on a stand-in extension folder.

## Tasks

Run them with `Ctrl+Shift+P` -> "Tasks: Run Task". `Ctrl+Shift+B` runs the
default build task.

| Label | What it does |
|-------|--------------|
| `Run AHK (fork, color)` | `run /Diag=json` on the active file with the console engine in a dedicated terminal, so `Print` output and ANSI colour show. An uncaught error appears as its JSON line and as a Problems entry |
| `Check AHK (fork)` | `check /Diag=json` on the active file. Exit 0 = `CHECK PASS` (warnings do not fail it); 13 = syntax error or missing file. Errors and warnings go to Problems |
| `Test AHK (fork)` | `test /Diag=json` on the active file. Exit 0 = pass; 10 = uncaught runtime error; 12 = parse error; 14 = explicit `ExitApp(14)`, a persistent script, or an exec failure. Errors go to Problems |
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

## Problem matcher for `/Diag=json`

With `/Diag=json` the engine writes each diagnostic as one JSON object on
stderr (schema 2), for `check`, `run` and `test` alike:

```json
{"kind":"diagnostic","format":"json","schema":2,"severity":"error","type":"ValueError","code":10,"message":"boom \"quoted\" \\ slash","extra":"extra \t tab","what":"Fn","file":"C:\\path\\boom.ahk","line":4,"column":0,"source":"    throw ValueError(...)","stack":"..."}
```

The key order is fixed by `FormatDiagJson` in `source/error.cpp`: `severity`
(`error`, `warning` or `critical`), `type`, `code`, `message`, `extra`, `what`,
`file`, `line`, `column`, `source`, `stack`. String values are JSON-escaped
(`\"`, `\\`, `\t`), and `column` is present on every record, parse and runtime
errors alike (0 today). The `Check AHK (fork)`, `Run AHK (fork, color)` and
`Test AHK (fork)` tasks pass `/Diag=json` and share this matcher:

```json
"problemMatcher": {
    "owner": "ahk",
    "source": "ahk",
    "fileLocation": "absolute",
    "severity": "error",
    "pattern": {
        "regexp": "^\\{\"kind\":\"diagnostic\",\"format\":\"json\",\"schema\":\\d+,\"severity\":\"(error|warning|critical)\",\"type\":\"[^\"]*\",\"code\":-?\\d+,\"message\":\"((?:[^\"\\\\]|\\\\.)*)\",\"extra\":\"(?:[^\"\\\\]|\\\\.)*\",\"what\":\"(?:[^\"\\\\]|\\\\.)*\",\"file\":\"((?:[^\"\\\\]|\\\\.)+)\",\"line\":(\\d+),\"column\":(?:0|([1-9]\\d*)),",
        "severity": 1,
        "message": 2,
        "file": 3,
        "line": 4,
        "column": 5
    }
}
```

`fileLocation: absolute` works with the escaped path (`C:\\path\\boom.ahk`)
because VS Code runs `normalize()` on it, which collapses the doubled
separators. The message is shown as the raw JSON text, so a quote inside it
reads `\"`. `column` is captured only when it is not 0, so today the whole line
is marked. `critical` is not a VS Code severity and falls back to the matcher's
`error`. Nothing else a task prints matches: script output, `CHECK PASS`,
`{"kind":"check",...}`, `/Trace=json` events, the text reports printed without
`/Diag=json`, and the debugger notice (its `file` is empty).
`tests/test_vscode_matcher.py` runs the engine on a syntax error and on an
uncaught throw and checks what the regexp captures.

For other workspaces, `tools/vscode/tasks.template.json` holds run, check,
test, trace and coverage tasks that run
`${env:USERPROFILE}\Documents\Design\Coding\AutoHotkey\bin\AutoHotkey64Console.exe`
with the same matcher; copy it to `.vscode\tasks.json`.

## Launch configurations (F5)

| Name | What it does |
|------|--------------|
| `Debug engine (C++, CMake MSVC x64 Debug console)` | Builds and debugs `out\msvc\x64_debug\AutoHotkey64Console.exe` on the active `.ahk` file |
| `Debug engine (C++, msbuild .sln GUI Debug x64)` | Legacy route: builds and debugs `bin_debug\AutoHotkey64.exe` on the active `.ahk` file |
| `Debug AHK script (DBGp, fork engine)` | Debugs the active script over DBGp with `bin\AutoHotkey64.exe`; needs `zero-plusplus.vscode-autohotkey-debug` |

Focus the `.ahk` file before pressing F5: every configuration passes `${file}`.
If a pre-launch build fails, do not choose "Debug Anyway".

The `autohotkey` configuration was checked attribute by attribute against
`zero-plusplus.vscode-autohotkey-debug` 1.11.1's `package.json`
(`contributes.debuggers[0].configurationAttributes.launch`) on 2026-10-09:
`program`, `runtime`, `args`, `useDebugDirective` and `variableCategories`
(with its `className` and `builtin` matchers) are declared there with those
types, and the adapter fills in the rest (`runtimeArgs` `["/ErrorStdOut"]`,
`port` 9002, `hostname` `localhost`, `stopOnEntry` false, `useAutoJumpToError`
false). The only fix was removing trailing commas. `runtime` is the GUI build
because the adapter starts the runtime with Node's `child_process.spawn`,
piping stdout and stderr into the Debug Console without `windowsHide`: the
console build would open an empty console window on every launch, while the
GUI build's `Print` output still arrives through the pipe. Neither exe prompts
when the adapter is not listening or goes away: the script runs on without the
debugger and only stderr says so (`Debugger error: ... continuing without the
debugger.`), which reaches the Debug Console through the same pipe. A debug
session itself has not been run from here.

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
- **Problems panel stays empty after Check**: the matcher reads the
  `{"kind":"diagnostic",...}` lines that `/Diag=json` puts on stderr, so the
  task's `args` must keep `/Diag=json`. A passing check with no warnings
  prints only `{"kind":"check","status":"pass"}`.
- **No completion or hover for `Print`, `JSON`, `Eval`, `#EnableEval`**: the
  language server does not know the fork. Generate the `AutoHotkey2.Syntaxes`
  folder and set the setting as described above, then reload the window; or
  add a `;@include` line for `fork.d.ahk` to that one file.
