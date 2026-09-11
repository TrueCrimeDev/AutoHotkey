# Building AutoHotkey with _ScriptGetLines

**GCC (mingw-w64) is the primary local compiler for this fork.** MSVC produces the
Windows x64 and Win32 release binaries. Both compiler routes must pass the native
regression gate before CI creates a draft release.

## Prerequisites

- [MSYS2](https://www.msys2.org) with the mingw-w64 toolchain
- After installing MSYS2, in the MSYS2 shell:
  ```bash
  pacman -S mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja
  ```

## Quick Build (Windows)

1. From the repo root (WSL or a Windows shell), run the helper script:

   ```cmd
   build.bat
   ```

   Append `clean` to force a fresh configure; set `MSYS2_ROOT` if MSYS2 isn't at `C:\msys64`.

2. Output will be in `bin\AutoHotkey64.exe`. The build tree lives in `build_gcc/`.

CI verifies this route via the `build-mingw` job in `.github/workflows/build.yml`. The GCC
binary is statically linked (~3.2 MB). There is no Clang path — the sources only fork on
`_MSC_VER` vs mingw GCC.

## Alternative: MSVC (Visual Studio)

Smaller binary (~1.3 MB) with full SEH crash-log fidelity; this is what the CI `release` job
ships. Requires Visual Studio 2022 or Build Tools 18 with the *C++ Desktop Development* workload.

1. Use the repo helper script, which auto-detects the toolchain:

   ```cmd
   build_local.bat
   ```

   If only Visual Studio Build Tools 18 is installed, you can also run `build_vs18.cmd`.

2. Manual build — open **Developer Command Prompt for VS 2022** and run:
   ```cmd
   msbuild AutoHotkeyx.sln /p:Configuration=Release /p:Platform=x64
   ```

3. Or via the **Visual Studio GUI**: open `AutoHotkeyx.sln`, select **Release** / **x64**,
   then Build > Build Solution (Ctrl+Shift+B).

4. Output in `bin\AutoHotkey64.exe`.

For an isolated build while the current executable is running, use CMake and Ninja
from a Visual Studio developer prompt for the desired architecture:

```cmd
cmake -S . -B build_review -G Ninja -DCMAKE_BUILD_TYPE=Release -DAHK_OUTPUT_DIR=bin_review
cmake --build build_review --target AutoHotkey64 --parallel 6
python tests/run_console_gate.py bin_review/AutoHotkey64.exe
```

Use a separate build directory and the `AutoHotkey32` target from an x86 developer
prompt for Win32. CMake embeds the Git revision (with `-dirty` for source changes).
Builds without Git may supply `-DAHK_BUILD_REVISION=<revision>`; other build routes
report `unknown` unless they define `AHK_BUILD_REVISION` themselves.

For an attached terminal process, explicitly build the additional console target
from the same configured CMake tree:

```cmd
cmake --build build_review --target AutoHotkey64Console --parallel 6
python tests/run_console_gate.py bin_review/AutoHotkey64Console.exe
```

Use `AutoHotkey32Console` in the separate x86 tree. These targets are excluded
from the default build and use the console subsystem; the existing GUI targets
keep their launch behavior. For the `ahk` PowerShell alias, place the x64 console
executable in `bin/` beside its dependencies and dot-source `tools/ahk.ps1`.
Validate that registration in PowerShell 7 and Windows PowerShell 5.1 with
`python tests/test_powershell_cli.py --wrapper tools/ahk.ps1`. Omit `--wrapper`
to validate the installed user profiles instead. Unicode pipeline tests explicitly
select UTF-8; Windows PowerShell 5.1 uses its native quoting and encoding rules.

## Build Configurations

| Config | Platform | Output |
|--------|----------|--------|
| Release | x64 | `bin\AutoHotkey64.exe` |
| Release | Win32 | `bin\AutoHotkey32.exe` |
| Debug | x64 | `bin_debug\AutoHotkey64.exe` |

## Verify the built engine

Run the same aggregate gate used before CI uploads artifacts (Python 3.11+):

```powershell
python tests/run_console_gate.py bin/AutoHotkey64.exe
```

The gate runs all `qa/tests/test_*.ahk` files, the existing Eval/gating scripts,
and the Python QA-runner, CLI, REPL, and native MCP protocol suites against that
exact executable. Every suite must pass.
It waits for the GUI-subsystem executable's process exit and applies an outer
180-second timeout to each suite. QA children have their own 30-second timeout and
run with `/Headless`; override it with `AHK_QA_TIMEOUT_MS` (1–300000 milliseconds).

CI runs the gate on MSVC x64, MSVC Win32, and MinGW x64. Release artifacts continue
to use MSVC. The bundled `tree-sitter-ahk.dll` is **x64 only**; download it beside
the x64 executable for grammar/AST tools. Win32 supports the engine and native MCP
protocol, but cannot load that grammar DLL. Native MCP protocol tests do not rely
on grammar tools, so they run on every supported build.

## Troubleshooting

**MSBuild not found**: Use `build_local.bat` or `build_vs18.cmd`, or make sure you're using a Visual Studio developer prompt instead of regular `cmd`.

**Build errors**: Ensure you have the C++ workload installed in VS Installer.

**Missing SDK**: Install Windows 10/11 SDK via VS Installer.
